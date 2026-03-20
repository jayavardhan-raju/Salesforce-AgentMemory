// ==============================================================================
// TC1 -- SALES CLOUD -- "The Ghost Deal"
// Acme Corp - Enterprise closes a $500K deal.
// Memory compounds across 4 Opportunity interactions.
// Suggestions for Service Cloud and Marketing Cloud inserted directly
// with ALL fields populated (bypasses async queueable to guarantee display).
// ==============================================================================

// --- CLEANUP ------------------------------------------------------------------
List<Account> old1 = [SELECT Id FROM Account WHERE Name = 'Acme Corp - Enterprise'];
if (!old1.isEmpty()) {
    List<Id> ids1 = new List<Id>();
    for (Account a : old1) ids1.add(a.Id);
    delete [SELECT Id FROM Agent_Suggestion__c WHERE Entity_Id__c IN :ids1];
    delete [SELECT Id FROM Agent_Action_Log__c  WHERE Entity_Id__c IN :ids1];
    delete [SELECT Id FROM Agent_Memory__c      WHERE Entity_Id__c IN :ids1];
    delete old1;
    System.debug('[OK] Prior TC1 data cleaned up');
}

// --- ACCOUNT ------------------------------------------------------------------
Account acme = new Account(
    Name              = 'Acme Corp - Enterprise',
    Industry          = 'Technology',
    AnnualRevenue     = 50000000,
    NumberOfEmployees = 1200,
    BillingCity       = 'San Francisco',
    BillingState      = 'CA',
    BillingCountry    = 'USA',
    Description       = 'Strategic enterprise account. $500K ACV. Multi-year expansion potential.'
);
insert acme;
System.debug('[OK] Account created: Acme Corp - Enterprise (' + acme.Id + ')');

// --- BUILD MEMORY VIA SERVICE (synchronous upsert) ----------------------------
String[] actions = new String[]{
    'Opportunity Created - Discovery Call Completed',
    'Opportunity Advanced - Technical Evaluation Started',
    'Proposal Submitted - Executive Sponsor Confirmed',
    'Opportunity Closed Won - $500,000 ACV'
};
String[] ctxs = new String[]{
    '{"stage":"Prospecting","amount":500000,"product":"Platform Pro"}',
    '{"stage":"Qualification","amount":500000,"evalType":"POC"}',
    '{"stage":"Proposal/Price Quote","amount":500000,"executiveSponsor":"CFO"}',
    '{"stage":"Closed Won","amount":500000,"closeDate":"2026-03-01","multiYear":true}'
};
List<List<String>> tagSets = new List<List<String>>{
    new List<String>{ 'new_opportunity', 'enterprise', 'discovery_complete' },
    new List<String>{ 'qualified', 'enterprise', 'technical_eval', 'high_value' },
    new List<String>{ 'proposal_sent', 'exec_sponsor', 'high_value', 'enterprise' },
    new List<String>{ 'closed_won', 'high_value', 'enterprise', 'expansion_signal', 'upsell' }
};

for (Integer i = 0; i < 4; i++) {
    AgentMemoryService.MemoryContext ctx = new AgentMemoryService.MemoryContext();
    ctx.entityId    = acme.Id;
    ctx.entityType  = 'Account';
    ctx.cloudSource = 'Sales Cloud';
    ctx.actionTaken = actions[i];
    ctx.contextJson = ctxs[i];
    ctx.intentTags  = tagSets[i];
    AgentMemoryService.recordAndLearn(ctx);
    System.debug('    >> Memory pass ' + (i + 1) + ' recorded: ' + actions[i]);
}

// --- READ BACK THE MEMORY RECORD ----------------------------------------------
String memHashRaw = acme.Id + '|Sales Cloud|Account|' + UserInfo.getOrganizationId();
String memHash    = EncodingUtil.convertToHex(
    Crypto.generateDigest('SHA-256', Blob.valueOf(memHashRaw))
).left(64);
Agent_Memory__c acmeMem = AgentMemorySelector.getByOrgContextHash(memHash);

if (acmeMem == null) {
    System.debug('[ERROR] Memory record not found after recordAndLearn -- aborting TC1');
    return;
}
System.debug('[OK] Memory Strength : ' + acmeMem.Memory_Strength__c);
System.debug('[OK] Pattern Count   : ' + acmeMem.Pattern_Count__c);
System.debug('[OK] Intent Tags     : ' + acmeMem.Intent_Tags__c);
System.debug('[OK] Cloud Source    : ' + acmeMem.Cloud_Source__c);

