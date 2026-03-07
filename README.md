# Salesforce AgentMemory

**A native Apex architecture that enables Sales Cloud, Service Cloud, and Marketing Cloud to learn from each other — with zero middleware, zero hardcoded integrations, and a self-tuning confidence engine.**

---

## Overview

Salesforce AgentMemory is a platform-native framework that gives your Salesforce org a **shared memory layer** across clouds. When a sales rep closes a deal, Service Cloud automatically knows to create an onboarding case. When a support case resolves positively, Sales Cloud gets an upsell signal. When Marketing Cloud detects high engagement, Sales Cloud receives an outreach task — all without a single line of middleware or external integration.

The system learns over time: every interaction **reinforces** memory, every dismissal **decays** it, and a nightly batch implements a **forgetting curve** that archives stale patterns. A confidence engine calculates suggestion quality from pattern frequency and memory strength, ensuring agents only surface high-value cross-cloud actions.

### Key Capabilities

- **Cross-Cloud Intelligence** — Automatic suggestion generation when activity in one cloud signals an action in another
- **Self-Tuning Confidence Engine** — Dynamically scores suggestions using pattern count + memory strength; filters below 40%
- **Memory Strength Lifecycle** — New memories start at 50, reinforced +10 per interaction (capped at 100), decayed -5 on dismissal, and aged out by a nightly scheduled batch
- **Zero Middleware** — Built entirely on native Apex, Queueable, Batch, and LWC — no external services required
- **Flow-Based Automation** — Accepted suggestions can trigger any Salesforce Flow by API name, enabling declarative automation chaining
- **Full Audit Trail** — Every action (reinforcement, acceptance, dismissal) is logged to `Agent_Action_Log__c` with user, timestamp, and context

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    LWC PRESENTATION                      │
│  ┌─────────────────────┐  ┌──────────────────────────┐  │
│  │ agentMemoryDashboard │  │   agentSuggestionCard    │  │
│  └──────────┬──────────┘  └────────────┬─────────────┘  │
│             │                          │                 │
├─────────────┼──────────────────────────┼─────────────────┤
│             ▼          CONTROLLER      ▼                 │
│  ┌───────────────────────────────────────────────────┐   │
│  │            AgentMemoryController                  │   │
│  │   @AuraEnabled methods — no logic, delegates all  │   │
│  └──────────────────────┬────────────────────────────┘   │
│                         │                                │
├─────────────────────────┼────────────────────────────────┤
│                         ▼          SERVICE               │
│  ┌───────────────────────────────────────────────────┐   │
│  │             AgentMemoryService                    │   │
│  │   recordAndLearn()  acceptSuggestion()            │   │
│  │   dismissSuggestion()  applyStrengthDecay()       │   │
│  └───┬──────────────┬──────────────┬─────────────────┘   │
│      │              │              │                      │
│      ▼              ▼              ▼                      │
│  ┌────────┐  ┌────────────┐  ┌────────────────────────┐  │
│  │Selector│  │ Queueables │  │  MemoryStrengthDecay   │  │
│  │ (SOQL) │  │ CrossCloud │  │       Batch            │  │
│  │        │  │ FlowExec   │  │  (Forgetting Curve)    │  │
│  └────────┘  └────────────┘  └────────────────────────┘  │
│                                                          │
├──────────────────────────────────────────────────────────┤
│                     DATA MODEL                           │
│  Agent_Memory__c ─┬─< Agent_Suggestion__c                │
│                   └─< Agent_Action_Log__c                │
└──────────────────────────────────────────────────────────┘
```

The project follows a strict **Trigger → Handler → Service → Selector** pattern:

| Layer | Class | Responsibility |
|-------|-------|----------------|
| **Trigger** | `AgentMemoryTrigger` | Delegates to handler — zero logic |
| **Handler** | `AgentMemoryTriggerHandler` | Routes trigger events, builds DTOs |
| **Service** | `AgentMemoryService` | All business logic: upsert, reinforce, decay, log |
| **Selector** | `AgentMemorySelector` | All SOQL queries — zero DML |
| **Controller** | `AgentMemoryController` | `@AuraEnabled` surface — delegates to Service |
| **Async** | `CrossCloudAnalysisQueueable` | Cross-cloud pattern matching + suggestion generation |
| **Async** | `FlowExecutionQueueable` | Invokes named Flows when suggestions are accepted |
| **Batch** | `MemoryStrengthDecayBatch` | Nightly forgetting curve — decays and archives stale memories |
| **DTO** | `AgentActionLogDTO` | Lightweight data transfer for action log creation |

---

## Data Model

### Agent_Memory__c (Core Memory)

The central record — one per entity + cloud + org combination, deduplicated via SHA-256 hash.

| Field | Type | Description |
|-------|------|-------------|
| `Cloud_Source__c` | Picklist | Sales Cloud / Service Cloud / Marketing Cloud |
| `Entity_Id__c` | Text(18) | 18-char Salesforce record ID of the tracked entity |
| `Entity_Type__c` | Picklist | Account, Contact, Lead, Opportunity, Case, Campaign |
| `Context_Payload__c` | Long Text (128KB) | Raw JSON context snapshot from last interaction |
| `Memory_Strength__c` | Number(5,2) | 0–100 score. Created at 50, +10 reinforce, -5 dismiss/decay |
| `Pattern_Count__c` | Number | Incremented on each `recordAndLearn()` call |
| `Intent_Tags__c` | Text(255) | Comma-separated learned intent signals (max 10) |
| `Org_Context_Hash__c` | Text(64) | SHA-256 unique key for upsert deduplication |
| `Last_Action_Taken__c` | Text(255) | Label of the most recent agent action |
| `Last_Interacted_By__c` | Lookup(User) | User who triggered the last memory write |

### Agent_Suggestion__c (Cross-Cloud Suggestions)

Suggestions generated asynchronously by `CrossCloudAnalysisQueueable`.

| Field | Type | Description |
|-------|------|-------------|
| `Source_Cloud__c` | Picklist | Cloud that triggered the suggestion |
| `Target_Cloud__c` | Picklist | Cloud where the automation should execute |
| `Suggestion_Body__c` | Long Text | Natural-language explanation with intent signals |
| `Confidence_Score__c` | Percent(5,1) | 0–99.9% — below 40% is filtered before insert |
| `Status__c` | Picklist | Pending → Accepted / Dismissed / Expired |
| `Flow_API_Name__c` | Text(255) | Developer name of Flow to invoke on acceptance |
| `Expires_At__c` | DateTime | TTL — 72 hours from creation |
| `Dismissed_Reason__c` | Text(255) | User-provided reason on dismissal |
| `Agent_Memory__c` | Lookup | Parent memory. Accept boosts +10, dismiss decays -5 |

### Agent_Action_Log__c (Audit Trail)

Immutable log of every agent action for analytics and compliance.

| Field | Type | Description |
|-------|------|-------------|
| `Action_Name__c` | Text(255) | Free-text label (required) |
| `Action_Type__c` | Picklist | Automation_Created, Record_Updated, Suggestion_Accepted, Suggestion_Dismissed, Cross_Cloud_Triggered, Memory_Reinforced |
| `Cloud_Source__c` | Picklist | Originating cloud |
| `Entity_Id__c` | Text(18) | Associated entity |
| `Input_Context__c` | Long Text (32KB) | JSON input that triggered the action |
| `Output_Result__c` | Long Text (32KB) | Result of the action |
| `User_Accepted__c` | Checkbox | True if explicitly accepted |
| `Executed_By__c` | Lookup(User) | User who triggered the log entry |
| `Agent_Memory__c` | Lookup | Optional parent memory record |

---

## Confidence Engine

The confidence engine determines suggestion quality using a formula based on pattern frequency and memory strength:

```
Base Confidence     = 50.0
Pattern Bonus       = min(30, patternCount × 2)
Strength Bonus      = min(20, (memoryStrength / 10) × 2)
───────────────────────────────────────────────────
Raw Confidence      = min(100, base + patternBonus + strengthBonus)
Adjusted Confidence = rawConfidence × (templateBaseConfidence / 100)
```

Suggestions with adjusted confidence below **40%** are discarded before insert. Template base confidence varies by cloud pair (e.g., Service → Sales upsell signals carry 80% base confidence, while Marketing → Sales outreach carries 85%).

### Cross-Cloud Suggestion Templates

| Source Cloud | Target Cloud | Automation Flow | Base Confidence |
|-------------|-------------|-----------------|-----------------|
| Sales Cloud | Service Cloud | `AgentMemory_CreateOnboardingCase` | 75% |
| Sales Cloud | Marketing Cloud | `AgentMemory_TriggerNurtureJourney` | 70% |
| Service Cloud | Sales Cloud | `AgentMemory_CreateUpsellTask` | 80% |
| Service Cloud | Marketing Cloud | `AgentMemory_EnrollSatisfactionJourney` | 65% |
| Marketing Cloud | Sales Cloud | `AgentMemory_CreateOutreachTask` | 85% |

---

## LWC Components

### agentMemoryDashboard

The primary record-page component. Drop it onto any Account, Contact, Lead, Opportunity, Case, or Campaign Lightning page.

**Features:**
- Real-time memory strength indicator with color-coded progress bar (green ≥80%, blue ≥40%, grey <40%)
- Cross-cloud suggestion list with accept/dismiss actions
- Expandable action history table with pagination
- Dismiss modal with optional reason capture
- Full `refreshApex` integration for instant UI updates

### agentSuggestionCard

Reusable child component rendering individual suggestions.

**Features:**
- Cloud-route badges with color-coded pills (Sales = blue, Service = green, Marketing = orange)
- Confidence tier indicator with progress bar
- Expiration countdown
- Bubble-up custom events for accept/dismiss

---

## Setup & Deployment

### Prerequisites

- Salesforce DX CLI (`sf` or `sfdx`)
- A Salesforce org with Sales Cloud and Service Cloud enabled
- Node.js 18+ (for local development tooling)

### Deploy to a Scratch Org

```bash
# Clone the repository
git clone https://github.com/jayavardhan-raju/Salesforce-AgentMemory.git
cd Salesforce-AgentMemory

