// ==============================================================================
// TC2 -- SERVICE CLOUD -- "The Compounding Signal"
// HelixSync Technologies resolves the same integration issue 3 times.
// Memory climbs to strength 80. Suggestions for Sales Cloud and Marketing Cloud
// inserted directly with ALL fields populated (bypasses async queueable).
// ==============================================================================

// --- CLEANUP ------------------------------------------------------------------
List<Account> old2 = [SELECT Id FROM Account WHERE Name = 'HelixSync Technologies'];
if (!old2.isEmpty()) {
    List<Id> ids2 = new List<Id>();
    for (Account a : old2) ids2.add(a.Id);
    delete [SELECT Id FROM Agent_Suggestion__c WHERE Entity_Id__c IN :ids2];
    delete [SELECT Id FROM Agent_Action_Log__c  WHERE Entity_Id__c IN :ids2];
    delete [SELECT Id FROM Agent_Memory__c      WHERE Entity_Id__c IN :ids2];
    delete old2;
    System.debug('[OK] Prior TC2 data cleaned up');
}

// --- ACCOUNT ------------------------------------------------------------------
Account helix = new Account(
    Name              = 'HelixSync Technologies',
    Industry          = 'Software',
    AnnualRevenue     = 12000000,
    NumberOfEmployees = 340,
    BillingCity       = 'Austin',
    BillingState      = 'TX',
    BillingCountry    = 'USA',
    Description       = 'Mid-market SaaS company. Current ARR $400K. Active integration user.'
);
insert helix;
System.debug('[OK] Account created: HelixSync Technologies (' + helix.Id + ')');

// --- BUILD MEMORY VIA SERVICE (synchronous upsert) ----------------------------
String[] actions = new String[]{
    'Case #00019812 Resolved - API Integration Timeout (CSAT: 8)',
    'Case #00021447 Resolved - API Rate Limit Hit (CSAT: 9)',
    'Case #00023091 Resolved - OAuth Token Expiry Fixed (CSAT: 10) - You guys are incredible'
};
String[] ctxs = new String[]{
    '{"caseNumber":"00019812","category":"Integration","csat":8,"resolutionTime":"2hrs"}',
    '{"caseNumber":"00021447","category":"Integration","csat":9,"repeatIssue":true}',
    '{"caseNumber":"00023091","category":"Integration","csat":10,"verbatim":"You guys are incredible","repeatIssue":true}'
};
List<List<String>> tagSets = new List<List<String>>{
    new List<String>{ 'positive_resolution', 'api_integration', 'csat_high' },
    new List<String>{ 'positive_resolution', 'repeat_case', 'api_integration', 'high_csat' },
    new List<String>{ 'positive_resolution', 'repeat_case', 'high_csat', 'expansion_signal', 'advocacy_potential' }
};

for (Integer i = 0; i < 3; i++) {
    AgentMemoryService.MemoryContext ctx = new AgentMemoryService.MemoryContext();
    ctx.entityId    = helix.Id;
    ctx.entityType  = 'Account';
    ctx.cloudSource = 'Service Cloud';
    ctx.actionTaken = actions[i];
    ctx.contextJson = ctxs[i];
    ctx.intentTags  = tagSets[i];
    AgentMemoryService.recordAndLearn(ctx);
    System.debug('    >> Memory pass ' + (i + 1) + ' recorded: ' + actions[i]);
}

// --- READ BACK THE MEMORY RECORD ----------------------------------------------
String memHashRaw = helix.Id + '|Service Cloud|Account|' + UserInfo.getOrganizationId();
String memHash    = EncodingUtil.convertToHex(
    Crypto.generateDigest('SHA-256', Blob.valueOf(memHashRaw))
).left(64);
Agent_Memory__c helixMem = AgentMemorySelector.getByOrgContextHash(memHash);

if (helixMem == null) {
    System.debug('[ERROR] Memory record not found after recordAndLearn -- aborting TC2');
    return;
}
System.debug('[OK] Memory Strength : ' + helixMem.Memory_Strength__c);
System.debug('[OK] Pattern Count   : ' + helixMem.Pattern_Count__c);
System.debug('[OK] Intent Tags     : ' + helixMem.Intent_Tags__c);
System.debug('[OK] Cloud Source    : ' + helixMem.Cloud_Source__c);

