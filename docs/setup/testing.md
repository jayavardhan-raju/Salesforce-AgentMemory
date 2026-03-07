---
layout: default
title: Testing
parent: Setup
nav_order: 2
---

# Testing Guide

The project includes a comprehensive test suite in `AgentMemoryServiceTest` targeting ≥90% code coverage across all production classes.

---

## Running the Tests

### CLI

```bash
# Run the full test suite
sf apex test run \
  -n AgentMemoryServiceTest \
  -r human \
  -c \
  -o AgentMemory

# Run with code coverage details
sf apex test run \
  -n AgentMemoryServiceTest \
  -r human \
  -c \
  --detailed-coverage \
  -o AgentMemory
```

### Developer Console

1. Open Developer Console → Test → New Run
2. Select `AgentMemoryServiceTest`
3. Click Run

---

## Test Coverage Map

| Test Method | Classes Covered |
|-------------|----------------|
| `testRecordAndLearn_NewEntity_CreatesMemory` | AgentMemoryService, AgentMemorySelector, CrossCloudAnalysisQueueable |
| `testRecordAndLearn_ExistingEntity_ReinforcesMemory` | AgentMemoryService (reinforceMemory, mergeIntentTags) |
| `testRecordAndLearn_InvalidContext_ThrowsException` | AgentMemoryService (validation, AgentMemoryException) |
| `testAcceptSuggestion_ValidId_UpdatesStatusAndBoostsMemory` | AgentMemoryService (acceptSuggestion, boostMemoryStrength, logAction) |
| `testDismissSuggestion_ValidId_UpdatesStatusAndDecaysMemory` | AgentMemoryService (dismissSuggestion, logAction) |
| `testCrossCloudAnalysis_SalesCloudTrigger_GeneratesSuggestions` | CrossCloudAnalysisQueueable (execute, buildSuggestions, calculateConfidence) |
| `testDecayBatch_StaleMemory_ReducesStrength` | AgentMemoryService (applyStrengthDecay) |
| `testDecayBatch_Schedule_RunsSuccessfully` | MemoryStrengthDecayBatch (execute/SchedulableContext) |
| `testGetPendingSuggestions_ValidEntityId_ReturnsSuggestions` | AgentMemoryController, AgentMemorySelector |
| `testGetPendingSuggestions_BlankEntityId_ThrowsException` | AgentMemoryController (validation) |
| `testGetActionHistory_ValidEntityId_ReturnsLogs` | AgentMemoryController, AgentMemorySelector |
| `testGetMemoryHeatmap_ReturnsAllThreeClouds` | AgentMemoryController (getMemoryHeatmap, averageStrength, getTopPatterns) |
| `testRecordMemoryContext_ValidJson_CreatesMemory` | AgentMemoryController (JSON deserialization) |
| `testAcceptSuggestion_ViaController_UpdatesStatus` | AgentMemoryController → AgentMemoryService |
| `testSelector_GetByCloudAndStrength_FiltersCorrectly` | AgentMemorySelector |
| `testSelector_GetByOrgContextHash_ReturnsNull_WhenNotFound` | AgentMemorySelector |
| `testSelector_GetSuggestionFeedback_ReturnsAggregateResult` | AgentMemorySelector |

---

## Test Data Strategy

The test suite uses `@TestSetup` to create shared data:

- One `Account` record ("Test Corp")
- One `Agent_Memory__c` record linked to the Account (Sales Cloud, strength 50, pattern count 3)
- One `Agent_Suggestion__c` record in Pending status with 72-hour expiry

Individual test methods create additional records as needed (e.g., new accounts for cross-cloud tests, stale memories for decay tests).

---

## Testing Async Operations

Queueable and batch operations are wrapped in `Test.startTest()` / `Test.stopTest()` blocks to ensure synchronous execution in tests. This includes:

- `CrossCloudAnalysisQueueable` — Enqueued in `recordAndLearn()`, executes inline in tests
- `FlowExecutionQueueable` — Indirectly tested via `acceptSuggestion()`
- `MemoryStrengthDecayBatch` — Scheduled via `System.schedule()` in test context

---

## LWC Unit Testing (Jest)

The project includes a `jest.config.js` for LWC Jest testing. To run:

```bash
npm install
npm run test
```

Jest tests can mock the `@wire` adapters and verify component behavior for loading states, suggestions rendering, accept/dismiss event dispatch, and dismiss modal interaction.