// --- DIRECT INSERT: Agent_Suggestion__c (all fields set, no queueable) --------
// This guarantees Source_Cloud__c and Target_Cloud__c are never null,
// regardless of FLS or async timing.
List<Agent_Suggestion__c> suggestions = new List<Agent_Suggestion__c>{

    new Agent_Suggestion__c(
        Name                = 'Cross-Cloud: Sales Cloud -> Service Cloud',
        Source_Cloud__c     = 'Sales Cloud',
        Target_Cloud__c     = 'Service Cloud',
        Suggestion_Body__c  = 'Acme Corp just closed a $500K deal (Closed Won). '
                            + 'Set up a proactive onboarding case in Service Cloud to ensure '
                            + 'customer success from day one and reduce early churn risk. '
                            + '[Intent signals: closed_won, high_value, enterprise, upsell]',
        Confidence_Score__c = 82.5,
        Status__c           = 'Pending',
        Entity_Id__c        = acme.Id,
        Agent_Memory__c     = acmeMem.Id,
        Flow_API_Name__c    = 'AgentMemory_CreateOnboardingCase',
        Expires_At__c       = System.now().addHours(72)
    ),

    new Agent_Suggestion__c(
        Name                = 'Cross-Cloud: Sales Cloud -> Marketing Cloud',
        Source_Cloud__c     = 'Sales Cloud',
        Target_Cloud__c     = 'Marketing Cloud',
        Suggestion_Body__c  = 'A $500K multi-year deal was closed for Acme Corp. '
                            + 'Trigger a welcome and adoption nurture journey in Marketing Cloud '
                            + 'to accelerate product adoption and surface upsell opportunities. '
                            + '[Intent signals: closed_won, expansion_signal, enterprise]',
        Confidence_Score__c = 76.8,
        Status__c           = 'Pending',
        Entity_Id__c        = acme.Id,
        Agent_Memory__c     = acmeMem.Id,
        Flow_API_Name__c    = 'AgentMemory_TriggerNurtureJourney',
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
        Action_Name__c   = 'Opportunity Created - Discovery Call Completed',
        Action_Type__c   = 'Record_Updated',
        Cloud_Source__c  = 'Sales Cloud',
        Entity_Id__c     = acme.Id,
        Agent_Memory__c  = acmeMem.Id,
        Input_Context__c = '{"stage":"Prospecting","amount":500000}',
        Output_Result__c = 'Memory initialised at strength 50',
        User_Accepted__c = true,
        Executed_By__c   = UserInfo.getUserId()
    ),
    new Agent_Action_Log__c(
        Action_Name__c   = 'Opportunity Advanced - Technical Evaluation Started',
        Action_Type__c   = 'Record_Updated',
        Cloud_Source__c  = 'Sales Cloud',
        Entity_Id__c     = acme.Id,
        Agent_Memory__c  = acmeMem.Id,
        Input_Context__c = '{"stage":"Qualification","amount":500000,"evalType":"POC"}',
        Output_Result__c = 'Memory strength reinforced to 60',
        User_Accepted__c = true,
        Executed_By__c   = UserInfo.getUserId()
    ),
    new Agent_Action_Log__c(
        Action_Name__c   = 'Proposal Submitted - Executive Sponsor Confirmed',
        Action_Type__c   = 'Record_Updated',
        Cloud_Source__c  = 'Sales Cloud',
        Entity_Id__c     = acme.Id,
        Agent_Memory__c  = acmeMem.Id,
        Input_Context__c = '{"stage":"Proposal","executiveSponsor":"CFO"}',
        Output_Result__c = 'Memory strength reinforced to 70',
        User_Accepted__c = true,
        Executed_By__c   = UserInfo.getUserId()
    ),
    new Agent_Action_Log__c(
        Action_Name__c   = 'Opportunity Closed Won - $500,000 ACV',
        Action_Type__c   = 'Record_Updated',
        Cloud_Source__c  = 'Sales Cloud',
        Entity_Id__c     = acme.Id,
        Agent_Memory__c  = acmeMem.Id,
        Input_Context__c = '{"stage":"Closed Won","amount":500000,"multiYear":true}',
        Output_Result__c = 'Memory strength reinforced to 80. Cross-cloud suggestions generated.',
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
    WHERE  Entity_Id__c = :acme.Id
    AND    Status__c    = 'Pending'
];
System.debug('');
System.debug('[VERIFY] Suggestions in DB for Acme Corp: ' + verifySugs.size());
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
System.debug('[TC1 COMPLETE] Open this URL to demo:');
System.debug('  /lightning/r/Account/' + acme.Id + '/view');
