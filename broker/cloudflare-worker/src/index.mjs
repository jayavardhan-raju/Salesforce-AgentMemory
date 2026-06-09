const DEFAULT_TTL_SECONDS = 15 * 60;
const DEFAULT_SCRATCH_ORG_DURATION_DAYS = 30;
const ALLOWED_SCRATCH_ORG_DURATION_DAYS = new Set([7, 14, 21, 30]);
const DEFAULT_SCRATCH_ORG_MODE = "create";
const ALLOWED_SCRATCH_ORG_MODES = new Set(["create", "reuse"]);
const DEFAULT_OWNER = "jayavardhan-raju";
const DEFAULT_REPO = "Salesforce-AgentMemory";

const JSON_HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};

export default {
  async fetch(request, env, ctx) {
    return createHandler(env, ctx).fetch(request);
  },
};

export function createHandler(env, ctx = {}, options = {}) {
  const now = options.now || (() => Date.now());
  const fetchImpl = options.fetch || fetch;
  const randomBytes = options.randomBytes || crypto.getRandomValues.bind(crypto);

  return {
    async fetch(request) {
      const url = new URL(request.url);

      if (request.method === "OPTIONS") {
        return emptyResponse(204, env, request);
      }

      try {
        if (request.method === "GET" && url.pathname === "/health") {
          return jsonResponse({ ok: true }, 200, env, request);
        }

        if (request.method === "POST" && url.pathname === "/launch") {
          return await launch(request, env, { now, fetchImpl, randomBytes });
        }

        if (request.method === "POST" && url.pathname === "/claim") {
          return await claim(request, env, { now });
        }

        return jsonResponse({ error: "not_found" }, 404, env, request);
      } catch (error) {
        return jsonResponse(
          { error: "broker_error", message: error.message },
          500,
          env,
          request,
        );
      }
    },
  };
}

async function launch(request, env, runtime) {
  assertEnv(env, ["AUTH_TOKENS", "GITHUB_TOKEN"]);
  const body = await readJson(request);
  const payload = normalizeLaunchPayload(body);
  const validation = validateLaunchPayload(payload);

  if (validation.length > 0) {
    return jsonResponse({ error: "invalid_request", fields: validation }, 400, env, request);
  }

  const requestId = crypto.randomUUID();
  const claimToken = toBase64Url(randomBytes(runtime.randomBytes, 32));
  const claimTokenHash = await sha256(claimToken);
  const ttlSeconds = Number(env.TTL_SECONDS || DEFAULT_TTL_SECONDS);
  const createdAt = new Date(runtime.now()).toISOString();
  const expiresAt = new Date(runtime.now() + ttlSeconds * 1000).toISOString();

  const record = {
    requestId,
    claimTokenHash,
    createdAt,
    expiresAt,
    requester: {
      name: payload.name,
      email: payload.email,
      githubUsername: payload.githubUsername,
      forkUrl: payload.forkUrl,
      scratchOrgMode: payload.scratchOrgMode,
      scratchOrgDurationDays: payload.scratchOrgDurationDays,
    },
    salesforceAuthUrl: payload.salesforceAuthUrl,
  };

  await env.AUTH_TOKENS.put(kvKey(requestId), JSON.stringify(record), {
    expirationTtl: ttlSeconds,
  });

  const dispatchResult = await dispatchGitHub(runtime.fetchImpl, env, {
    request_id: requestId,
    claim_token: claimToken,
    name: payload.name,
    email: payload.email,
    github_username: payload.githubUsername,
    fork_url: payload.forkUrl,
    scratch_org_mode: payload.scratchOrgMode,
    expires_at: expiresAt,
    scratch_org_duration_days: payload.scratchOrgDurationDays,
  });

  if (!dispatchResult.ok) {
    await env.AUTH_TOKENS.delete(kvKey(requestId));
    return jsonResponse(
      {
        error: "dispatch_failed",
        status: dispatchResult.status,
        message: dispatchResult.message,
      },
      502,
      env,
      request,
    );
  }

  return jsonResponse(
    {
      ok: true,
      request_id: requestId,
      expires_at: expiresAt,
      scratch_org_mode: payload.scratchOrgMode,
      scratch_org_duration_days: payload.scratchOrgDurationDays,
    },
    202,
    env,
    request,
  );
}

