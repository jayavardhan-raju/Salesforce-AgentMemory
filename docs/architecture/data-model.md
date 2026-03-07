---
layout: default
title: Data Model
parent: Architecture
nav_order: 2
---

# Data Model

AgentMemory uses three custom objects in a parent-child hierarchy.

---

## Entity-Relationship Diagram

```
┌──────────────────────────┐
│    Agent_Memory__c       │
│ ─────────────────────    │
│  Org_Context_Hash__c (UK)│──────┐
│  Cloud_Source__c          │      │
│  Entity_Id__c (EXT)      │      │
│  Entity_Type__c          │      │
│  Memory_Strength__c      │      │
│  Pattern_Count__c        │      │
│  Intent_Tags__c          │      │
│  Context_Payload__c      │      │
│  Last_Action_Taken__c    │      │
│  Last_Interacted_By__c   │      │
└──────────┬───────────────┘      │
           │                      │
     1:N   │                1:N   │
           ▼                      ▼
┌────────────────────┐   ┌────────────────────────┐
│ Agent_Suggestion__c│   │  Agent_Action_Log__c   │
│ ───────────────────│   │ ───────────────────────│
│ Source_Cloud__c    │   │  Action_Name__c        │
│ Target_Cloud__c    │   │  Action_Type__c        │
│ Suggestion_Body__c │   │  Cloud_Source__c       │
│ Confidence_Score__c│   │  Entity_Id__c          │
│ Status__c          │   │  Input_Context__c      │
│ Flow_API_Name__c   │   │  Output_Result__c      │
│ Expires_At__c      │   │  User_Accepted__c      │
│ Dismissed_Reason__c│   │  Executed_By__c        │
│ Agent_Memory__c(FK)│   │  Agent_Memory__c (FK)  │
│ Entity_Id__c       │   │                        │
└────────────────────┘   └────────────────────────┘
```

---

## Agent_Memory__c

The central memory record. One record exists per unique combination of `Entity_Id__c` + `Cloud_Source__c` + `Entity_Type__c` + Org ID, enforced by the `Org_Context_Hash__c` unique external ID.

### Fields

| API Name | Type | Required | Description |
|----------|------|----------|-------------|
| `Cloud_Source__c` | Picklist (restricted) | Yes | Sales Cloud, Service Cloud, or Marketing Cloud |
| `Entity_Id__c` | Text(18), External ID | No | 18-char Salesforce record ID of the tracked entity |
| `Entity_Type__c` | Picklist (restricted) | Yes | Account, Contact, Lead, Opportunity, Case, Campaign |
| `Context_Payload__c` | Long Text Area (128KB) | No | JSON context snapshot from the last agent interaction |
| `Memory_Strength__c` | Number(5,2), default 50 | No | Intelligence score 0–100. +10 on reinforce, -5 on dismiss/decay |
| `Pattern_Count__c` | Number(6,0), default 1 | No | Incremented on each `recordAndLearn()` call |
| `Intent_Tags__c` | Text(255) | No | Comma-separated intent signals, max 10 tags |
| `Org_Context_Hash__c` | Text(64), Unique, External ID, Case-Sensitive | No | SHA-256 hex digest for upsert deduplication |
| `Last_Action_Taken__c` | Text(255) | No | Label of the most recent agent action |
| `Last_Interacted_By__c` | Lookup(User) | No | User who last triggered a memory write |

### Deduplication Strategy

The `Org_Context_Hash__c` field is a SHA-256 digest of `entityId|cloudSource|entityType|orgId`. This enables the service to use Apex `upsert` with the hash as the external ID key, ensuring exactly one memory record per entity-cloud-type-org combination without race conditions.

---

## Agent_Suggestion__c

Suggestions generated asynchronously by `CrossCloudAnalysisQueueable`. Each suggestion links back to its parent memory and carries a confidence score, status lifecycle, and optional Flow automation.

### Fields

| API Name | Type | Required | Description |
|----------|------|----------|-------------|
| `Source_Cloud__c` | Picklist (restricted) | No | Cloud that originated the suggestion |
| `Target_Cloud__c` | Picklist (restricted) | No | Cloud where the suggested action should execute |
| `Suggestion_Body__c` | Long Text Area (32KB) | No | Natural-language explanation with appended intent signals |
| `Confidence_Score__c` | Percent(5,1) | No | 0–99.9%. Below 40% is filtered before insert |
| `Status__c` | Picklist (restricted), default Pending | No | Pending → Accepted / Dismissed / Expired |
| `Flow_API_Name__c` | Text(255) | No | API name of the Flow invoked on acceptance |
| `Expires_At__c` | DateTime | No | TTL — set to 72 hours from creation |
| `Expiration_Timestamp__c` | DateTime | No | Alternate expiration timestamp field |
| `Dismissed_Reason__c` | Text(255) | No | User-provided dismissal reason |
| `Entity_Id__c` | Text(18) | No | Entity this suggestion pertains to |
| `Agent_Memory__c` | Lookup(Agent_Memory__c), SetNull | No | Parent memory. Accept +10, dismiss -5 |

### Status Lifecycle

```
  ┌─────────┐
  │ Pending │─────────┬──────────────┐
  └─────────┘         │              │
                      ▼              ▼
              ┌──────────┐   ┌───────────┐
              │ Accepted │   │ Dismissed │
              └──────────┘   └───────────┘
                      │              │
                      │              │
           (Memory +10)    (Memory -5, reason logged)
           (Flow invoked)
```

Expired suggestions are filtered by the selector query (`Expires_At__c > :System.now()`).

---

## Agent_Action_Log__c

An immutable audit trail. Every significant action — memory reinforcement, suggestion acceptance, suggestion dismissal — creates a log entry.

### Fields

| API Name | Type | Required | Description |
|----------|------|----------|-------------|
| `Action_Name__c` | Text(255) | Yes | Free-text label for the action |
| `Action_Type__c` | Picklist (restricted) | No | Automation_Created, Record_Updated, Suggestion_Accepted, Suggestion_Dismissed, Cross_Cloud_Triggered, Memory_Reinforced |
| `Cloud_Source__c` | Picklist (restricted) | No | Sales Cloud, Service Cloud, or Marketing Cloud |
| `Entity_Id__c` | Text(18) | No | Associated entity record ID |
| `Input_Context__c` | Long Text Area (32KB) | No | JSON input that triggered the action |
| `Output_Result__c` | Long Text Area (32KB) | No | Result of the action |
| `Output_Context__c` | Long Text Area (32KB) | No | Captured output context |
| `User_Accepted__c` | Checkbox, default false | No | True if explicitly accepted by user |
| `Accepted_By_User__c` | Checkbox, default false | No | Whether the user accepted the automation |
| `Executed_By__c` | Lookup(User) | No | User who triggered the log entry |
| `Agent_Memory__c` | Lookup(Agent_Memory__c), SetNull | No | Optional parent memory |
| `Action_Timestamp__c` | DateTime | No | When the action occurred |

---

## Permission Set

The `AgentMemory_Access` permission set grants CRUD and field-level access to all three custom objects. Assign it to any user who needs to interact with the AgentMemory framework.
