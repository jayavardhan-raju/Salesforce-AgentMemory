# Salesforce AgentMemory Auth Broker

Short-lived broker for live demo launches from GitHub Pages.

The GitHub Pages form sends the requester details and Salesforce Dev Hub auth URL to this Worker over HTTPS. The Worker stores the auth URL in Cloudflare KV with a short TTL, triggers a `repository_dispatch` event, lets GitHub Actions claim the auth URL once, then deletes it immediately.

## Endpoints

| Method | Path | Caller | Purpose |
|---|---|---|---|
| `POST` | `/launch` | GitHub Pages | Validate request, store auth URL temporarily, dispatch GitHub Actions |
| `POST` | `/claim` | GitHub Actions | Return auth URL once, then delete it |
| `GET` | `/health` | Monitoring | Broker health check |

## Cloudflare Setup

1. Create a KV namespace:

   ```bash
   wrangler kv namespace create AUTH_TOKENS
   ```

2. Update `wrangler.toml` with the returned namespace id.

3. Set Worker secrets:

   ```bash
   wrangler secret put GITHUB_TOKEN
   wrangler secret put ACTIONS_BROKER_TOKEN
   ```

   `GITHUB_TOKEN` must be a fine-grained GitHub token with permission to call `repository_dispatch` on `jayavardhan-raju/Salesforce-AgentMemory`.

4. Deploy:

   ```bash
   wrangler deploy
   ```

5. Add these GitHub repository settings:

   | Type | Name | Value |
   |---|---|---|
   | Repository variable | `DEMO_BROKER_CLAIM_URL` | `https://<worker-host>/claim` |
   | Repository secret | `DEMO_BROKER_ACTIONS_TOKEN` | Same value as `ACTIONS_BROKER_TOKEN` |
   | Repository secret | `MAILTRAP_USER` | Mailtrap SMTP username |
   | Repository secret | `MAILTRAP_PASS` | Mailtrap SMTP password / API token |
   | Repository variable | `MAILTRAP_FROM_EMAIL` | Verified sender |
   | Repository variable | `MAILTRAP_FROM_NAME` | Sender display name |

## Security Notes

- The Salesforce auth URL is never accepted through GitHub Issues, workflow inputs, or repository secrets.
- `/launch` rejects malformed auth URLs and never echoes the secret back.
- `/claim` requires both the one-time claim token from `repository_dispatch` and the GitHub Actions bearer token.
- KV records expire automatically and are deleted immediately after a successful claim.
- The GitHub Actions workflow writes the auth URL only to `$RUNNER_TEMP/sfauth.txt`, masks it, logs in with Salesforce CLI, and deletes the temp file immediately.

## Local Tests

From the repository root:

```bash
npm run test:broker
```
