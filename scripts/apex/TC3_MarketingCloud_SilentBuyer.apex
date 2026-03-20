// ==============================================================================
// TC3 -- MARKETING CLOUD -- "The Silent Buyer"
// Maya Ramirez-Okonkwo (QuantumLeap Ltd) opens 4 emails, clicks pricing,
// downloads buyer guide -- zero form fills. Agent surfaces her to the AE.
// Suggestion for Sales Cloud inserted directly with ALL fields populated
// (bypasses async queueable to guarantee display).
// ==============================================================================

// --- CLEANUP ------------------------------------------------------------------
List<Contact> oldC = [
    SELECT Id FROM Contact
    WHERE LastName = 'Ramirez-Okonkwo' AND FirstName = 'Maya'
];
List<Account> oldA = [SELECT Id FROM Account WHERE Name = 'QuantumLeap Ltd'];

List<Id> oldIds = new List<Id>();
for (Contact c : oldC) oldIds.add(c.Id);
for (Account a : oldA) oldIds.add(a.Id);

if (!oldIds.isEmpty()) {
    delete [SELECT Id FROM Agent_Suggestion__c WHERE Entity_Id__c IN :oldIds];
    delete [SELECT Id FROM Agent_Action_Log__c  WHERE Entity_Id__c IN :oldIds];
    delete [SELECT Id FROM Agent_Memory__c      WHERE Entity_Id__c IN :oldIds];
}
// Contact before Account (FK constraint)
if (!oldC.isEmpty()) {
    delete oldC;
    System.debug('[OK] Prior TC3 contact deleted');
}
if (!oldA.isEmpty()) {
    delete oldA;
    System.debug('[OK] Prior TC3 account deleted');
}

// --- ACCOUNT + CONTACT --------------------------------------------------------
Account quantum = new Account(
    Name              = 'QuantumLeap Ltd',
    Industry          = 'Financial Services',
    AnnualRevenue     = 8000000,
    NumberOfEmployees = 180,
    BillingCity       = 'Chicago',
    BillingState      = 'IL',
    BillingCountry    = 'USA',
    Description       = 'Financial services firm evaluating enterprise integration platforms.'
);
insert quantum;
System.debug('[OK] Account created: QuantumLeap Ltd (' + quantum.Id + ')');

Contact maya = new Contact(
    FirstName    = 'Maya',
    LastName     = 'Ramirez-Okonkwo',
    Title        = 'Senior IT Director',
    Email        = 'maya.ramirez@quantumleap.io',
    Phone        = '+1-312-555-0192',
    AccountId    = quantum.Id,
    Department   = 'Information Technology',
    Description  = 'IT decision maker. Controls $2M tech budget. Evaluating integration platforms.'
);
insert maya;
System.debug('[OK] Contact created: Maya Ramirez-Okonkwo (' + maya.Id + ')');

// --- BUILD MEMORY VIA SERVICE (synchronous upsert) ----------------------------
String[] actions = new String[]{
    'Email Opened - Q1 Product Update (4th open this week)',
    'Link Clicked - ROI Calculator and Competitor Comparison Article',
    'Pricing Page Visited - 4 minutes 31 seconds dwell time',
    'Buyer Guide Downloaded - Enterprise Integration Platform Evaluation Checklist'
};
String[] ctxs = new String[]{
    '{"emailName":"Q1 Product Update","journeyName":"Enterprise Nurture","openCount":4,"device":"Desktop"}',
    '{"emailName":"Case Study Series","clickedUrl":"roi-calculator","timeOnPage":"4m12s"}',
    '{"pageUrl":"/pricing","dwellSeconds":271,"scrollDepth":"92pct","plansViewed":["Professional","Enterprise"]}',
    '{"assetName":"Enterprise Integration Eval Checklist","format":"PDF","journeyComplete":true}'
};
List<List<String>> tagSets = new List<List<String>>{
    new List<String>{ 'email_opened', 'enterprise_nurture', 'repeat_engagement' },
    new List<String>{ 'link_clicked', 'roi_calculator', 'competitor_research', 'evaluation_stage' },
    new List<String>{ 'pricing_page_clicked', 'high_intent', 'evaluation_stage', 'decision_maker' },
    new List<String>{ 'content_downloaded', 'high_intent', 'pricing_page_clicked', 'buyer_intent', 'enterprise' }
};

for (Integer i = 0; i < 4; i++) {
    AgentMemoryService.MemoryContext ctx = new AgentMemoryService.MemoryContext();
    ctx.entityId    = maya.Id;
    ctx.entityType  = 'Contact';
    ctx.cloudSource = 'Marketing Cloud';
    ctx.actionTaken = actions[i];
    ctx.contextJson = ctxs[i];
    ctx.intentTags  = tagSets[i];
    AgentMemoryService.recordAndLearn(ctx);
    System.debug('    >> Memory pass ' + (i + 1) + ' recorded: ' + actions[i]);
}

