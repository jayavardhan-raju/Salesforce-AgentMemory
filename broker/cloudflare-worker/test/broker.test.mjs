import assert from "node:assert/strict";
import test from "node:test";

import { createHandler, isValidSalesforceAuthUrl } from "../src/index.mjs";

const VALID_AUTH_URL =
  "force://PlatformCLI::00Dxx0000000000!AQwAQExampleRefreshToken@login.salesforce.com";
const VALID_AUTH_URL_WITH_PROTOCOL =
  "force://PlatformCLI::00Dxx0000000000!AQwAQExampleRefreshToken@https://login.salesforce.com";

class MemoryKV {
  constructor() {
    this.records = new Map();
  }

  async put(key, value, options = {}) {
    this.records.set(key, { value, options });
  }

  async get(key) {
    return this.records.get(key)?.value || null;
  }

  async delete(key) {
    this.records.delete(key);
  }
}

function validLaunchBody(overrides = {}) {
  return {
    name: "Priya Shah",
    email: "priya@example.com",
    githubUsername: "priya-demo",
    forkUrl: "https://github.com/priya-demo/Salesforce-AgentMemory",
    salesforceAuthUrl: VALID_AUTH_URL,
    ...overrides,
  };
}

function createTestBroker({ ttlSeconds = "900", now = () => Date.now() } = {}) {
  const kv = new MemoryKV();
  const dispatches = [];
  const env = {
    AUTH_TOKENS: kv,
    GITHUB_TOKEN: "github-token",
    ACTIONS_BROKER_TOKEN: "actions-token",
    TTL_SECONDS: ttlSeconds,
    CORS_ORIGIN: "https://jayavardhan-raju.github.io",
  };

  const handler = createHandler(env, {}, {
    now,
    randomBytes(bytes) {
      bytes.fill(7);
      return bytes;
    },
    async fetch(url, init) {
      dispatches.push({ url, init, body: JSON.parse(init.body) });
      return new Response(null, { status: 204 });
    },
  });

  return { handler, kv, dispatches };
}

