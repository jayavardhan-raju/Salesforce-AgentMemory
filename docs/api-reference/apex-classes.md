---
layout: default
title: Apex Classes
parent: API Reference
nav_order: 1
---

# Apex Class Reference

ApexDox-style documentation for all classes in the AgentMemory framework.

---

## AgentMemoryService

**Core service layer for the Contextual Agent Memory system.** Handles memory upsert, strength reinforcement and decay, intent-tag extraction, pattern learning, and cross-cloud suggestion generation. Contains zero SOQL — all queries are delegated to `AgentMemorySelector`.

**Author:** Contextual Agent Memory  
**Version:** 1.0  
**Sharing:** `with sharing`

### Constants

| Constant | Type | Value | Description |
|----------|------|-------|-------------|
| `STRENGTH_REINFORCEMENT_BOOST` | Decimal | 10.0 | Points added on each reinforcement |
| `STRENGTH_CAP` | Decimal | 100.0 | Maximum memory strength |
| `STRENGTH_NEW_MEMORY` | Decimal | 50.0 | Initial strength for new memories |
| `SUGGESTION_EXPIRY_HOURS` | Integer | 72 | Hours before a suggestion expires |
| `MAX_TAGS_PER_MEMORY` | Integer | 10 | Maximum intent tags stored per memory |

### Inner Classes

#### MemoryContext

Lightweight input DTO carrying all data needed to record a memory.

| Property | Type | Description |
|----------|------|-------------|
| `entityId` | String | 18-char Salesforce record ID |
| `entityType` | String | SObject type (Account, Contact, etc.) |
| `cloudSource` | String | Sales Cloud, Service Cloud, or Marketing Cloud |
| `actionTaken` | String | Label of the action that occurred |
| `contextJson` | String | JSON payload with action context |
| `intentTags` | List\<String\> | Intent signals to merge into memory |

#### SuggestionResult

Response wrapper for suggestion-related operations.

| Property | Type | Description |
|----------|------|-------------|
| `success` | Boolean | Whether the operation succeeded |
| `message` | String | Human-readable status message |
| `suggestions` | List\<Agent_Suggestion__c\> | Generated or affected suggestions |

#### AgentMemoryException

Custom exception class for AgentMemory-specific errors.

### Public Methods

---

#### `recordAndLearn(MemoryContext ctx)`

**Main entry point.** Upserts a memory record (creating or reinforcing), then enqueues a `CrossCloudAnalysisQueueable` job.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `ctx` | `MemoryContext` | Required. Must have non-blank `entityId`, `entityType`, and `cloudSource` |

**Behavior:**
1. Validates the context (throws `AgentMemoryException` if incomplete)
2. Builds a SHA-256 hash from `entityId|cloudSource|entityType|orgId`
3. Looks up existing memory by hash
4. If found: reinforces (+10 strength, +1 pattern count, merges intent tags)
5. If not found: creates new memory at strength 50
6. Applies `Security.stripInaccessible()` with appropriate AccessType
7. Upserts on `Org_Context_Hash__c`
8. Enqueues `CrossCloudAnalysisQueueable`

**Throws:** `AgentMemoryException` if context is incomplete or CRUD checks fail

---

#### `acceptSuggestion(Id suggestionId, Id executingUserId)`

Accepts a suggestion — updates status, boosts parent memory, logs the action, and invokes the linked Flow.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `suggestionId` | Id | The suggestion to accept |
| `executingUserId` | Id | The user performing the action |

**Behavior:**
1. Queries the suggestion record
2. Sets `Status__c` to `'Accepted'`
3. Logs an action of type `Suggestion_Accepted`
4. Boosts parent memory strength by +10
5. If `Flow_API_Name__c` is populated, enqueues `FlowExecutionQueueable`

---

#### `dismissSuggestion(Id suggestionId, String reason, Id executingUserId)`

Dismisses a suggestion — updates status, captures reason, decays parent memory, and logs the action.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `suggestionId` | Id | The suggestion to dismiss |
| `reason` | String | User-provided dismissal reason |
| `executingUserId` | Id | The user performing the action |

**Behavior:**
1. Sets `Status__c` to `'Dismissed'` and `Dismissed_Reason__c` to the provided reason
2. Logs an action of type `Suggestion_Dismissed`
3. Decays parent memory strength by -5

---

#### `applyStrengthDecay(List<Agent_Memory__c> memories, Decimal decayAmount)`

Invoked by `MemoryStrengthDecayBatch`. Reduces memory strength by the specified amount, flooring at 0.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `memories` | List\<Agent_Memory__c\> | Memories to decay |
| `decayAmount` | Decimal | Points to subtract |

---

#### `logAction(AgentActionLogDTO dto, Id memoryId)`

Creates an `Agent_Action_Log__c` record. Checks `isCreateable()` before DML.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `dto` | `AgentActionLogDTO` | Action details |
| `memoryId` | Id | Optional parent memory (can be null) |

---

## AgentMemorySelector

**Selector for Agent_Memory__c — all SOQL lives here, zero DML.**

**Author:** Contextual Agent Memory  
**Version:** 1.0  
**Sharing:** `with sharing`

### Methods

---

#### `getByEntityIds(Set<String> entityIds)`

Returns all memories matching the given entity IDs, ordered by strength descending.

**Returns:** `List<Agent_Memory__c>` with all fields

---

#### `getByOrgContextHash(String hash)`

Returns a single memory matching the SHA-256 org context hash, or `null` if not found.

**Returns:** `Agent_Memory__c` or `null`

---

#### `getByCloudAndStrength(String cloudSource, Decimal minStrength)`

Returns memories for a specific cloud with strength at or above the threshold, ordered by pattern count descending.

