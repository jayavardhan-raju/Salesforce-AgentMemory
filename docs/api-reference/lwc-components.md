---
layout: default
title: LWC Components
parent: API Reference
nav_order: 2
---

# LWC Component Reference

AgentMemory ships with two Lightning Web Components designed to be placed on any record page.

---

## agentMemoryDashboard

The primary record-page component. It provides a full view of the agent memory state for the current record, including memory strength, cross-cloud suggestions, and action history.

### Configuration

**Target:** Lightning Record Page  
**API Version:** 62.0

Place this component on any Account, Contact, Lead, Opportunity, Case, or Campaign Lightning page via the Lightning App Builder.

### Public Properties

| Property | Type | Source | Description |
|----------|------|--------|-------------|
| `recordId` | String | Injected by framework | The current record's ID. Automatically set by the Lightning record page. |

### Wired Data Sources

| Wire | Apex Method | Cacheable | Description |
|------|------------|-----------|-------------|
| `wiredSuggestions` | `AgentMemoryController.getPendingSuggestions` | Yes | Pending, non-expired suggestions for this entity |
| `wiredMemory` | `AgentMemoryController.getMemoriesForEntities` | Yes | Memory records for this entity |
| `wiredHistory` | `AgentMemoryController.getActionHistory` | Yes | 20 most recent action log entries |

### UI Sections

**Memory Strength Bar**  
Displays a horizontal progress bar color-coded by strength: green (≥80%), blue (≥40%), grey (<40%). Shows the percentage, pattern count, cloud source, and intent tags.

**Cross-Cloud Suggestions**  
Lists pending suggestions as `c-agent-suggestion-card` child components. Shows a badge with the count. If no suggestions are pending, displays a check icon with a monitoring message.

**Action History**  
An expandable table showing the action name, type, acceptance status (check/cross icon), and date. Toggle visibility with a chevron link.

**Dismiss Modal**  
A modal dialog with a textarea for capturing the dismissal reason. Triggered when a user clicks "Dismiss" on a suggestion card.

### Event Handling

| Event | Source | Handler | Action |
|-------|--------|---------|--------|
| `accept` | `c-agent-suggestion-card` | `handleAccept` | Calls `acceptSuggestion`, refreshes all wired data, shows success toast |
| `dismiss` | `c-agent-suggestion-card` | `handleDismiss` | Opens dismiss modal, stores suggestion ID |
| Confirm dismiss | Modal button | `confirmDismiss` | Calls `dismissSuggestion` with reason, refreshes data, shows info toast |
| Refresh | Header button | `handleRefresh` | Refreshes all three wired results |
| Toggle history | Link click | `toggleHistory` | Shows/hides the action log table |

### Error Handling

All errors are caught and displayed inline with a red error icon and message text. The `handleError()` method extracts messages from Aura response bodies, strings, or falls back to a generic message.

---

## agentSuggestionCard

A reusable child component that renders a single cross-cloud suggestion as a styled card.

### Public Properties

| Property | Type | Description |
|----------|------|-------------|
| `suggestion` | Object | An `Agent_Suggestion__c` record with fields: `Source_Cloud__c`, `Target_Cloud__c`, `Suggestion_Body__c`, `Confidence_Score__c`, `Expires_At__c`, `Id` |

### Visual Design

**Card Border**  
Left border color indicates confidence tier:
- Green (`#4CAF50`) — High confidence (≥80%)
- Blue (`#2196F3`) — Moderate confidence (≥60%)
- Grey (`#9E9E9E`) — Low confidence (≥40%)

**Cloud Route Badges**  
Pill-shaped badges showing source → target cloud with a forward arrow icon:
- Sales Cloud: Blue background (`#e1f0ff`), dark blue text
- Service Cloud: Green background (`#e8f5e9`), dark green text
- Marketing Cloud: Orange background (`#fff3e0`), dark orange text

**Confidence Bar**  
A thin 4px progress bar matching the tier color.

**Confidence Label**  
Displays the score with a human-readable tier: "75% — Moderate Confidence"

**Expiry Notice**  
Shows the expiration date formatted as "Mar 15, 2:30 PM"

### Dispatched Events

| Event | Bubbles | Composed | Detail | Description |
|-------|---------|----------|--------|-------------|
| `accept` | Yes | Yes | `{ suggestionId: Id }` | User clicked Accept |
| `dismiss` | Yes | Yes | `{ suggestionId: Id }` | User clicked Dismiss |

Both events bubble up to the parent `agentMemoryDashboard` for processing.

### CSS Classes

| Class | Description |
|-------|-------------|
| `.suggestion-card` | Base card container with border-radius and transition |
| `.suggestion-card_high` | Green left border |
| `.suggestion-card_moderate` | Blue left border |
| `.suggestion-card_low` | Grey left border |
| `.cloud-badge` | Pill badge base |
| `.cloud-badge_sales` | Blue pill for Sales Cloud |
| `.cloud-badge_service` | Green pill for Service Cloud |
| `.cloud-badge_marketing` | Orange pill for Marketing Cloud |
| `.confidence-track` / `.confidence-fill` | Progress bar track and fill |
