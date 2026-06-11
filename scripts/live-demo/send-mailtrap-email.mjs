import { existsSync } from "node:fs";
import { basename } from "node:path";
import { parseArgs } from "node:util";

import nodemailer from "nodemailer";

import { githubRunUrl, readDispatchPayload, readJsonFile } from "./lib.mjs";

const REPO_URL = "https://github.com/jayavardhan-raju/Salesforce-AgentMemory";
const DOCS_URL = "https://jayavardhan-raju.github.io/Salesforce-AgentMemory/";

const { values } = parseArgs({
  options: {
    artifacts: { type: "string" },
    credentials: { type: "string" },
    status: { type: "string", default: "unknown" },
    "duration-days": { type: "string", default: "30" },
  },
});

if (!values.artifacts) {
  throw new Error("Usage: node send-mailtrap-email.mjs --artifacts <dir> --credentials <runner-temp-file> --status <status>");
}

// Send through Mailtrap SMTP with nodemailer (the mechanism proven to deliver),
// authenticating with the inbox/sending-stream SMTP username + password. The
// password also accepts the legacy MAILTRAP_TOKEN secret so existing setups keep
// working. Live delivery uses live.smtp.mailtrap.io; override host/port for sandbox.
const smtpUser = process.env.MAILTRAP_USER || "api";
const smtpPass = String(process.env.MAILTRAP_PASS || process.env.MAILTRAP_TOKEN || process.env.MAILTRAP_API_TOKEN || "")
  .trim()
  .replace(/^Bearer\s+/i, "")
  .trim();
if (!smtpPass) {
  console.warn("MAILTRAP_PASS is not configured; skipping email send");
  process.exit(0);
}
const smtpHost = process.env.MAILTRAP_HOST || "live.smtp.mailtrap.io";
const smtpPort = Number(process.env.MAILTRAP_PORT || 587);

const payload = await readDispatchPayload();
const credentials = values.credentials && existsSync(values.credentials)
  ? await readJsonFile(values.credentials)
  : null;
const scenarioResults = existsSync(`${values.artifacts}/scenario-results.json`)
  ? await readJsonFile(`${values.artifacts}/scenario-results.json`)
  : null;
const scratchSelection = existsSync(`${values.artifacts}/scratch-org-selection.json`)
  ? await readJsonFile(`${values.artifacts}/scratch-org-selection.json`)
  : null;
const uiResults = existsSync(`${values.artifacts}/ui-scenario-results.json`)
  ? await readJsonFile(`${values.artifacts}/ui-scenario-results.json`)
  : null;
const recordLinks = (uiResults?.record_links || []).filter((link) => link.url);

const runUrl = githubRunUrl();
const artifactUrl = process.env.ARTIFACT_URL || runUrl;
const status = String(values.status || "unknown").toLowerCase();
const success = status === "success" && credentials;
const subject = success
  ? "Salesforce AgentMemory demo org is ready"
  : "Salesforce AgentMemory demo setup needs attention";

const hasGif = existsSync(`${values.artifacts}/agentmemory-demo.gif`);

const context = {
  payload,
  credentials,
  scenarioResults,
  scratchSelection,
  recordLinks,
  runUrl,
  artifactUrl,
  success,
  hasGif,
  durationDays: values["duration-days"],
};
const text = buildText(context);
const html = buildHtml(context);
const attachments = await buildAttachments(values.artifacts);

const fromEmail = process.env.MAILTRAP_FROM_EMAIL || "demo@salesforce-agentmemory.example";
const fromName = process.env.MAILTRAP_FROM_NAME || "Salesforce AgentMemory Demo";

const transporter = nodemailer.createTransport({
  host: smtpHost,
  port: smtpPort,
  secure: smtpPort === 465,
  auth: { user: smtpUser, pass: smtpPass },
});

