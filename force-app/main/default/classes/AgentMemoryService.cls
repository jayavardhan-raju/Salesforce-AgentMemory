/**
 * @description Core service layer for the Contextual Agent Memory system.
 *              Handles memory upsert, strength decay, intent-tag extraction,
 *              pattern learning, and cross-cloud suggestion generation.
 *              NO SOQL here — delegates all queries to AgentMemorySelector.
 * @author      Contextual Agent Memory
 * @version     1.0
 */
public with sharing class AgentMemoryService {

    // ─── Constants ────────────────────────────────────────────────────────────
    private static final Decimal STRENGTH_REINFORCEMENT_BOOST  = 10.0;
    private static final Decimal STRENGTH_CAP                  = 100.0;
    private static final Decimal STRENGTH_NEW_MEMORY           = 50.0;
    private static final Integer SUGGESTION_EXPIRY_HOURS       = 72;
    private static final Integer MAX_TAGS_PER_MEMORY           = 10;

    // ─── Inner DTOs ───────────────────────────────────────────────────────────
    public class MemoryContext {
        @AuraEnabled public String       entityId    { get; set; }
        @AuraEnabled public String       entityType  { get; set; }
        @AuraEnabled public String       cloudSource { get; set; }
        @AuraEnabled public String       actionTaken { get; set; }
        @AuraEnabled public String       contextJson { get; set; }
        @AuraEnabled public List<String> intentTags  { get; set; }
    }

    public class SuggestionResult {
        @AuraEnabled public Boolean                   success     { get; set; }
        @AuraEnabled public String                    message     { get; set; }
        @AuraEnabled public List<Agent_Suggestion__c> suggestions { get; set; }

        public SuggestionResult(Boolean success, String msg, List<Agent_Suggestion__c> sug) {
            this.success     = success;
            this.message     = msg;
            this.suggestions = sug;
        }
    }

    // ─── Public API ───────────────────────────────────────────────────────────

    /**
     * @description Main entry point. Upserts memory, reinforces strength,
     *              enqueues cross-cloud analysis.
     *
     * FIX: AccessType.UPSERT does not exist in Apex.
     *      Conditionally use UPDATABLE (existing record) or CREATABLE (new record).
     */
    public static void recordAndLearn(MemoryContext ctx) {
        if (!isValid(ctx)) {
            throw new AgentMemoryException('MemoryContext is incomplete: ' + JSON.serialize(ctx));
        }

        String          hash     = buildOrgContextHash(ctx.entityId, ctx.cloudSource, ctx.entityType);
        Agent_Memory__c existing = AgentMemorySelector.getByOrgContextHash(hash);

        Agent_Memory__c memory = existing != null
            ? reinforceMemory(existing, ctx)
            : buildNewMemory(ctx, hash);

        // Use CREATABLE for new records, UPDATABLE for existing ones.
        // Direct if/else avoids declaring a local variable named 'accessType'
        // which would shadow the System.AccessType enum and cause a compile error
        // when referencing AccessType.UPDATABLE / AccessType.CREATABLE in comparisons.
        SObjectAccessDecision decision;
        if (existing != null) {
            if (!Schema.sObjectType.Agent_Memory__c.isUpdateable()) {
                throw new AgentMemoryException('Insufficient update permissions on Agent_Memory__c');
            }
            decision = Security.stripInaccessible(AccessType.UPDATABLE, new List<SObject>{ memory });
        } else {
            if (!Schema.sObjectType.Agent_Memory__c.isCreateable()) {
                throw new AgentMemoryException('Insufficient create permissions on Agent_Memory__c');
            }
            decision = Security.stripInaccessible(AccessType.CREATABLE, new List<SObject>{ memory });
        }
        upsert (Agent_Memory__c) decision.getRecords()[0] Org_Context_Hash__c;

        System.enqueueJob(new CrossCloudAnalysisQueueable(memory.Id, ctx));
    }

    /**
     * @description Accept a suggestion — logs outcome, boosts parent memory,
     *              invokes linked automation Flow asynchronously.
     */
    public static void acceptSuggestion(Id suggestionId, Id executingUserId) {
        List<Agent_Suggestion__c> suggestions = [
            SELECT Id, Status__c, Agent_Memory__c, Flow_API_Name__c,
                   Confidence_Score__c, Entity_Id__c
            FROM   Agent_Suggestion__c
            WHERE  Id = :suggestionId
            LIMIT  1
        ];
        if (suggestions.isEmpty()) return;

        Agent_Suggestion__c sug = suggestions[0];
        sug.Status__c = 'Accepted';

        SObjectAccessDecision dec = Security.stripInaccessible(
            AccessType.UPDATABLE, new List<SObject>{ sug }
        );
        update (Agent_Suggestion__c) dec.getRecords()[0];

        logAction(new AgentActionLogDTO(
            'Accepted: ' + sug.Id,
            'Suggestion_Accepted',
            null,
            sug.Entity_Id__c,
            JSON.serialize(new Map<String, Object>{ 'suggestionId' => suggestionId }),
            null,
            true,
            executingUserId
        ), sug.Agent_Memory__c);

        if (sug.Agent_Memory__c != null) {
            boostMemoryStrength(sug.Agent_Memory__c, STRENGTH_REINFORCEMENT_BOOST);
        }

        if (String.isNotBlank(sug.Flow_API_Name__c)) {
            System.enqueueJob(new FlowExecutionQueueable(sug.Flow_API_Name__c, sug.Entity_Id__c));
        }
    }

    /**
     * @description Dismiss a suggestion — logs outcome, decays memory.
     */
    public static void dismissSuggestion(Id suggestionId, String reason, Id executingUserId) {
        List<Agent_Suggestion__c> suggestions = [
            SELECT Id, Status__c, Agent_Memory__c, Entity_Id__c
            FROM   Agent_Suggestion__c
            WHERE  Id = :suggestionId
            LIMIT  1
        ];
        if (suggestions.isEmpty()) return;

        Agent_Suggestion__c sug = suggestions[0];
        sug.Status__c           = 'Dismissed';
        sug.Dismissed_Reason__c = reason;

        SObjectAccessDecision dec = Security.stripInaccessible(
            AccessType.UPDATABLE, new List<SObject>{ sug }
        );
        update (Agent_Suggestion__c) dec.getRecords()[0];

        logAction(new AgentActionLogDTO(
            'Dismissed: ' + sug.Id,
            'Suggestion_Dismissed',
            null,
            sug.Entity_Id__c,
            reason,
            null,
            false,
            executingUserId
        ), sug.Agent_Memory__c);

        if (sug.Agent_Memory__c != null) {
            boostMemoryStrength(sug.Agent_Memory__c, -5.0);
        }
    }

    /**
     * @description Invoked by batch — decay memories on the natural forgetting curve.
     */
    public static void applyStrengthDecay(List<Agent_Memory__c> memories, Decimal decayAmount) {
        List<Agent_Memory__c> toUpdate = new List<Agent_Memory__c>();
        for (Agent_Memory__c m : memories) {
            Decimal newStrength = (m.Memory_Strength__c != null)
                ? Math.max(0, m.Memory_Strength__c - decayAmount)
                : 0;
            toUpdate.add(new Agent_Memory__c(
                Id                 = m.Id,
                Memory_Strength__c = newStrength
            ));
        }
        if (!toUpdate.isEmpty()) {
            SObjectAccessDecision dec = Security.stripInaccessible(AccessType.UPDATABLE, toUpdate);
            update dec.getRecords();
        }
    }

    // ─── Private Helpers ──────────────────────────────────────────────────────

    private static Agent_Memory__c reinforceMemory(Agent_Memory__c existing, MemoryContext ctx) {
        existing.Context_Payload__c    = ctx.contextJson;
        existing.Last_Action_Taken__c  = ctx.actionTaken;
        existing.Last_Interacted_By__c = UserInfo.getUserId();
        existing.Pattern_Count__c      = (existing.Pattern_Count__c != null)
            ? existing.Pattern_Count__c + 1 : 1;
        existing.Memory_Strength__c    = Math.min(
            STRENGTH_CAP,
            (existing.Memory_Strength__c != null ? existing.Memory_Strength__c : 0)
            + STRENGTH_REINFORCEMENT_BOOST
        );
        existing.Intent_Tags__c = mergeIntentTags(existing.Intent_Tags__c, ctx.intentTags);
        return existing;
    }

    private static Agent_Memory__c buildNewMemory(MemoryContext ctx, String hash) {
        return new Agent_Memory__c(
            Name                  = ctx.cloudSource + ' | ' + ctx.entityType + ' | ' + ctx.entityId,
            Cloud_Source__c       = ctx.cloudSource,
            Entity_Id__c          = ctx.entityId,
            Entity_Type__c        = ctx.entityType,
            Context_Payload__c    = ctx.contextJson,
            Last_Action_Taken__c  = ctx.actionTaken,
            Last_Interacted_By__c = UserInfo.getUserId(),
            Memory_Strength__c    = STRENGTH_NEW_MEMORY,
            Pattern_Count__c      = 1,
            Org_Context_Hash__c   = hash,
            Intent_Tags__c        = ctx.intentTags != null
                ? String.join(ctx.intentTags, ',') : ''
        );
    }

    /**
     * FIX: List<String>.subList() cannot be re-assigned to a List<String> variable in Apex
     *      because subList() returns a view, not a new list of the same generic type.
     *      Use an explicit index loop instead.
     */
    private static String mergeIntentTags(String existing, List<String> newTags) {
        Set<String> tagSet = new Set<String>();
        if (String.isNotBlank(existing)) tagSet.addAll(existing.split(','));
        if (newTags != null)             tagSet.addAll(newTags);

        List<String> merged = new List<String>(tagSet);

        // FIX: Replace merged.subList(0, MAX_TAGS_PER_MEMORY) with explicit index loop
        if (merged.size() > MAX_TAGS_PER_MEMORY) {
            List<String> trimmed = new List<String>();
            for (Integer i = 0; i < MAX_TAGS_PER_MEMORY; i++) {
                trimmed.add(merged[i]);
            }
            merged = trimmed;
        }

        return String.join(merged, ',');
    }

    private static void boostMemoryStrength(Id memoryId, Decimal boost) {
        List<Agent_Memory__c> mems = [
            SELECT Id, Memory_Strength__c
            FROM   Agent_Memory__c
            WHERE  Id = :memoryId
            LIMIT  1
        ];
        if (!mems.isEmpty()) {
            Decimal current = mems[0].Memory_Strength__c != null ? mems[0].Memory_Strength__c : 0;
            mems[0].Memory_Strength__c = Math.min(STRENGTH_CAP, Math.max(0, current + boost));
            SObjectAccessDecision dec = Security.stripInaccessible(AccessType.UPDATABLE, mems);
            update dec.getRecords();
        }
    }

    public static void logAction(AgentActionLogDTO dto, Id memoryId) {
        if (!Schema.sObjectType.Agent_Action_Log__c.isCreateable()) return;

        Agent_Action_Log__c log = new Agent_Action_Log__c(
            Action_Name__c   = dto.actionName,
            Action_Type__c   = dto.actionType,
            Cloud_Source__c  = dto.cloudSource,
            Entity_Id__c     = dto.entityId,
            Input_Context__c = dto.inputContext,
            Output_Result__c = dto.outputResult,
            User_Accepted__c = dto.userAccepted,
            Executed_By__c   = dto.executedBy,
            Agent_Memory__c  = memoryId
        );
        SObjectAccessDecision dec = Security.stripInaccessible(
            AccessType.CREATABLE, new List<SObject>{ log }
        );
        insert dec.getRecords();
    }

    private static String buildOrgContextHash(String entityId, String cloudSource, String entityType) {
        String raw    = entityId + '|' + cloudSource + '|' + entityType + '|' + UserInfo.getOrganizationId();
        Blob   digest = Crypto.generateDigest('SHA-256', Blob.valueOf(raw));
        return EncodingUtil.convertToHex(digest).left(64);
    }

    private static Boolean isValid(MemoryContext ctx) {
        return ctx != null
            && String.isNotBlank(ctx.entityId)
            && String.isNotBlank(ctx.entityType)
            && String.isNotBlank(ctx.cloudSource);
    }

    // ─── Custom Exception ─────────────────────────────────────────────────────
    public class AgentMemoryException extends Exception {}
}