async function claim(request, env, runtime) {
  assertEnv(env, ["AUTH_TOKENS", "ACTIONS_BROKER_TOKEN"]);

  const expected = `Bearer ${env.ACTIONS_BROKER_TOKEN}`;
  if (request.headers.get("authorization") !== expected) {
    return jsonResponse({ error: "unauthorized" }, 401, env, request);
  }

  const body = await readJson(request);
  const requestId = String(body.request_id || "").trim();
  const claimToken = String(body.claim_token || "").trim();

  if (!requestId || !claimToken) {
    return jsonResponse({ error: "invalid_request" }, 400, env, request);
  }

  const key = kvKey(requestId);
  const raw = await env.AUTH_TOKENS.get(key);
  if (!raw) {
    return jsonResponse({ error: "not_found_or_claimed" }, 404, env, request);
  }

  const record = JSON.parse(raw);
  if (Date.parse(record.expiresAt) <= runtime.now()) {
    await env.AUTH_TOKENS.delete(key);
    return jsonResponse({ error: "expired" }, 410, env, request);
  }

  const actualHash = await sha256(claimToken);
  if (!constantTimeEqual(actualHash, record.claimTokenHash)) {
    return jsonResponse({ error: "not_found_or_claimed" }, 404, env, request);
  }

  await env.AUTH_TOKENS.delete(key);

  return jsonResponse(
    {
      ok: true,
      request_id: requestId,
      salesforce_auth_url: record.salesforceAuthUrl,
      requester: record.requester,
      expires_at: record.expiresAt,
      scratch_org_mode: record.requester?.scratchOrgMode || DEFAULT_SCRATCH_ORG_MODE,
      scratch_org_duration_days:
        record.requester?.scratchOrgDurationDays || DEFAULT_SCRATCH_ORG_DURATION_DAYS,
    },
    200,
    env,
    request,
  );
}

function normalizeLaunchPayload(body) {
  return {
    name: String(body.name || "").trim(),
    email: String(body.email || "").trim().toLowerCase(),
    githubUsername: String(body.githubUsername || body.github_username || "").trim(),
    forkUrl: String(body.forkUrl || body.fork_url || "").trim(),
    scratchOrgMode: normalizeScratchOrgMode(body.scratchOrgMode || body.scratch_org_mode),
    scratchOrgDurationDays: normalizeScratchOrgDuration(
      body.scratchOrgDurationDays || body.scratch_org_duration_days,
    ),
    salesforceAuthUrl: String(
      body.salesforceAuthUrl || body.salesforce_auth_url || "",
    ).trim(),
  };
}

function validateLaunchPayload(payload) {
  const fields = [];

  if (!payload.name || payload.name.length > 120) {
    fields.push("name");
  }

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(payload.email)) {
    fields.push("email");
  }

  if (!/^[A-Za-z0-9-]{1,39}$/.test(payload.githubUsername)) {
    fields.push("githubUsername");
  }

  if (!isValidGitHubRepoUrl(payload.forkUrl)) {
    fields.push("forkUrl");
  }

  if (!ALLOWED_SCRATCH_ORG_MODES.has(payload.scratchOrgMode)) {
    fields.push("scratchOrgMode");
  }

  if (!ALLOWED_SCRATCH_ORG_DURATION_DAYS.has(payload.scratchOrgDurationDays)) {
    fields.push("scratchOrgDurationDays");
  }

  if (!isValidSalesforceAuthUrl(payload.salesforceAuthUrl)) {
    fields.push("salesforceAuthUrl");
  }

  return fields;
}

