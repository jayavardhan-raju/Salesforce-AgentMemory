---
layout: default
title: Architecture Overview
parent: Architecture
nav_order: 1
---

# Architecture Overview

AgentMemory follows the **Trigger → Handler → Service → Selector** pattern — a well-established Salesforce enterprise architecture that separates concerns cleanly across layers.

---

## Layered Design

```
┌───────────────────────────────────────────────────────────────┐
│                      PRESENTATION LAYER                       │
│   agentMemoryDashboard (LWC)    agentSuggestionCard (LWC)    │
└──────────────────────────┬────────────────────────────────────┘
                           │
┌──────────────────────────▼────────────────────────────────────┐
│                      CONTROLLER LAYER                         │
│               AgentMemoryController                           │
│   @AuraEnabled cacheable=true for reads                       │
│   @AuraEnabled for writes — delegates to Service              │
└──────────────────────────┬────────────────────────────────────┘
                           │
┌──────────────────────────▼────────────────────────────────────┐
│                       SERVICE LAYER                            │
│                 AgentMemoryService                             │
│   recordAndLearn()     acceptSuggestion()                     │
│   dismissSuggestion()  applyStrengthDecay()                   │
│   logAction()          boostMemoryStrength()                  │
└───┬──────────────────┬──────────────────┬─────────────────────┘
    │                  │                  │
    ▼                  ▼                  ▼
┌────────┐   ┌──────────────────┐   ┌───────────────────────┐
│SELECTOR│   │   ASYNC LAYER    │   │     BATCH LAYER       │
│ (SOQL) │   │ CrossCloudAnalysis│  │ MemoryStrengthDecay   │
│        │   │ FlowExecution     │  │   (Schedulable)       │
└────────┘   └──────────────────┘   └───────────────────────┘
```

---

## Layer Responsibilities

### Trigger Layer
`AgentMemoryTrigger` is a thin delegating trigger on `Agent_Memory__c`. It routes all events (`before insert`, `before update`, `after insert`, `after update`) to the handler and contains zero business logic.

### Handler Layer
`AgentMemoryTriggerHandler` routes trigger events and builds DTOs. On `after update`, it detects memory strength increases and creates `AgentActionLogDTO` entries to log reinforcements via the Service layer.

### Service Layer
`AgentMemoryService` is the heart of the system. It owns all business logic including memory upsert (via SHA-256 hash deduplication), strength reinforcement, intent tag merging, suggestion acceptance/dismissal, and action logging. It contains zero SOQL — all queries are delegated to the Selector.

### Selector Layer
`AgentMemorySelector` encapsulates all SOQL queries. This includes lookups by entity ID, org context hash, cloud + strength threshold, pending suggestions, suggestion feedback aggregates, recent action logs, and decayed memories.

### Controller Layer
`AgentMemoryController` exposes `@AuraEnabled` methods to the LWC layer. Cacheable methods are used for reads (suggestions, memories, history, heatmap). Write methods delegate to the Service and wrap exceptions in `AuraHandledException`.

### Async Layer
Two Queueable classes handle asynchronous processing:
- **CrossCloudAnalysisQueueable** — Runs after every `recordAndLearn()` call. Analyzes the memory's cloud source against a template map, calculates adjusted confidence, deduplicates against existing pending suggestions, and inserts new ones.
- **FlowExecutionQueueable** — Invokes a named Salesforce Flow when a suggestion is accepted, passing the `entityId` as an input variable.

### Batch Layer
`MemoryStrengthDecayBatch` implements a forgetting curve. It runs as a scheduled batch (default: nightly at 2 AM), finds memories not modified in 30+ days, decays their strength by 5 points per cycle, and deletes memories that fall below a 5.0 archive threshold.

---

## Data Flow: End-to-End

1. **Agent action occurs** — A user or process invokes `AgentMemoryService.recordAndLearn()` with a `MemoryContext` (entity ID, type, cloud, action, context JSON, intent tags)
2. **Memory upsert** — The service builds a SHA-256 hash from `entityId|cloudSource|entityType|orgId`. If a matching memory exists, it reinforces it (+10 strength, +1 pattern count, merged tags). Otherwise, it creates a new memory at strength 50.
3. **Cross-cloud analysis** — A `CrossCloudAnalysisQueueable` job is enqueued. It calculates confidence from pattern count and strength, checks suggestion templates for the source cloud, deduplicates against existing pending suggestions, and inserts new ones above the 40% threshold.
4. **LWC renders** — The `agentMemoryDashboard` wires to `AgentMemoryController` methods. It displays the memory strength bar, pending suggestions as cards, and an expandable action history.
5. **User feedback** — When a user accepts a suggestion, the Service updates its status, boosts the parent memory's strength by 10, logs the action, and enqueues a `FlowExecutionQueueable` to invoke the linked automation Flow. Dismissals decay strength by 5 and capture the reason.
6. **Nightly decay** — The scheduled batch reduces strength for all memories not touched in 30+ days, archiving (deleting) those below the threshold.

---

## Security Model

Every DML operation passes through `Security.stripInaccessible()` with the appropriate `AccessType` (CREATABLE or UPDATABLE). All classes use `with sharing` to enforce record-level security. Object-level checks (`isCreateable()`, `isUpdateable()`) are performed before DML. A dedicated permission set (`AgentMemory_Access`) grants field-level access to all three custom objects.