function post(path, body, headers = {}) {
  return new Request(`https://broker.example${path}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      origin: "https://jayavardhan-raju.github.io",
      ...headers,
    },
    body: JSON.stringify(body),
  });
}

test("accepts a valid auth URL and dispatches a live demo request", async () => {
  const { handler, kv, dispatches } = createTestBroker();

  const response = await handler.fetch(post("/launch", validLaunchBody()));
  const body = await response.json();

  assert.equal(response.status, 202);
  assert.equal(body.ok, true);
  assert.equal(body.scratch_org_mode, "create");
  assert.equal(body.scratch_org_duration_days, 30);
  assert.equal(kv.records.size, 1);
  assert.equal(dispatches.length, 1);
  assert.equal(dispatches[0].body.event_type, "live-demo-requested");
  assert.equal(dispatches[0].body.client_payload.email, "priya@example.com");
  assert.equal(dispatches[0].body.client_payload.scratch_org_mode, "create");
  assert.equal(dispatches[0].body.client_payload.scratch_org_duration_days, 30);
  assert.ok(dispatches[0].body.client_payload.claim_token);
  assert.equal(JSON.stringify(dispatches[0].body).includes(VALID_AUTH_URL), false);
});

test("dispatches requester-selected scratch org reuse mode", async () => {
  const { handler, dispatches } = createTestBroker();

  const response = await handler.fetch(
    post("/launch", validLaunchBody({ scratchOrgMode: "reuse" })),
  );
  const body = await response.json();

  assert.equal(response.status, 202);
  assert.equal(body.scratch_org_mode, "reuse");
  assert.equal(dispatches[0].body.client_payload.scratch_org_mode, "reuse");
});

test("dispatches requester-selected scratch org duration", async () => {
  const { handler, dispatches } = createTestBroker();

  const response = await handler.fetch(
    post("/launch", validLaunchBody({ scratchOrgDurationDays: 14 })),
  );
  const body = await response.json();

  assert.equal(response.status, 202);
  assert.equal(body.scratch_org_duration_days, 14);
  assert.equal(dispatches[0].body.client_payload.scratch_org_duration_days, 14);
});

test("rejects unsupported scratch org mode without dispatching", async () => {
  const { handler, kv, dispatches } = createTestBroker();

  const response = await handler.fetch(
    post("/launch", validLaunchBody({ scratchOrgMode: "keep" })),
  );
  const body = await response.json();

  assert.equal(response.status, 400);
  assert.deepEqual(body.fields, ["scratchOrgMode"]);
  assert.equal(kv.records.size, 0);
  assert.equal(dispatches.length, 0);
});

test("rejects unsupported scratch org duration without dispatching", async () => {
  const { handler, kv, dispatches } = createTestBroker();

  const response = await handler.fetch(
    post("/launch", validLaunchBody({ scratchOrgDurationDays: 31 })),
  );
  const body = await response.json();

  assert.equal(response.status, 400);
  assert.deepEqual(body.fields, ["scratchOrgDurationDays"]);
  assert.equal(kv.records.size, 0);
  assert.equal(dispatches.length, 0);
});

test("rejects an invalid Salesforce auth URL without dispatching", async () => {
  const { handler, kv, dispatches } = createTestBroker();

  const response = await handler.fetch(
    post("/launch", validLaunchBody({ salesforceAuthUrl: "https://login.salesforce.com" })),
  );
  const body = await response.json();

  assert.equal(response.status, 400);
  assert.deepEqual(body.fields, ["salesforceAuthUrl"]);
  assert.equal(kv.records.size, 0);
  assert.equal(dispatches.length, 0);
});

test("one-time claim returns the secret once and deletes it", async () => {
  const { handler, kv, dispatches } = createTestBroker();

  const launchResponse = await handler.fetch(post("/launch", validLaunchBody()));
  const launchBody = await launchResponse.json();
  const claimToken = dispatches[0].body.client_payload.claim_token;

  const claimResponse = await handler.fetch(
    post(
      "/claim",
      { request_id: launchBody.request_id, claim_token: claimToken },
      { authorization: "Bearer actions-token" },
    ),
  );
  const claimBody = await claimResponse.json();

  assert.equal(claimResponse.status, 200);
  assert.equal(claimBody.salesforce_auth_url, VALID_AUTH_URL);
  assert.equal(claimBody.scratch_org_mode, "create");
  assert.equal(claimBody.scratch_org_duration_days, 30);
  assert.equal(kv.records.size, 0);

  const secondClaim = await handler.fetch(
    post(
      "/claim",
      { request_id: launchBody.request_id, claim_token: claimToken },
      { authorization: "Bearer actions-token" },
    ),
  );

  assert.equal(secondClaim.status, 404);
});

test("expired claims are rejected and deleted", async () => {
  let currentTime = Date.parse("2026-06-02T12:00:00.000Z");
  const { handler, kv, dispatches } = createTestBroker({
    ttlSeconds: "1",
    now: () => currentTime,
  });

  const launchResponse = await handler.fetch(post("/launch", validLaunchBody()));
  const launchBody = await launchResponse.json();
  const claimToken = dispatches[0].body.client_payload.claim_token;
  currentTime += 2000;

  const claimResponse = await handler.fetch(
    post(
      "/claim",
      { request_id: launchBody.request_id, claim_token: claimToken },
      { authorization: "Bearer actions-token" },
    ),
  );
  const claimBody = await claimResponse.json();

  assert.equal(claimResponse.status, 410);
  assert.equal(claimBody.error, "expired");
  assert.equal(kv.records.size, 0);
});

test("Salesforce auth URL validation is strict enough for log-safe handling", () => {
  assert.equal(isValidSalesforceAuthUrl(VALID_AUTH_URL), true);
  assert.equal(isValidSalesforceAuthUrl(VALID_AUTH_URL_WITH_PROTOCOL), true);
  assert.equal(isValidSalesforceAuthUrl(`${VALID_AUTH_URL}\nSECRET=1`), false);
  assert.equal(isValidSalesforceAuthUrl("sfdx://not-supported"), false);
});
