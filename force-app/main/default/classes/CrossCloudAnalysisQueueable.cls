/**
 * @description Async job: analyses cross-cloud patterns, generates Agent_Suggestion__c records.
 * @author      Contextual Agent Memory
 * @version     1.0
 */
public class CrossCloudAnalysisQueueable implements Queueable {

    private Id                              memoryId;
    private AgentMemoryService.MemoryContext ctx;

    private static final Map<String, CrossCloudTemplate[]> SUGGESTION_TEMPLATES =
        new Map<String, CrossCloudTemplate[]>{
            'Sales Cloud' => new CrossCloudTemplate[]{
                new CrossCloudTemplate(
                    'Service Cloud',
                    'Based on recent sales activity for this account, consider setting up ' +
                    'a proactive onboarding case in Service Cloud to ensure customer success.',
                    'AgentMemory_CreateOnboardingCase',
                    75.0
                ),
                new CrossCloudTemplate(
                    'Marketing Cloud',
                    'A new deal was closed or progressed in Sales Cloud. Trigger a ' +
                    'welcome/nurture journey in Marketing Cloud to accelerate adoption.',
                    'AgentMemory_TriggerNurtureJourney',
                    70.0
                )
            },
            'Service Cloud' => new CrossCloudTemplate[]{
                new CrossCloudTemplate(
                    'Sales Cloud',
                    'A case was resolved positively. This is a strong upsell signal — ' +
                    'create a follow-up opportunity task in Sales Cloud.',
                    'AgentMemory_CreateUpsellTask',
                    80.0
                ),
                new CrossCloudTemplate(
                    'Marketing Cloud',
                    'Customer had a service interaction. Enroll them in a re-engagement ' +
                    'or satisfaction survey journey in Marketing Cloud.',
                    'AgentMemory_EnrollSatisfactionJourney',
                    65.0
                )
            },
            'Marketing Cloud' => new CrossCloudTemplate[]{
                new CrossCloudTemplate(
                    'Sales Cloud',
                    'High engagement detected in a Marketing Cloud journey. ' +
                    'Auto-create a Sales Cloud outreach task for this contact.',
                    'AgentMemory_CreateOutreachTask',
                    85.0
                )
            }
        };

    public CrossCloudAnalysisQueueable(Id memoryId, AgentMemoryService.MemoryContext ctx) {
        this.memoryId = memoryId;
        this.ctx      = ctx;
    }

    public void execute(QueueableContext qCtx) {
        try {
            List<Agent_Memory__c> memories = AgentMemorySelector.getByEntityIds(
                new Set<String>{ ctx.entityId }
            );
            if (memories.isEmpty()) return;

            Agent_Memory__c memory     = memories[0];
            Decimal         confidence = calculateConfidence(
                memory.Pattern_Count__c, memory.Memory_Strength__c
            );
            List<Agent_Suggestion__c> suggestions = buildSuggestions(memory, confidence);

            if (!suggestions.isEmpty()) {
                SObjectAccessDecision dec = Security.stripInaccessible(
                    AccessType.CREATABLE, suggestions
                );
                insert dec.getRecords();
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'CrossCloudAnalysisQueueable failed: ' + ex.getMessage());
        }
    }

    private List<Agent_Suggestion__c> buildSuggestions(
            Agent_Memory__c memory, Decimal baseConfidence) {

        List<Agent_Suggestion__c> results   = new List<Agent_Suggestion__c>();
        CrossCloudTemplate[]      templates = SUGGESTION_TEMPLATES.get(ctx.cloudSource);
        if (templates == null) return results;

        List<Agent_Suggestion__c> existing =
            AgentMemorySelector.getPendingSuggestionsForEntity(ctx.entityId);
        Set<String> existingTargets = new Set<String>();
        for (Agent_Suggestion__c s : existing) {
            existingTargets.add(s.Target_Cloud__c);
        }

        for (CrossCloudTemplate tmpl : templates) {
            if (existingTargets.contains(tmpl.targetCloud)) continue;

            Decimal adjustedConfidence = Math.min(99.9,
                baseConfidence * (tmpl.baseConfidence / 100.0));
            if (adjustedConfidence < 40.0) continue;

            results.add(new Agent_Suggestion__c(
                Name                = 'Cross-Cloud: ' + ctx.cloudSource + ' → ' + tmpl.targetCloud,
                Source_Cloud__c     = ctx.cloudSource,
                Target_Cloud__c     = tmpl.targetCloud,
                Suggestion_Body__c  = tmpl.body + enrichWithContext(memory),
                Confidence_Score__c = adjustedConfidence,
                Status__c           = 'Pending',
                Entity_Id__c        = ctx.entityId,
                Agent_Memory__c     = memory.Id,
                Flow_API_Name__c    = tmpl.flowApiName,
                Expires_At__c       = System.now().addHours(72)
            ));
        }
        return results;
    }

    private String enrichWithContext(Agent_Memory__c memory) {
        if (String.isBlank(memory.Intent_Tags__c)) return '';
        return ' [Intent signals: ' + memory.Intent_Tags__c + ']';
    }

    private Decimal calculateConfidence(Decimal patternCount, Decimal strength) {
        Decimal base     = 50.0;
        Decimal countAdd = Math.min(30.0, (patternCount != null ? patternCount : 1) * 2.0);
        Decimal strAdd   = Math.min(20.0, (strength     != null ? strength     : 0) / 10.0 * 2.0);
        return Math.min(100.0, base + countAdd + strAdd);
    }

    private class CrossCloudTemplate {
        String  targetCloud;
        String  body;
        String  flowApiName;
        Decimal baseConfidence;

        CrossCloudTemplate(String tc, String b, String f, Decimal conf) {
            this.targetCloud    = tc;
            this.body           = b;
            this.flowApiName    = f;
            this.baseConfidence = conf;
        }
    }
}