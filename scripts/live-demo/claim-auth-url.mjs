import { readDispatchPayload } from "./lib.mjs";

const payload = await readDispatchPayload();
const claimUrl = process.env.DEMO_BROKER_CLAIM_URL;
const actionsToken = process.env.DEMO_BROKER_ACTIONS_TOKEN;

if (!claimUrl) {
  throw new Error("DEMO_BROKER_CLAIM_URL repository variable is required");
}

if (!actionsToken) {
  throw new Error("DEMO_BROKER_ACTIONS_TOKEN repository secret is required");
}

const response = await fetch(claimUrl, {
  method: "POST",
  headers: {
    authorization: `Bearer ${actionsToken}`,
    "content-type": "application/json",
  },
  body: JSON.stringify({
    request_id: payload.request_id,
    claim_token: payload.claim_token,
  }),
});

const body = await response.json();
if (!response.ok) {
  throw new Error(`Broker claim failed: ${body.error || response.status}`);
}

if (!body.salesforce_auth_url) {
  throw new Error("Broker claim response did not include a Salesforce auth URL");
}

process.stdout.write(body.salesforce_auth_url);