try {
  await transporter.verify();
  console.log(`Connected to Mailtrap SMTP ${smtpHost}:${smtpPort} as ${smtpUser}`);
  const info = await transporter.sendMail({
    from: { name: fromName, address: fromEmail },
    to: { name: payload.name, address: payload.email },
    subject,
    text,
    html,
    attachments,
  });
  console.log(`Mailtrap email sent to ${payload.email}: messageId=${info.messageId} response=${info.response}`);
  if (info.rejected && info.rejected.length) {
    console.warn(`Mailtrap rejected recipients: ${info.rejected.join(", ")}`);
  }
} catch (error) {
  throw new Error(
    `Mailtrap SMTP send failed via ${smtpHost}:${smtpPort} (user=${smtpUser}, from=${fromEmail}): ${
      error?.message || error
    }${error?.response ? ` | server: ${error.response}` : ""}`,
  );
}

function testsSummaryLine(tests) {
  if (!tests) {
    return "";
  }
  const coverage = tests.coverage_percent != null ? `${tests.coverage_percent}% coverage` : "coverage unavailable";
  return `Apex unit tests: ${tests.outcome}, ${tests.passing}/${tests.testsRan} passing, ${coverage}.`;
}

function buildText({
  payload,
  credentials,
  scenarioResults,
  scratchSelection,
  recordLinks,
  runUrl,
  artifactUrl,
  success,
  hasGif,
  durationDays,
}) {
  const lines = [
    `Hi ${payload.name},`,
    "",
    success
      ? `Your Salesforce AgentMemory ${durationDays}-day scratch org is ready. It expires on ${credentials.expires_at}.`
      : "The live demo run did not complete successfully. Setup evidence was uploaded so the failure can be inspected honestly.",
    "",
  ];

  if (credentials) {
    lines.push(
      "Scratch org credentials:",
      `Login URL: ${credentials.login_url}`,
      `Username: ${credentials.username}`,
      `Password: ${credentials.password}`,
      `Expiration: ${credentials.expires_at}`,
      "",
    );
  }

  if (scenarioResults) {
    lines.push(
      `Demo scenarios: ${scenarioResults.passed || 0} passed, ${scenarioResults.failed || 0} failed.`,
    );
    for (const scenario of scenarioResults.scenarios || []) {
      lines.push(`  - ${scenario.status === "passed" ? "PASS" : "FAIL"} ${scenario.name}${scenario.detail ? ` (${scenario.detail})` : ""}`);
    }
    const testsLine = testsSummaryLine(scenarioResults.tests);
    if (testsLine) {
      lines.push(testsLine);
    }
    lines.push("");
  }

  if (scratchSelection) {
    lines.push(
      `Scratch org mode: requested ${scratchSelection.requested_mode}, ${scratchSelection.effective_mode}.`,
      scratchSelection.fallback_reason ? `Fallback reason: ${scratchSelection.fallback_reason}` : "",
      "",
    );
  }

  if (recordLinks && recordLinks.length > 0) {
    lines.push("Demo records (log in first, then open these to see the Agent Memory dashboard):");
    for (const link of recordLinks) {
      lines.push(`  - ${link.object} — ${link.name}: ${link.url}`);
    }
    lines.push("");
  }

  if (hasGif) {
    lines.push(
      "A short GIF walkthrough of the dashboard scenarios (open record, view suggestions, accept) is attached: agentmemory-demo.gif.",
      "",
    );
  }

  lines.push(
    "Next steps: log in, then assign the permission set and open an Account record with the AgentMemory dashboard.",
    `Artifacts: ${artifactUrl}`,
    `Run log: ${runUrl}`,
    `Repository: ${REPO_URL}`,
    `Documentation: ${DOCS_URL}`,
    "",
    `Scratch org duration is fixed at ${durationDays} days. Your Salesforce Dev Hub auth URL is not included in this email, logs, or artifacts.`,
  );

  return lines.join("\n");
}

