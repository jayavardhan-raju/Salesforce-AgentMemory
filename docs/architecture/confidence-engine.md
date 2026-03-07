---
layout: default
title: Confidence Engine
parent: Architecture
nav_order: 3
---

# Confidence Engine

The confidence engine is the intelligence layer that determines which cross-cloud suggestions are worth surfacing. It combines pattern frequency with memory strength to produce a composite score, then adjusts it per template.

---

## Formula

The `calculateConfidence()` method in `CrossCloudAnalysisQueueable` computes confidence in three steps:

### Step 1: Raw Confidence

```
Base            = 50.0  (starting point)
Pattern Bonus   = min(30, patternCount × 2)
Strength Bonus  = min(20, (memoryStrength / 10) × 2)
────────────────────────────────────────────────────
Raw Confidence  = min(100, Base + PatternBonus + StrengthBonus)
```

The pattern bonus rewards repeated interactions (up to 15 repetitions to reach the 30-point cap). The strength bonus rewards recently active memories (a strength of 100 contributes the full 20 points).

### Step 2: Template Adjustment

Each cross-cloud template carries a `baseConfidence` specific to the cloud pair. The raw confidence is multiplied by this value:

```
Adjusted Confidence = Raw Confidence × (templateBaseConfidence / 100)
```

For example, a memory with pattern count 8 and strength 70:

```
Raw = min(100, 50 + min(30, 16) + min(20, 14)) = min(100, 80) = 80

Service → Sales template (base 80%):
  Adjusted = 80 × 0.80 = 64.0%  ✅ Above threshold

Service → Marketing template (base 65%):
  Adjusted = 80 × 0.65 = 52.0%  ✅ Above threshold
```

### Step 3: Threshold Filter

Any suggestion with an adjusted confidence **below 40%** is discarded and never inserted into `Agent_Suggestion__c`. This prevents low-quality noise from reaching users.

The adjusted confidence is also capped at **99.9%** to avoid false certainty.

---

## Template Confidence Values

| Source → Target | Template | Base Confidence | Rationale |
|----------------|----------|-----------------|-----------|
| Sales → Service | Create Onboarding Case | 75% | Deal progression is a strong but not certain onboarding signal |
| Sales → Marketing | Trigger Nurture Journey | 70% | New deals benefit from adoption nurturing, but timing varies |
| Service → Sales | Create Upsell Task | 80% | Positive case resolution is a very strong upsell indicator |
| Service → Marketing | Enroll Satisfaction Journey | 65% | Service interactions may or may not warrant marketing follow-up |
| Marketing → Sales | Create Outreach Task | 85% | High engagement in marketing journeys is the strongest intent signal |

---

## Memory Strength Lifecycle

Memory strength directly feeds the confidence formula. Here's how it evolves:

| Event | Strength Change | Notes |
|-------|----------------|-------|
| New memory created | Set to **50** | Starting point |
| `recordAndLearn()` called on existing memory | **+10** (capped at 100) | Reinforcement |
| Suggestion accepted | Parent memory **+10** | Positive feedback loop |
| Suggestion dismissed | Parent memory **-5** | Negative feedback |
| Nightly batch (30+ days stale) | **-5** per cycle | Forgetting curve |
| Strength falls below 5.0 | **Deleted** | Archive threshold |

This creates a natural lifecycle: active memories grow stronger and produce higher-confidence suggestions, while neglected memories fade and eventually disappear.

---

## Deduplication

Before inserting suggestions, the queueable checks existing pending suggestions for the same `Entity_Id__c` and `Target_Cloud__c`. If a pending suggestion already exists for a given target cloud, no duplicate is created. This prevents suggestion flooding when `recordAndLearn()` is called frequently.

---

## Tuning the Engine

To adjust the system's sensitivity:

| Parameter | Location | Default | Effect |
|-----------|----------|---------|--------|
| `STRENGTH_REINFORCEMENT_BOOST` | `AgentMemoryService` | 10.0 | Higher = faster confidence growth |
| `STRENGTH_NEW_MEMORY` | `AgentMemoryService` | 50.0 | Higher = new entities get stronger initial suggestions |
| `STRENGTH_CAP` | `AgentMemoryService` | 100.0 | Maximum memory strength |
| `SUGGESTION_EXPIRY_HOURS` | `AgentMemoryService` | 72 | TTL for pending suggestions |
| `MAX_TAGS_PER_MEMORY` | `AgentMemoryService` | 10 | Max intent tags per memory |
| `DECAY_AMOUNT` | `MemoryStrengthDecayBatch` | 5.0 | Nightly decay rate |
| `ARCHIVE_THRESHOLD` | `MemoryStrengthDecayBatch` | 5.0 | Strength below which memories are deleted |
| Template `baseConfidence` | `CrossCloudAnalysisQueueable` | 65–85% | Per-template confidence multiplier |
| Minimum threshold | `CrossCloudAnalysisQueueable` | 40% | Below this, suggestions are discarded |