**Returns:** `List<Agent_Memory__c>`

---

#### `getPendingSuggestionsForEntity(String entityId)`

Returns pending, non-expired suggestions for an entity, ordered by confidence descending.

**Returns:** `List<Agent_Suggestion__c>`

---

#### `getSuggestionFeedbackByMemory(Set<Id> memoryIds)`

Returns aggregate counts of Accepted and Dismissed suggestions grouped by memory ID and status.

**Returns:** `List<AggregateResult>` — fields: `Agent_Memory__c`, `Status__c`, `cnt`

---

#### `getRecentActionLogs(String entityId, Integer limitCount)`

Returns the most recent action logs for an entity.

**Returns:** `List<Agent_Action_Log__c>` ordered by `CreatedDate DESC`

---

#### `getDecayedMemories(Decimal decayThreshold)`

Returns memories with strength below the threshold and not modified in 30+ days.

**Returns:** `List<Agent_Memory__c>`

---

## AgentMemoryController

**AuraEnabled controller exposing agent memory operations to LWC.**

**Author:** Contextual Agent Memory  
**Version:** 1.0  
**Sharing:** `with sharing`

### Methods

| Method | Cacheable | Description |
|--------|-----------|-------------|
| `getPendingSuggestions(String entityId)` | Yes | Returns pending suggestions for an entity |
| `getMemoriesForEntities(List<String> entityIds)` | Yes | Returns memories for one or more entity IDs |
| `getActionHistory(String entityId)` | Yes | Returns the 20 most recent action logs |
| `acceptSuggestion(Id suggestionId)` | No | Delegates to `AgentMemoryService.acceptSuggestion()` |
| `dismissSuggestion(Id suggestionId, String reason)` | No | Delegates to `AgentMemoryService.dismissSuggestion()` |
| `recordMemoryContext(String memoryContextJson)` | No | Deserializes JSON to `MemoryContext`, delegates to `recordAndLearn()` |
| `getMemoryHeatmap()` | Yes | Returns a map of cloud → {count, avgStrength, topPatterns} |

All write methods wrap exceptions in `AuraHandledException`. All read methods validate required parameters.

---

## AgentMemoryTriggerHandler

**Trigger handler for Agent_Memory__c.** Routes trigger events with zero SOQL and zero DML of its own.

**Author:** Contextual Agent Memory  
**Version:** 1.0  
**Sharing:** `with sharing`

### Methods

#### `run()`

Static entry point called by `AgentMemoryTrigger`. Currently handles `after update` — detects memory strength increases and logs them via `AgentMemoryService.logAction()`.

---

## CrossCloudAnalysisQueueable

**Async job that analyses cross-cloud patterns and generates Agent_Suggestion__c records.**

**Author:** Contextual Agent Memory  
**Version:** 1.0  
**Implements:** `Queueable`

### Constructor

```apex
CrossCloudAnalysisQueueable(Id memoryId, AgentMemoryService.MemoryContext ctx)
```

### Behavior

1. Queries the memory by entity ID
2. Calculates confidence from pattern count and memory strength
3. Looks up suggestion templates for the source cloud
4. Deduplicates against existing pending suggestions for the same target cloud
5. Filters suggestions below 40% adjusted confidence
6. Inserts surviving suggestions with a 72-hour TTL
7. Enriches suggestion body with intent tag signals

### Suggestion Templates

Templates are stored as a static `Map<String, CrossCloudTemplate[]>` keyed by source cloud name. Each template specifies target cloud, suggestion body, Flow API name, and base confidence.

---

## FlowExecutionQueueable

**Queueable that invokes a named Salesforce Flow when a suggestion is accepted.**

**Author:** Contextual Agent Memory  
**Version:** 1.0  
**Implements:** `Queueable`

### Constructor

```apex
FlowExecutionQueueable(String flowApiName, String entityId)
```

### Behavior

Creates a `Flow.Interview` from the provided Flow API name, passes `entityId` as an input variable, and starts the interview. Errors are caught and logged at `ERROR` level.

---

## MemoryStrengthDecayBatch

**Scheduled batch implementing a forgetting curve for agent memories.**

**Author:** Contextual Agent Memory  
**Version:** 1.0  
**Implements:** `Database.Batchable<SObject>`, `Schedulable`

### Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `DECAY_AMOUNT` | 5.0 | Points subtracted per batch cycle |
| `ARCHIVE_THRESHOLD` | 5.0 | Memories at or below this strength are deleted |
| `BATCH_SIZE` | 200 | Records processed per batch execute |

### Behavior

1. **start()** — Queries memories not modified in 30+ days with strength > 0
2. **execute()** — Decays strength by 5. Memories at or below 5.0 are deleted; others are updated
3. **finish()** — Logs completion at INFO level

Uses `Database.update(..., false)` and `Database.delete(..., false)` for partial success handling.

---

## AgentActionLogDTO

**Lightweight DTO bundling Agent_Action_Log__c insertion parameters.** Keeps `AgentMemoryService` and `AgentMemoryTriggerHandler` clean by avoiding long method signatures.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `actionName` | String | Free-text label |
| `actionType` | String | Picklist value |
| `cloudSource` | String | Originating cloud |
| `entityId` | String | Associated entity ID |
| `inputContext` | String | JSON input context |
| `outputResult` | String | Result of the action |
| `userAccepted` | Boolean | Whether user accepted |
| `executedBy` | Id | User who triggered the action |

### Constructor

```apex
AgentActionLogDTO(
    String actionName, String actionType, String cloudSource,
    String entityId, String inputContext, String outputResult,
    Boolean userAccepted, Id executedBy
)
```
