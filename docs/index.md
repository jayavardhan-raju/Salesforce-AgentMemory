---
layout: default
title: Home
nav_order: 1
---

# Salesforce AgentMemory Documentation

Welcome to the documentation for **Salesforce AgentMemory** — a platform-native Apex framework that enables Sales Cloud, Service Cloud, and Marketing Cloud to learn from each other with zero middleware and a self-tuning confidence engine.

---

## Quick Navigation

| Section | Description |
|---------|-------------|
| [Architecture](architecture/overview.md) | System design, layered architecture, and data flow |
| [Data Model](architecture/data-model.md) | Custom objects, fields, and relationships |
| [Confidence Engine](architecture/confidence-engine.md) | How suggestions are scored and filtered |
| [API Reference](api-reference/apex-classes.md) | ApexDox-style documentation for all classes |
| [LWC Components](api-reference/lwc-components.md) | Lightning Web Component reference |
| [Setup Guide](setup/deployment.md) | Deploy, configure, and schedule |
| [Testing](setup/testing.md) | Run the test suite and coverage targets |

---

## What Is AgentMemory?

In a typical Salesforce org, Sales Cloud, Service Cloud, and Marketing Cloud operate as independent silos. A sales rep closes a deal, but Service Cloud has no awareness to proactively onboard the customer. A support case resolves positively, but the upsell signal never reaches the sales team.

AgentMemory solves this by introducing a **shared memory layer** that:

1. **Observes** — Records agent actions as memory entries with context, intent tags, and strength scores
2. **Learns** — Reinforces memory on repeated patterns, decays on dismissals, and archives stale data
3. **Suggests** — Generates cross-cloud suggestions with confidence scores and linked automation Flows
4. **Adapts** — User feedback (accept/dismiss) directly tunes the system's future behavior

All of this happens natively within Salesforce — no middleware, no external APIs, no integration platform.