function normalizeScratchOrgMode(value) {
  const mode = String(value || DEFAULT_SCRATCH_ORG_MODE).trim().toLowerCase();
  return mode || DEFAULT_SCRATCH_ORG_MODE;
}

function normalizeScratchOrgDuration(value) {
  if (value === undefined || value === null || value === "") {
    return DEFAULT_SCRATCH_ORG_DURATION_DAYS;
  }

  return Number(value);
}

export function isValidSalesforceAuthUrl(value) {
  if (!value || value.length > 20000 || /[\r\n\t]/.test(value)) {
    return false;
  }

  return /^force:\/\/[^@\s]+@(?:https:\/\/)?[A-Za-z0-9.-]+(?:\/[^\s]*)?$/.test(value);
}

function isValidGitHubRepoUrl(value) {
  try {
    const parsed = new URL(value);
    if (parsed.hostname.toLowerCase() !== "github.com") {
      return false;
    }

    const parts = parsed.pathname.split("/").filter(Boolean);
    return parts.length >= 2 && /^[A-Za-z0-9_.-]+$/.test(parts[0]) && /^[A-Za-z0-9_.-]+$/.test(parts[1]);
  } catch {
    return false;
  }
}

async function dispatchGitHub(fetchImpl, env, payload) {
  const owner = env.GITHUB_OWNER || DEFAULT_OWNER;
  const repo = env.GITHUB_REPO || DEFAULT_REPO;
  const response = await fetchImpl(`https://api.github.com/repos/${owner}/${repo}/dispatches`, {
    method: "POST",
    headers: {
      accept: "application/vnd.github+json",
      authorization: `Bearer ${env.GITHUB_TOKEN}`,
      "content-type": "application/json",
      "user-agent": "salesforce-agentmemory-auth-broker",
      "x-github-api-version": "2022-11-28",
    },
    body: JSON.stringify({
      event_type: "live-demo-requested",
      client_payload: payload,
    }),
  });

  if (response.ok) {
    return { ok: true };
  }

  const message = await response.text();
  return { ok: false, status: response.status, message };
}

function corsHeaders(env, request) {
  const origin = request.headers.get("origin");
  const allowedOrigin = env.CORS_ORIGIN || "https://jayavardhan-raju.github.io";

  return {
    "access-control-allow-origin": origin === allowedOrigin ? origin : allowedOrigin,
    "access-control-allow-methods": "POST, GET, OPTIONS",
    "access-control-allow-headers": "content-type, authorization",
    "access-control-max-age": "600",
    vary: "Origin",
  };
}

function jsonResponse(body, status, env, request) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...JSON_HEADERS,
      ...corsHeaders(env, request),
    },
  });
}

function emptyResponse(status, env, request) {
  return new Response(null, {
    status,
    headers: corsHeaders(env, request),
  });
}

async function readJson(request) {
  const contentType = request.headers.get("content-type") || "";
  if (!contentType.includes("application/json")) {
    throw new Error("Expected application/json");
  }

  return await request.json();
}

function assertEnv(env, names) {
  const missing = names.filter((name) => !env[name]);
  if (missing.length > 0) {
    throw new Error(`Missing broker configuration: ${missing.join(", ")}`);
  }
}

function kvKey(requestId) {
  return `live-demo:${requestId}`;
}

function randomBytes(getRandomValues, length) {
  const bytes = new Uint8Array(length);
  getRandomValues(bytes);
  return bytes;
}

function toBase64Url(bytes) {
  let value = "";
  for (const byte of bytes) {
    value += String.fromCharCode(byte);
  }

  return btoa(value).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function sha256(value) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function constantTimeEqual(a, b) {
  if (a.length !== b.length) {
    return false;
  }

  let diff = 0;
  for (let i = 0; i < a.length; i += 1) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }

  return diff === 0;
}
