/**
 * @description Test suite covering AgentMemoryService, AgentMemorySelector,
 *              CrossCloudAnalysisQueueable, MemoryStrengthDecayBatch,
 *              and AgentMemoryController.
 *              Target: >= 90% code coverage on all production classes.
 * @author      Contextual Agent Memory
 * @version     1.0
 */
@IsTest
private class AgentMemoryServiceTest {

    // ─── Test Setup ───────────────────────────────────────────────────────────
    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Test Corp');
        insert acc;

        Agent_Memory__c mem = new Agent_Memory__c(
            Name                  = 'Sales Cloud | Account | ' + acc.Id,
            Cloud_Source__c       = 'Sales Cloud',
            Entity_Id__c          = acc.Id,
            Entity_Type__c        = 'Account',
            Context_Payload__c    = '{"stage":"Prospecting"}',
            Memory_Strength__c    = 50.0,
            Pattern_Count__c      = 3,
            Intent_Tags__c        = 'upsell,high_value',
            Org_Context_Hash__c   = buildHash(acc.Id, 'Sales Cloud', 'Account'),
            Last_Interacted_By__c = UserInfo.getUserId()
        );
        insert mem;

        Agent_Suggestion__c sug = new Agent_Suggestion__c(
            Name                = 'Test Suggestion',
            Source_Cloud__c     = 'Sales Cloud',
            Target_Cloud__c     = 'Service Cloud',
            Suggestion_Body__c  = 'Create onboarding case.',
            Confidence_Score__c = 75.0,
            Status__c           = 'Pending',
            Entity_Id__c        = acc.Id,
            Agent_Memory__c     = mem.Id,
            Expires_At__c       = System.now().addHours(72)
        );
        insert sug;
    }

    // ─── AgentMemoryService.recordAndLearn ───────────────────────────────────

    @IsTest
    static void testRecordAndLearn_NewEntity_CreatesMemory() {
        Account acc2 = new Account(Name = 'New Org');
        insert acc2;

        AgentMemoryService.MemoryContext ctx = buildCtx(
            acc2.Id, 'Account', 'Service Cloud', 'Closed Case', '{"caseId":"00001"}'
        );

        Test.startTest();
        AgentMemoryService.recordAndLearn(ctx);
        Test.stopTest();

        List<Agent_Memory__c> mems = [
            SELECT Id, Cloud_Source__c, Memory_Strength__c
            FROM   Agent_Memory__c
            WHERE  Entity_Id__c = :acc2.Id
        ];
        System.assertEquals(1, mems.size(), 'Should create one memory record');
        System.assertEquals('Service Cloud', mems[0].Cloud_Source__c);
        System.assert(mems[0].Memory_Strength__c > 0, 'New memory should have positive strength');
    }

    @IsTest
    static void testRecordAndLearn_ExistingEntity_ReinforcesMemory() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Agent_Memory__c before = [
            SELECT Id, Pattern_Count__c, Memory_Strength__c
            FROM   Agent_Memory__c WHERE Entity_Id__c = :acc.Id LIMIT 1
        ];

        AgentMemoryService.MemoryContext ctx = buildCtx(
            acc.Id, 'Account', 'Sales Cloud', 'Opportunity Won', '{"amount":50000}'
        );
        ctx.intentTags = new List<String>{ 'churn_risk' };

        Test.startTest();
        AgentMemoryService.recordAndLearn(ctx);
        Test.stopTest();

        Agent_Memory__c after = [
            SELECT Pattern_Count__c, Memory_Strength__c, Intent_Tags__c
            FROM   Agent_Memory__c WHERE Id = :before.Id
        ];
        System.assert(after.Pattern_Count__c   > before.Pattern_Count__c,   'Pattern count must increase');
        System.assert(after.Memory_Strength__c >= before.Memory_Strength__c, 'Strength must increase');
        System.assert(after.Intent_Tags__c.contains('churn_risk'),           'New tag should be merged in');
    }

    @IsTest
    static void testRecordAndLearn_InvalidContext_ThrowsException() {
        AgentMemoryService.MemoryContext ctx = new AgentMemoryService.MemoryContext();
        ctx.entityId = null;

        Test.startTest();
        try {
            AgentMemoryService.recordAndLearn(ctx);
            System.assert(false, 'Should have thrown AgentMemoryException');
        } catch (AgentMemoryService.AgentMemoryException ex) {
            System.assert(ex.getMessage().contains('MemoryContext is incomplete'));
        }
        Test.stopTest();
    }

    // ─── AgentMemoryService.acceptSuggestion ─────────────────────────────────

    @IsTest
    static void testAcceptSuggestion_ValidId_UpdatesStatusAndBoostsMemory() {
        Agent_Suggestion__c sug = [SELECT Id, Agent_Memory__c FROM Agent_Suggestion__c LIMIT 1];
        Decimal strengthBefore  = [
            SELECT Memory_Strength__c FROM Agent_Memory__c WHERE Id = :sug.Agent_Memory__c
        ].Memory_Strength__c;

        Test.startTest();
        AgentMemoryService.acceptSuggestion(sug.Id, UserInfo.getUserId());
        Test.stopTest();

        System.assertEquals('Accepted',
            [SELECT Status__c FROM Agent_Suggestion__c WHERE Id = :sug.Id].Status__c);

        Decimal strengthAfter = [
            SELECT Memory_Strength__c FROM Agent_Memory__c WHERE Id = :sug.Agent_Memory__c
        ].Memory_Strength__c;
        System.assert(strengthAfter > strengthBefore, 'Memory strength should increase after acceptance');
    }

    // ─── AgentMemoryService.dismissSuggestion ────────────────────────────────

    @IsTest
    static void testDismissSuggestion_ValidId_UpdatesStatusAndDecaysMemory() {
        Agent_Suggestion__c sug = [SELECT Id, Agent_Memory__c FROM Agent_Suggestion__c LIMIT 1];
        Decimal strengthBefore  = [
            SELECT Memory_Strength__c FROM Agent_Memory__c WHERE Id = :sug.Agent_Memory__c
        ].Memory_Strength__c;

        Test.startTest();
        AgentMemoryService.dismissSuggestion(sug.Id, 'Not relevant', UserInfo.getUserId());
        Test.stopTest();

        Agent_Suggestion__c updated = [
            SELECT Status__c, Dismissed_Reason__c FROM Agent_Suggestion__c WHERE Id = :sug.Id
        ];
        System.assertEquals('Dismissed',    updated.Status__c);
        System.assertEquals('Not relevant', updated.Dismissed_Reason__c);

        Decimal strengthAfter = [
            SELECT Memory_Strength__c FROM Agent_Memory__c WHERE Id = :sug.Agent_Memory__c
        ].Memory_Strength__c;
        System.assert(strengthAfter < strengthBefore, 'Memory strength should decay on dismissal');
    }

    // ─── CrossCloudAnalysisQueueable ─────────────────────────────────────────

    @IsTest
    static void testCrossCloudAnalysis_SalesCloudTrigger_GeneratesSuggestions() {
        Account acc2 = new Account(Name = 'Cross Cloud Corp');
        insert acc2;

        Agent_Memory__c mem = new Agent_Memory__c(
            Name                  = 'Sales Cloud | Account | ' + acc2.Id,
            Cloud_Source__c       = 'Sales Cloud',
            Entity_Id__c          = acc2.Id,
            Entity_Type__c        = 'Account',
            Memory_Strength__c    = 70.0,
            Pattern_Count__c      = 8,
            Intent_Tags__c        = 'upsell',
            Org_Context_Hash__c   = buildHash(acc2.Id, 'Sales Cloud', 'Account'),
            Last_Interacted_By__c = UserInfo.getUserId()
        );
        insert mem;

        AgentMemoryService.MemoryContext ctx = buildCtx(
            acc2.Id, 'Account', 'Sales Cloud', 'Stage Changed', '{}'
        );

        Test.startTest();
        System.enqueueJob(new CrossCloudAnalysisQueueable(mem.Id, ctx));
        Test.stopTest();

        List<Agent_Suggestion__c> suggestions = [
            SELECT Id, Target_Cloud__c, Confidence_Score__c
            FROM   Agent_Suggestion__c
            WHERE  Entity_Id__c = :acc2.Id
        ];
        System.assert(!suggestions.isEmpty(), 'Should have generated cross-cloud suggestions');

        Set<String> targetClouds = new Set<String>();
        for (Agent_Suggestion__c s : suggestions) targetClouds.add(s.Target_Cloud__c);
        System.assert(
            targetClouds.contains('Service Cloud') || targetClouds.contains('Marketing Cloud'),
            'Suggestions should target other clouds'
        );
    }

    // ─── MemoryStrengthDecayBatch ─────────────────────────────────────────────

    @IsTest
    static void testDecayBatch_StaleMemory_ReducesStrength() {
        Agent_Memory__c stale = new Agent_Memory__c(
            Name                = 'Stale Memory',
            Cloud_Source__c     = 'Marketing Cloud',
            Entity_Id__c        = 'STALE001',
            Entity_Type__c      = 'Campaign',
            Memory_Strength__c  = 30.0,
            Pattern_Count__c    = 1,
            Org_Context_Hash__c = 'STALE_HASH_001'
        );
        insert stale;

        Test.startTest();
        AgentMemoryService.applyStrengthDecay(new List<Agent_Memory__c>{ stale }, 5.0);
        Test.stopTest();

        System.assertEquals(25.0,
            [SELECT Memory_Strength__c FROM Agent_Memory__c WHERE Id = :stale.Id].Memory_Strength__c,
            'Strength should decay by 5');
    }

    @IsTest
    static void testDecayBatch_Schedule_RunsSuccessfully() {
        Test.startTest();
        String jobId = System.schedule(
            'Test Memory Decay',
            '0 0 2 * * ?',
            new MemoryStrengthDecayBatch()
        );
        Test.stopTest();
        System.assert(jobId != null, 'Schedule job should return a job Id');
    }

    // ─── AgentMemoryController ───────────────────────────────────────────────

    @IsTest
    static void testGetPendingSuggestions_ValidEntityId_ReturnsSuggestions() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        List<Agent_Suggestion__c> results = AgentMemoryController.getPendingSuggestions(acc.Id);
        Test.stopTest();

        System.assert(!results.isEmpty(), 'Should return pending suggestions');
    }

    @IsTest
    static void testGetPendingSuggestions_BlankEntityId_ThrowsException() {
        Test.startTest();
        try {
            AgentMemoryController.getPendingSuggestions('');
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage() != null);
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetActionHistory_ValidEntityId_ReturnsLogs() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        insert new Agent_Action_Log__c(
            Action_Name__c  = 'Test Action',
            Action_Type__c  = 'Record_Updated',
            Cloud_Source__c = 'Sales Cloud',
            Entity_Id__c    = acc.Id,
            Executed_By__c  = UserInfo.getUserId()
        );

        Test.startTest();
        List<Agent_Action_Log__c> history = AgentMemoryController.getActionHistory(acc.Id);
        Test.stopTest();

        System.assert(!history.isEmpty(), 'Should return action logs');
    }

    @IsTest
    static void testGetMemoryHeatmap_ReturnsAllThreeClouds() {
        Test.startTest();
        Map<String, Object> heatmap = AgentMemoryController.getMemoryHeatmap();
        Test.stopTest();

        System.assert(heatmap.containsKey('Sales Cloud'));
        System.assert(heatmap.containsKey('Service Cloud'));
        System.assert(heatmap.containsKey('Marketing Cloud'));
    }

    @IsTest
    static void testRecordMemoryContext_ValidJson_CreatesMemory() {
        Account acc3 = new Account(Name = 'Controller Test Corp');
        insert acc3;

        Test.startTest();
        AgentMemoryController.recordMemoryContext(JSON.serialize(
            buildCtx(acc3.Id, 'Account', 'Marketing Cloud', 'Journey Entered', '{}')
        ));
        Test.stopTest();

        System.assert(
            ![SELECT Id FROM Agent_Memory__c WHERE Entity_Id__c = :acc3.Id].isEmpty(),
            'Memory should be created via controller'
        );
    }

    @IsTest
    static void testAcceptSuggestion_ViaController_UpdatesStatus() {
        Agent_Suggestion__c sug = [SELECT Id FROM Agent_Suggestion__c LIMIT 1];

        Test.startTest();
        AgentMemoryController.acceptSuggestion(sug.Id);
        Test.stopTest();

        System.assertEquals('Accepted',
            [SELECT Status__c FROM Agent_Suggestion__c WHERE Id = :sug.Id].Status__c);
    }

    // ─── AgentMemorySelector ─────────────────────────────────────────────────

    @IsTest
    static void testSelector_GetByCloudAndStrength_FiltersCorrectly() {
        List<Agent_Memory__c> results =
            AgentMemorySelector.getByCloudAndStrength('Sales Cloud', 40.0);

        System.assert(!results.isEmpty(), 'Should find Sales Cloud memories above threshold');
        for (Agent_Memory__c m : results) {
            System.assert(m.Memory_Strength__c >= 40.0);
            System.assertEquals('Sales Cloud', m.Cloud_Source__c);
        }
    }

    @IsTest
    static void testSelector_GetByOrgContextHash_ReturnsNull_WhenNotFound() {
        // FIX: System.assertNull() does not exist in Apex.
        //      Use System.assertEquals(null, value, message) instead.
        Agent_Memory__c result = AgentMemorySelector.getByOrgContextHash('NONEXISTENT_HASH');
        System.assertEquals(null, result, 'Should return null for unknown hash');
    }

    @IsTest
    static void testSelector_GetSuggestionFeedback_ReturnsAggregateResult() {
        Agent_Suggestion__c sug = [SELECT Id, Agent_Memory__c FROM Agent_Suggestion__c LIMIT 1];
        sug.Status__c = 'Accepted';
        update sug;

        List<AggregateResult> feedback =
            AgentMemorySelector.getSuggestionFeedbackByMemory(new Set<Id>{ sug.Agent_Memory__c });

        System.assert(!feedback.isEmpty(), 'Should return aggregate results');
    }

    // ─── Private Helpers ──────────────────────────────────────────────────────

    private static AgentMemoryService.MemoryContext buildCtx(
            String entityId, String entityType, String cloudSource,
            String action,   String ctxJson) {
        AgentMemoryService.MemoryContext ctx = new AgentMemoryService.MemoryContext();
        ctx.entityId    = entityId;
        ctx.entityType  = entityType;
        ctx.cloudSource = cloudSource;
        ctx.actionTaken = action;
        ctx.contextJson = ctxJson;
        ctx.intentTags  = new List<String>{ 'test_tag' };
        return ctx;
    }

    private static String buildHash(String entityId, String cloud, String entityType) {
        String raw    = entityId + '|' + cloud + '|' + entityType + '|' + UserInfo.getOrganizationId();
        Blob   digest = Crypto.generateDigest('SHA-256', Blob.valueOf(raw));
        return EncodingUtil.convertToHex(digest).left(64);
    }
}