// --- READ BACK THE MEMORY RECORD ----------------------------------------------
String memHashRaw = maya.Id + '|Marketing Cloud|Contact|' + UserInfo.getOrganizationId();
String memHash    = EncodingUtil.convertToHex(
    Crypto.generateDigest('SHA-256', Blob.valueOf(memHashRaw))
).left(64);
Agent_Memory__c mayaMem = AgentMemorySelector.getByOrgContextHash(memHash);

if (mayaMem == null) {
    System.debug('[ERROR] Memory record not found after recordAndLearn -- aborting TC3');
    return;
}
System.debug('[OK] Memory Strength : ' + mayaMem.Memory_Strength__c);
System.debug('[OK] Pattern Count   : ' + mayaMem.Pattern_Count__c);
System.debug('[OK] Intent Tags     : ' + mayaMem.Intent_Tags__c);
System.debug('[OK] Cloud Source    : ' + mayaMem.Cloud_Source__c);

// --- DIRECT INSERT: Agent_Suggestion__c (all fields set, no queueable) --------
// This guarantees Source_Cloud__c and Target_Cloud__c are never null,
// regardless of FLS or async timing.
List<Agent_Suggestion__c> suggestions = new List<Agent_Suggestion__c>{

    new Agent_Suggestion__c(
        Name                = 'Cross-Cloud: Marketing Cloud -> Sales Cloud',
        Source_Cloud__c     = 'Marketing Cloud',
        Target_Cloud__c     = 'Sales Cloud',
        Suggestion_Body__c  = 'Maya Ramirez-Okonkwo (Senior IT Director, QuantumLeap Ltd) has '
                            + 'opened 4 emails, clicked the ROI calculator, spent 4m31s on the '
                            + 'pricing page viewing Professional and Enterprise plans, and '
                            + 'downloaded the buyer evaluation checklist -- all without filling '
                            + 'a form. This is silent high-intent behaviour. Auto-create a Sales '
                            + 'Cloud outreach task for the assigned AE to contact her immediately. '
                            + '[Intent signals: buyer_intent, high_intent, decision_maker, pricing_page_clicked]',
        Confidence_Score__c = 91.2,
        Status__c           = 'Pending',
        Entity_Id__c        = maya.Id,
        Agent_Memory__c     = mayaMem.Id,
        Flow_API_Name__c    = 'AgentMemory_CreateOutreachTask',
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
        Action_Name__c   = 'Email Opened - Q1 Product Update (4th open this week)',
        Action_Type__c   = 'Record_Updated',
        Cloud_Source__c  = 'Marketing Cloud',
        Entity_Id__c     = maya.Id,
        Agent_Memory__c  = mayaMem.Id,
        Input_Context__c = '{"emailName":"Q1 Product Update","openCount":4,"device":"Desktop"}',
        Output_Result__c = 'Memory initialised at strength 50. Repeat engagement signal flagged.',
        User_Accepted__c = true,
        Executed_By__c   = UserInfo.getUserId()
    ),
    new Agent_Action_Log__c(
        Action_Name__c   = 'Link Clicked - ROI Calculator and Competitor Research',
        Action_Type__c   = 'Record_Updated',
        Cloud_Source__c  = 'Marketing Cloud',
        Entity_Id__c     = maya.Id,
        Agent_Memory__c  = mayaMem.Id,
        Input_Context__c = '{"clickedUrl":"roi-calculator","timeOnPage":"4m12s"}',
        Output_Result__c = 'Memory strength reinforced to 60. Evaluation stage confirmed.',
        User_Accepted__c = true,
        Executed_By__c   = UserInfo.getUserId()
    ),
    new Agent_Action_Log__c(
        Action_Name__c   = 'Pricing Page Visited - 4m31s dwell, Enterprise plan viewed',
        Action_Type__c   = 'Record_Updated',
        Cloud_Source__c  = 'Marketing Cloud',
        Entity_Id__c     = maya.Id,
        Agent_Memory__c  = mayaMem.Id,
        Input_Context__c = '{"pageUrl":"/pricing","dwellSeconds":271,"scrollDepth":"92pct"}',
        Output_Result__c = 'Memory strength reinforced to 70. High-intent buyer signal.',
        User_Accepted__c = true,
        Executed_By__c   = UserInfo.getUserId()
    ),
    new Agent_Action_Log__c(
        Action_Name__c   = 'Buyer Guide Downloaded - Enterprise Integration Eval Checklist',
        Action_Type__c   = 'Cross_Cloud_Triggered',
        Cloud_Source__c  = 'Marketing Cloud',
        Entity_Id__c     = maya.Id,
        Agent_Memory__c  = mayaMem.Id,
        Input_Context__c = '{"assetName":"Enterprise Integration Eval Checklist","format":"PDF"}',
        Output_Result__c = 'Memory strength reinforced to 80. Sales Cloud outreach task suggestion triggered.',
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
    WHERE  Entity_Id__c = :maya.Id
    AND    Status__c    = 'Pending'
];
System.debug('');
System.debug('[VERIFY] Suggestions in DB for Maya Ramirez-Okonkwo: ' + verifySugs.size());
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
System.debug('[TC3 COMPLETE] Open this URL to demo:');
System.debug('  /lightning/r/Contact/' + maya.Id + '/view');
