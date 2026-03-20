# AgentMemory Demo Playbook

## Overview

This folder contains **three anonymous Apex data scripts** that seed realistic cross-cloud demo scenarios into your org. Each script corresponds to a blog post in the Deep Dive series and demonstrates a distinct AgentMemory use case.

| Script | Scenario | Blog Post |
|---|---|---|
| `TC1_SalesCloud_GhostDeal.apex` | Acme Corp closes a $500K deal → Service Cloud + Marketing Cloud suggestions | [The Ghost Deal Problem](https://www.jayraju.com/?post=5) |
| `TC2_ServiceCloud_CompoundingSignal.apex` | HelixSync resolves 3 cases (CSAT 8/9/10) → Sales Cloud + Marketing Cloud suggestions | [The Compounding Signal](https://www.jayraju.com/?post=6) |
| `TC3_MarketingCloud_SilentBuyer.apex` | Maya browses pricing, downloads buyer guide → Sales Cloud outreach suggestion | [The Silent Buyer](https://www.jayraju.com/?post=12) |

---

## Prerequisites

Before running the scripts:

1. **Deploy the AgentMemory package** to your org (all Apex classes, triggers, objects, LWCs, and permission set)
2. **Assign the permission set**: `sf org assign permset --name AgentMemory_Access --target-org your-org`
3. **Add the `agentMemoryDashboard` LWC** to the Account and/or Contact record page in Lightning App Builder

---

## How to Run

### Option A: Salesforce CLI (Recommended)

```bash
# TC1 — Sales Cloud: The Ghost Deal
sf apex run --file scripts/apex/TC1_SalesCloud_GhostDeal.apex --target-org your-org

# TC2 — Service Cloud: The Compounding Signal
sf apex run --file scripts/apex/TC2_ServiceCloud_CompoundingSignal.apex --target-org your-org

# TC3 — Marketing Cloud: The Silent Buyer
sf apex run --file scripts/apex/TC3_MarketingCloud_SilentBuyer.apex --target-org your-org
```

### Option B: VS Code

1. Open the `.apex` file in VS Code
2. Select all content (`Ctrl+A` / `Cmd+A`)
3. Open the Command Palette (`Ctrl+Shift+P` / `Cmd+Shift+P`)
4. Run: **SFDX: Execute Anonymous Apex with Currently Selected Text**

### Option C: Developer Console

1. Open Developer Console → **Debug** → **Open Execute Anonymous Window**
2. Paste the entire script content
3. Click **Execute**
4. Check the debug log for `[OK]` confirmations

---

## What Each Script Does

### TC1: Sales Cloud — The Ghost Deal

1. Creates Account: **Acme Corp - Enterprise** (Technology, $50M revenue, 1200 employees)
2. Calls `AgentMemoryService.recordAndLearn()` **4 times** to simulate the deal lifecycle:
   - Discovery Call → Technical Eval → Proposal Submitted → Closed Won ($500K)
3. Memory accumulates to **Strength 90, Pattern Count 4**
4. Directly inserts 2 `Agent_Suggestion__c` records:
   - Sales Cloud → Service Cloud (82.5% confidence) — Create onboarding case
   - Sales Cloud → Marketing Cloud (76.8% confidence) — Trigger nurture journey
5. Inserts 4 `Agent_Action_Log__c` entries for the action history timeline

**Demo URL:** Navigate to the Acme Corp Account record to see the dashboard.

### TC2: Service Cloud — The Compounding Signal

1. Creates Account: **HelixSync Technologies** (Software, $12M revenue, 340 employees)
2. Calls `recordAndLearn()` **3 times** for resolved support cases:
   - API Timeout (CSAT 8) → Rate Limit (CSAT 9) → OAuth Fix (CSAT 10)
3. Memory compounds to **Strength 80, Pattern Count 3**
4. Directly inserts 2 suggestions:
   - Service Cloud → Sales Cloud (78.4% confidence) — Create upsell task
   - Service Cloud → Marketing Cloud (65.0% confidence) — Enroll satisfaction journey
5. Inserts 3 action log entries

**Demo URL:** Navigate to the HelixSync Technologies Account record.

### TC3: Marketing Cloud — The Silent Buyer

1. Creates Account: **QuantumLeap Ltd** + Contact: **Maya Ramirez-Okonkwo** (Senior IT Director)
2. Calls `recordAndLearn()` **4 times** on the Contact for marketing journey events:
   - Email opened (4th this week) → ROI calculator clicked → Pricing page (4m31s, 92% scroll) → Buyer guide downloaded
3. Memory reaches **Strength 80, Pattern Count 4**
4. Directly inserts 1 suggestion:
   - Marketing Cloud → Sales Cloud (91.2% confidence) — Create outreach task
5. Inserts 4 action log entries

**Demo URL:** Navigate to the Maya Ramirez-Okonkwo Contact record.

---

## Cleanup

Each script includes a cleanup block at the top that deletes prior data for that scenario before re-creating it. You can safely re-run any script multiple times.

To manually clean up all demo data:

```apex
// Run in Developer Console / Execute Anonymous
delete [SELECT Id FROM Agent_Suggestion__c];
delete [SELECT Id FROM Agent_Action_Log__c];
delete [SELECT Id FROM Agent_Memory__c];
delete [SELECT Id FROM Account WHERE Name IN ('Acme Corp - Enterprise', 'HelixSync Technologies', 'QuantumLeap Ltd')];
delete [SELECT Id FROM Contact WHERE LastName = 'Ramirez-Okonkwo'];
```

---

## Important Notes

- The TC scripts **bypass the async `CrossCloudAnalysisQueueable`** by directly inserting suggestion records. This guarantees all fields (including `Source_Cloud__c` and `Target_Cloud__c`) are populated regardless of async timing or FLS configuration.
- The existing `AgentMemoryServiceTest.cls` is the **unit test class** that provides code coverage for deployment. The TC scripts here are **demo data seeders** — they are not test classes and should not be deployed.
- Suggestions expire after 72 hours (`Expires_At__c`). Re-run the script to regenerate if they expire.
