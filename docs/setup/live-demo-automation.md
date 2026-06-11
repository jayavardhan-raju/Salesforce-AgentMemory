---
layout: default
title: Live Demo Automation
parent: Setup
nav_order: 5
---

# Live Demo Automation

The live demo flow starts at [Launch Live Demo](../live-demo.html) and provisions a scratch org from the requester's Salesforce Dev Hub.

## Required Services

| Service | Purpose |
|---|---|
| GitHub Pages | Hosts the secure launch form |
| Cloudflare Worker + KV | Short-lived auth URL broker |
| GitHub Actions | Claims the auth URL once, provisions the demo org, and runs a Playwright UI walkthrough (Chromium + ffmpeg) |
| Mailtrap | Sends login credentials, expiration date, scenario results, the demo GIF, and an artifact link |

## Broker Deployment

The Worker source lives in `broker/cloudflare-worker/`.

```bash
cd broker/cloudflare-worker
wrangler kv namespace create AUTH_TOKENS
# paste the returned id into wrangler.toml
wrangler secret put GITHUB_TOKEN
wrangler secret put ACTIONS_BROKER_TOKEN
wrangler deploy
```

After deployment, make sure `docs/live-demo.md` points its form `data-broker-url` to the Worker's `/launch` URL.

## GitHub Settings

Add these settings to `jayavardhan-raju/Salesforce-AgentMemory`:

| Type | Name | Value |
|---|---|---|
| Repository variable | `DEMO_BROKER_CLAIM_URL` | Worker `/claim` URL |
| Repository secret | `DEMO_BROKER_ACTIONS_TOKEN` | Same value as the Worker `ACTIONS_BROKER_TOKEN` secret |
| Repository secret | `MAILTRAP_USER` | Mailtrap SMTP username |
| Repository secret | `MAILTRAP_PASS` | Mailtrap SMTP password / API token |
| Repository variable | `MAILTRAP_FROM_EMAIL` | Verified Mailtrap sender |
| Repository variable | `MAILTRAP_FROM_NAME` | Sender display name |

## Security Contract

- The Salesforce Dev Hub auth URL is accepted only by the HTTPS broker.
- The broker dispatches GitHub Actions with a request id and one-time claim token, not the auth URL.
- GitHub Actions writes the auth URL only to `$RUNNER_TEMP/sfauth.txt`, masks it, logs in with Salesforce CLI, and deletes the file immediately.
- Uploaded artifacts contain JSON summaries (request, scratch org selection, org summary, scenario results, UI walkthrough results), dashboard screenshots, and the demo GIF. They do not contain the Dev Hub auth URL or scratch org password.
- The Mailtrap email contains the scratch org login URL, username, password, expiration date, scenario/test results, the demo GIF, run/artifact link, repository link, and docs link.

## Expected Run

1. Verify the requester fork belongs to the submitted GitHub username and is a fork of `jayavardhan-raju/Salesforce-AgentMemory`.
2. Claim the auth URL once from the broker.
3. Create a Developer-edition scratch org for the selected duration using `config/project-scratch-def.json`.
4. Deploy `force-app` (including the `AgentMemory_Demo` app + Account/Contact record pages) and assign the `AgentMemory_Access` permission set.
5. Run the three demo scenarios (`TC1`–`TC3`) and the `AgentMemoryServiceTest` suite with code coverage. These also seed the Accounts/Contacts the UI walkthrough films.
6. Run the Playwright UI walkthrough: open each seeded record's Agent Memory dashboard, accept the top suggestion, and screenshot each step.
7. Stitch the screenshots into `agentmemory-demo.gif`.
8. Generate a scratch org password, upload artifacts, and send the Mailtrap email with credentials, scenario results, coverage, and the demo GIF attached.

Demo scenarios and unit tests are reported honestly: a scenario or test failure is recorded in `scenario-results.json` and the email, while the org credentials are still delivered so the requester can inspect the org. The UI walkthrough is best-effort (`continue-on-error`): if a page or selector is unavailable, the GIF is built from whatever screenshots exist and the email still goes out.

### UI Walkthrough Setup Notes

The `AgentMemory_Demo` Lightning app ships an action override that makes the Agent Memory dashboard the active Account and Contact record page, and the `AgentMemory_Access` permission set grants the app to the scratch user. If a future org does not pick up the override, set `AgentMemory Account Record Page` as the Org Default in Lightning App Builder (one click) — the walkthrough also falls back to the standard record URL and soft-fails rather than blocking the run.
