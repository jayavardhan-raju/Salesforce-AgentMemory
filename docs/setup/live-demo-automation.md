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
| GitHub Actions | Claims the auth URL once and provisions the demo org |
| Mailtrap | Sends login credentials, expiration date, scenario results, and artifact link |

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
- Uploaded artifacts contain JSON summaries (request, scratch org selection, org summary, scenario results). They do not contain the Dev Hub auth URL or scratch org password.
- The Mailtrap email contains the scratch org login URL, username, password, expiration date, scenario/test results, run/artifact link, repository link, and docs link.

## Expected Run

1. Verify the requester fork belongs to the submitted GitHub username and is a fork of `jayavardhan-raju/Salesforce-AgentMemory`.
2. Claim the auth URL once from the broker.
3. Create a Developer-edition scratch org for the selected duration using `config/project-scratch-def.json`.
4. Deploy `force-app` and assign the `AgentMemory_Access` permission set.
5. Run the three demo scenarios (`TC1`–`TC3`) and the `AgentMemoryServiceTest` suite with code coverage.
6. Generate a scratch org password, upload artifacts, and send the Mailtrap email with credentials, scenario results, and coverage.

Demo scenarios and unit tests are reported honestly: a scenario or test failure is recorded in `scenario-results.json` and the email, while the org credentials are still delivered so the requester can inspect the org.
