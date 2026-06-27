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

// Always bound the broker call with a timeout. Node's fetch (undici) uses
// unref'd sockets, so a stalled top-level `await fetch()` can let the event loop
// drain with the await still pending -> Node exits 13 ("unsettled top-level
// await"). An explicit AbortSignal guarantees this promise settles, turning a
// silent exit-13/hang into a clear, diagnosable error.
let response;
try {
  response = await fetch(claimUrl, {
    method: "POST",
    headers: {
      authorization: `Bearer ${actionsToken}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      request_id: payload.request_id,
      claim_token: payload.claim_token,
    }),
    signal: AbortSignal.timeout(30000),
  });
} catch (error) {
  const reason = error?.name === "TimeoutError" ? "timed out after 30s" : "network error";
  throw new Error(`Broker claim request to ${claimUrl} failed (${reason}): ${error?.message || error}`);
}

const body = await response.json();
if (!response.ok) {
  throw new Error(`Broker claim failed: ${body.error || response.status}`);
}

if (!body.salesforce_auth_url) {
  throw new Error("Broker claim response did not include a Salesforce auth URL");
}

process.stdout.write(body.salesforce_auth_url);