// --- DIRECT INSERT: Agent_Suggestion__c (all fields set, no queueable) --------
// This guarantees Source_Cloud__c and Target_Cloud__c are never null,
// regardless of FLS or async timing.
List<Agent_Suggestion__c> suggestions = new List<Agent_Suggestion__c>{

    new Agent_Suggestion__c(
        Name                = 'Cross-Cloud: Service Cloud -> Sales Cloud',
        Source_Cloud__c     = 'Service Cloud',
        Target_Cloud__c     = 'Sales Cloud',
        Suggestion_Body__c  = 'HelixSync has resolved 3 integration cases with a 9.0 average CSAT '
                            + 'and left a "You guys are incredible" verbatim. This is a strong '
                            + 'upsell signal. Create a follow-up opportunity task in Sales Cloud '
                            + 'to capitalise on this advocacy moment. '
                            + '[Intent signals: expansion_signal, advocacy_potential, high_csat]',
        Confidence_Score__c = 78.4,
        Status__c           = 'Pending',
        Entity_Id__c        = helix.Id,
        Agent_Memory__c     = helixMem.Id,
        Flow_API_Name__c    = 'AgentMemory_CreateUpsellTask',
        Expires_At__c       = System.now().addHours(72)
    ),

    new Agent_Suggestion__c(
        Name                = 'Cross-Cloud: Service Cloud -> Marketing Cloud',
        Source_Cloud__c     = 'Service Cloud',
        Target_Cloud__c     = 'Marketing Cloud',
        Suggestion_Body__c  = 'HelixSync had 3 positive service interactions with a perfect '
                            + 'final CSAT. Enrol this account in a re-engagement or satisfaction '
                            + 'survey journey in Marketing Cloud to build advocacy and drive '
                            + 'referral pipeline. '
                            + '[Intent signals: positive_resolution, repeat_case, csat_high]',
        Confidence_Score__c = 65.0,
        Status__c           = 'Pending',
        Entity_Id__c        = helix.Id,
        Agent_Memory__c     = helixMem.Id,
        Flow_API_Name__c    = 'AgentMemory_EnrollSatisfactionJourney',
        Expires_At__c       = System.now().addHours(72)
    )
};
insert suggestions;
System.debug('[OK] Agent_Suggestion__c records inserted: ' + suggestions.size());
for (Agent_Suggestion__c s : suggestions) {
    System.debug('     Suggestion: ' + s.Source_Cloud__c + ' -> ' + s.Target_Cloud__c
        + ' | Confidence: ' + s.Confidence_Score__c + '% | Status: ' + s.Status__c);
}

// --- DIRECT INSERT: Agent_Action_Log__c (all fields, powers action history) ---
List<Agent_Action_Log__c> logs = new List<Agent_Action_Log__c>{

    new Agent_Action_Log__c(
        Action_Name__c   = 'Case #00019812 Resolved - API Integration Timeout',
        Action_Type__c   = 'Record_Updated',
        Cloud_Source__c  = 'Service Cloud',
        Entity_Id__c     = helix.Id,
        Agent_Memory__c  = helixMem.Id,
        Input_Context__c = '{"caseNumber":"00019812","csat":8,"resolutionTime":"2hrs"}',
        Output_Result__c = 'Memory initialised at strength 50',
        User_Accepted__c = true,
        Executed_By__c   = UserInfo.getUserId()
    ),
    new Agent_Action_Log__c(
        Action_Name__c   = 'Case #00021447 Resolved - API Rate Limit Hit',
        Action_Type__c   = 'Record_Updated',
        Cloud_Source__c  = 'Service Cloud',
        Entity_Id__c     = helix.Id,
        Agent_Memory__c  = helixMem.Id,
        Input_Context__c = '{"caseNumber":"00021447","csat":9,"repeatIssue":true}',
        Output_Result__c = 'Memory strength reinforced to 60. Repeat pattern flagged.',
        User_Accepted__c = true,
        Executed_By__c   = UserInfo.getUserId()
    ),
    new Agent_Action_Log__c(
        Action_Name__c   = 'Case #00023091 Resolved - OAuth Token Expiry Fixed (CSAT: 10)',
        Action_Type__c   = 'Cross_Cloud_Triggered',
        Cloud_Source__c  = 'Service Cloud',
        Entity_Id__c     = helix.Id,
        Agent_Memory__c  = helixMem.Id,
        Input_Context__c = '{"caseNumber":"00023091","csat":10,"verbatim":"You guys are incredible"}',
        Output_Result__c = 'Memory strength reinforced to 80. Cross-cloud suggestions generated for Sales and Marketing Cloud.',
        User_Accepted__c = true,
        Executed_By__c   = UserInfo.getUserId()
    )
};
insert logs;
System.debug('[OK] Agent_Action_Log__c records inserted: ' + logs.size());

// --- FINAL VERIFICATION -------------------------------------------------------
List<Agent_Suggestion__c> verifySugs = [
    SELECT Source_Cloud__c, Target_Cloud__c, Confidence_Score__c,
           Suggestion_Body__c, Status__c, Agent_Memory__c, Expires_At__c
    FROM   Agent_Suggestion__c
    WHERE  Entity_Id__c = :helix.Id
    AND    Status__c    = 'Pending'
];
System.debug('');
System.debug('[VERIFY] Suggestions in DB for HelixSync: ' + verifySugs.size());
for (Agent_Suggestion__c s : verifySugs) {
    System.debug('  Source_Cloud__c  : ' + s.Source_Cloud__c);
    System.debug('  Target_Cloud__c  : ' + s.Target_Cloud__c);
    System.debug('  Confidence_Score : ' + s.Confidence_Score__c);
    System.debug('  Status           : ' + s.Status__c);
    System.debug('  Agent_Memory__c  : ' + s.Agent_Memory__c);
    System.debug('  Expires_At__c    : ' + s.Expires_At__c);
    System.debug('  ---');
}

System.debug('');
System.debug('[TC2 COMPLETE] Open this URL to demo:');
System.debug('  /lightning/r/Account/' + helix.Id + '/view');