# Create a scratch org
sf org create scratch -f config/project-scratch-def.json -a AgentMemory -d 30

# Push source
sf project deploy start -o AgentMemory

# Assign the permission set
sf org assign permset -n AgentMemory_Access -o AgentMemory

# Open the org
sf org open -o AgentMemory
```

### Deploy to a Sandbox or Production

```bash
# Authenticate
sf org login web -a MyOrg

# Deploy with the manifest
sf project deploy start -x manifest/package.xml -o MyOrg

# Assign the permission set
sf org assign permset -n AgentMemory_Access -o MyOrg
```

### Schedule the Decay Batch

After deployment, schedule the forgetting curve batch to run nightly:

```apex
// Execute in Anonymous Apex
System.schedule(
    'AgentMemory Nightly Decay',
    '0 0 2 * * ?',   // 2:00 AM daily
    new MemoryStrengthDecayBatch()
);
```

### Create Automation Flows

The system ships with Flow API name references but not the Flows themselves. Create these auto-launched Flows in your org:

| Flow API Name | Purpose | Input Variable |
|--------------|---------|----------------|
| `AgentMemory_CreateOnboardingCase` | Creates a Service Cloud onboarding case | `entityId` (Text) |
| `AgentMemory_TriggerNurtureJourney` | Enrolls contact in Marketing Cloud journey | `entityId` (Text) |
| `AgentMemory_CreateUpsellTask` | Creates a Sales Cloud upsell task | `entityId` (Text) |
| `AgentMemory_EnrollSatisfactionJourney` | Enrolls in satisfaction survey journey | `entityId` (Text) |
| `AgentMemory_CreateOutreachTask` | Creates a Sales Cloud outreach task | `entityId` (Text) |

---

## Security

- All DML operations use `Security.stripInaccessible()` to enforce CRUD/FLS
- All classes use `with sharing` to respect org-wide defaults and sharing rules
- Object-level `isCreateable()` / `isUpdateable()` checks before every DML
- Permission set `AgentMemory_Access` grants field-level access to all three custom objects
- SHA-256 hashing for deduplication keys prevents enumeration attacks

---

## Testing

The test suite (`AgentMemoryServiceTest`) covers:

- `recordAndLearn()` — new entity creation and existing entity reinforcement
- `acceptSuggestion()` — status update, memory boost, Flow invocation
- `dismissSuggestion()` — status update, memory decay, reason capture
- `CrossCloudAnalysisQueueable` — async suggestion generation
- `MemoryStrengthDecayBatch` — scheduled strength decay
- `AgentMemoryController` — all `@AuraEnabled` methods
- `AgentMemorySelector` — hash lookup, cloud/strength filtering, aggregate feedback

Run the tests:

```bash
sf apex test run -n AgentMemoryServiceTest -r human -o AgentMemory
```

---

## Project Structure

```
Salesforce-AgentMemory/
├── force-app/main/default/
│   ├── classes/
│   │   ├── AgentActionLogDTO.cls            # DTO for action log creation
│   │   ├── AgentMemoryController.cls        # @AuraEnabled LWC controller
│   │   ├── AgentMemorySelector.cls          # All SOQL queries
│   │   ├── AgentMemoryService.cls           # Core business logic
│   │   ├── AgentMemoryServiceTest.cls       # Test suite (≥90% coverage)
│   │   ├── AgentMemoryTriggerHandler.cls    # Trigger event router
│   │   ├── CrossCloudAnalysisQueueable.cls  # Async cross-cloud suggestions
│   │   ├── FlowExecutionQueueable.cls       # Async Flow invocation
│   │   └── MemoryStrengthDecayBatch.cls     # Nightly forgetting curve
│   ├── lwc/
│   │   ├── agentMemoryDashboard/            # Main record-page component
│   │   └── agentSuggestionCard/             # Suggestion card component
│   ├── objects/
│   │   ├── Agent_Memory__c/                 # Core memory object + fields
│   │   ├── Agent_Suggestion__c/             # Cross-cloud suggestions
│   │   └── Agent_Action_Log__c/             # Audit trail
│   ├── permissionsets/
│   │   └── AgentMemory_Access               # FLS permission set
│   └── triggers/
│       └── AgentMemoryTrigger               # Delegating trigger
├── config/                                   # Scratch org config
├── manifest/                                 # package.xml
├── docs/                                     # Documentation site
└── sfdx-project.json
```

---

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -am 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

---

## License

This project is open source. See the repository for license details.

---

## Author

**Jayavardhan Raju** — [GitHub](https://github.com/jayavardhan-raju)