function buildHtml({
  payload,
  credentials,
  scenarioResults,
  scratchSelection,
  recordLinks,
  runUrl,
  artifactUrl,
  success,
  hasGif,
  durationDays,
}) {
  const credentialRows = credentials
    ? `
      <h2>Scratch Org Credentials</h2>
      <table>
        <tr><th align="left">Login URL</th><td><a href="${escapeHtml(credentials.login_url)}">${escapeHtml(credentials.login_url)}</a></td></tr>
        <tr><th align="left">Username</th><td>${escapeHtml(credentials.username)}</td></tr>
        <tr><th align="left">Password</th><td><code>${escapeHtml(credentials.password)}</code></td></tr>
        <tr><th align="left">Expiration</th><td>${escapeHtml(credentials.expires_at)}</td></tr>
      </table>`
    : "";

  let scenarios = "";
  if (scenarioResults) {
    const rows = (scenarioResults.scenarios || [])
      .map(
        (scenario) =>
          `<li><strong>${scenario.status === "passed" ? "PASS" : "FAIL"}</strong> — ${escapeHtml(scenario.name)}${
            scenario.detail ? ` <em>(${escapeHtml(scenario.detail)})</em>` : ""
          }</li>`,
      )
      .join("");
    const testsLine = testsSummaryLine(scenarioResults.tests);
    scenarios = `
      <h2>Demo Execution</h2>
      <p><strong>Scenario summary:</strong> ${scenarioResults.passed || 0} passed, ${scenarioResults.failed || 0} failed.</p>
      <ul>${rows}</ul>
      ${testsLine ? `<p><strong>${escapeHtml(testsLine)}</strong></p>` : ""}`;
  }

  const scratchMode = scratchSelection
    ? `<p><strong>Scratch org mode:</strong> requested ${escapeHtml(scratchSelection.requested_mode)}, ${escapeHtml(scratchSelection.effective_mode)}.${
        scratchSelection.fallback_reason ? ` ${escapeHtml(scratchSelection.fallback_reason)}` : ""
      }</p>`
    : "";

  const demoRecords =
    recordLinks && recordLinks.length > 0
      ? `
      <h2>Demo Records</h2>
      <p>Log in first, then open any record below to see the Agent Memory dashboard (top of the right sidebar):</p>
      <ul>${recordLinks
        .map(
          (link) =>
            `<li>${escapeHtml(link.object)} — <a href="${escapeHtml(link.url)}">${escapeHtml(link.name)}</a></li>`,
        )
        .join("")}</ul>`
      : "";

  return `
    <p>Hi ${escapeHtml(payload.name)},</p>
    <p>${
      success
        ? `Your Salesforce AgentMemory ${escapeHtml(durationDays)}-day scratch org is ready. It expires on ${escapeHtml(credentials.expires_at)}.`
        : "The live demo run did not complete successfully. Setup evidence was uploaded so the failure can be inspected honestly."
    }</p>
    ${credentialRows}
    ${scenarios}
    ${demoRecords}
    ${scratchMode}
    ${hasGif ? "<p>A short <strong>GIF walkthrough</strong> of the dashboard scenarios (open record, view suggestions, accept) is attached as <code>agentmemory-demo.gif</code>.</p>" : ""}
    <p><a href="${escapeHtml(artifactUrl)}">Open the uploaded artifacts</a></p>
    <p><a href="${escapeHtml(runUrl)}">Open the GitHub Actions run log</a></p>
    <p>
      <a href="${REPO_URL}">Repository</a> |
      <a href="${DOCS_URL}">Documentation</a>
    </p>
    <p>Scratch org duration is fixed at ${escapeHtml(durationDays)} days. The Salesforce Dev Hub auth URL is not included in this email, logs, or artifacts.</p>
  `;
}

async function buildAttachments(artifactDir) {
  const attachments = [];

  const gifPath = `${artifactDir}/agentmemory-demo.gif`;
  if (existsSync(gifPath)) {
    attachments.push({
      filename: basename(gifPath),
      path: gifPath,
      contentType: "image/gif",
    });
  }

  const resultsPath = `${artifactDir}/scenario-results.json`;
  if (existsSync(resultsPath)) {
    attachments.push({
      filename: basename(resultsPath),
      path: resultsPath,
      contentType: "application/json",
    });
  }

  return attachments;
}

function escapeHtml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}
