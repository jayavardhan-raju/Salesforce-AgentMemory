---
layout: default
title: Deployment
parent: Setup
nav_order: 1
---

# Deployment Guide

---

## Prerequisites

- **Salesforce CLI** — `sf` (v2+) or `sfdx` installed and authenticated
- **Salesforce Org** — Scratch org, sandbox, or production with Sales Cloud and Service Cloud
- **Node.js 18+** — For local development tooling (ESLint, Prettier, Jest)
- **Permission** — System Administrator profile or equivalent deploy permissions

---

## Option 1: Scratch Org (Recommended for Development)

```bash
# 1. Clone the repository
git clone https://github.com/jayavardhan-raju/Salesforce-AgentMemory.git
cd Salesforce-AgentMemory

# 2. Create a scratch org (30-day duration)
sf org create scratch \
  -f config/project-scratch-def.json \
  -a AgentMemory \
  -d 30

# 3. Push all source
sf project deploy start -o AgentMemory

# 4. Assign the permission set
sf org assign permset -n AgentMemory_Access -o AgentMemory

# 5. Open the org
sf org open -o AgentMemory
```

---

## Option 2: Sandbox / Production

```bash
# 1. Authenticate to the target org
sf org login web -a MyOrg

# 2. Deploy using the manifest
sf project deploy start \
  -x manifest/package.xml \
  -o MyOrg

# 3. Assign the permission set to relevant users
sf org assign permset -n AgentMemory_Access -o MyOrg
```

---

## Post-Deployment Configuration

### 1. Schedule the Nightly Decay Batch

Open the Developer Console or execute via CLI:

```apex
System.schedule(
    'AgentMemory Nightly Decay',
    '0 0 2 * * ?',           // 2:00 AM daily
    new MemoryStrengthDecayBatch()
);
```

To verify the job is scheduled:

```apex
List<CronTrigger> jobs = [
    SELECT Id, CronJobDetail.Name, NextFireTime
    FROM CronTrigger
    WHERE CronJobDetail.Name = 'AgentMemory Nightly Decay'
];
System.debug(jobs);
```

### 2. Create Automation Flows

The framework references five Flows by API name. Create these as **Auto-Launched Flows** in your org:

| Flow API Name | Purpose | Input Variable |
|--------------|---------|----------------|
| `AgentMemory_CreateOnboardingCase` | Creates a Service Cloud onboarding case | `entityId` (Text) |
| `AgentMemory_TriggerNurtureJourney` | Enrolls contact in a Marketing Cloud journey | `entityId` (Text) |
| `AgentMemory_CreateUpsellTask` | Creates a Sales Cloud upsell task | `entityId` (Text) |
| `AgentMemory_EnrollSatisfactionJourney` | Enrolls in a satisfaction survey journey | `entityId` (Text) |
| `AgentMemory_CreateOutreachTask` | Creates a Sales Cloud outreach task | `entityId` (Text) |

Each Flow should accept a single Text input variable named `entityId` and implement the relevant automation logic for your org.

### 3. Add the Dashboard Component to Record Pages

1. Navigate to a record page (e.g., Account)
2. Click the gear icon → **Edit Page**
3. Drag **agentMemoryDashboard** from the component list onto the page
4. Save and activate the page

The component will automatically bind to the record's ID and display memory, suggestions, and history.

### 4. Assign Permission Set

Ensure all users who need access have the `AgentMemory_Access` permission set:

```bash
# Assign to a single user
sf org assign permset \
  -n AgentMemory_Access \
  -o MyOrg \
  -b "user@example.com"
```

Or assign via Setup → Permission Sets → AgentMemory_Access → Manage Assignments.

---

## Uninstallation

To remove AgentMemory from an org:

1. Remove the `agentMemoryDashboard` component from all Lightning pages
2. Unschedule the decay batch
3. Delete records from `Agent_Action_Log__c`, `Agent_Suggestion__c`, and `Agent_Memory__c`
4. Remove the metadata via destructive changes or manual deletion
