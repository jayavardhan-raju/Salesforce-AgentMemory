import { parseArgs } from "node:util";

import { ensureDir, getOrgOpenUrl, querySalesforce, sfJson, writeJsonFile } from "./lib.mjs";

// AgentMemory's UI demo is the Agent Memory dashboard LWC on a record page.
// The TC1-TC3 Apex scenarios seed Accounts/Contacts that carry pending
// cross-cloud suggestions. This script drives the real Lightning UI with
// Playwright: open each seeded record, screenshot the dashboard, accept the top
// suggestion (the "manual step"), then capture the updated state + action
// history. Screenshots feed create-gif.mjs. It is best-effort and never throws,
// so a missing page or selector change cannot block the GIF or the email.

const APP_API_NAME = "c__AgentMemory_Demo";

const { values } = parseArgs({
  options: {
    "target-org": { type: "string" },
    artifacts: { type: "string" },
  },
});

if (!values["target-org"] || !values.artifacts) {
  throw new Error("Usage: node run-salesforce-ui-scenarios.mjs --target-org <alias> --artifacts <dir>");
}

const targetOrg = values["target-org"];
const artifactDir = values.artifacts;
await ensureDir(`${artifactDir}/screenshots`);

const instanceUrl = await getInstanceUrl(targetOrg);

let entities = [];
try {
  entities = await discoverEntities(targetOrg);
} catch (error) {
  console.warn(`Could not query AgentMemory suggestions: ${error.message}`);
}

if (entities.length === 0) {
  console.log("No pending AgentMemory suggestions found; skipping UI walkthrough.");
  await writeResults([]);
  process.exit(0);
}

const { chromium } = await import("playwright");
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
const results = [];

try {
  for (const [index, entity] of entities.entries()) {
    results.push(await runScenario(page, entity, index + 1));
  }
} finally {
  await browser.close();
}

await writeResults(results);

const passed = results.filter((result) => result.status === "passed").length;
console.log(`UI walkthrough: ${passed}/${results.length} record(s) captured successfully.`);

// Intentionally exit 0: the workflow step is best-effort. Whatever screenshots
// were captured are stitched into the GIF and the email is still sent.

async function discoverEntities(org) {
  const rows = await querySalesforce(
    org,
    "SELECT Entity_Id__c, Confidence_Score__c FROM Agent_Suggestion__c " +
      "WHERE Status__c = 'Pending' AND Entity_Id__c != null ORDER BY Confidence_Score__c DESC",
  );

  const seen = new Set();
  const discovered = [];
  for (const row of rows) {
    const id = row.Entity_Id__c;
    if (!id || seen.has(id)) {
      continue;
    }
    seen.add(id);
    discovered.push({ id, object: objectFromId(id) });
  }

  for (const entity of discovered) {
    entity.name = await resolveName(org, entity);
    entity.record_url = recordUrl(entity);
  }

  return discovered;
}

async function getInstanceUrl(org) {
  try {
    const output = await sfJson(["org", "display", "--target-org", org, "--json"]);
    return output.result?.instanceUrl || "";
  } catch {
    return "";
  }
}

function recordUrl(entity) {
  // App-scoped URL so the requester lands on the AgentMemory Demo app, where the
  // action override makes the dashboard the active record page.
  if (!instanceUrl) {
    return "";
  }
  return `${instanceUrl}/lightning/app/${APP_API_NAME}/r/${entity.object}/${entity.id}/view`;
}

function objectFromId(id) {
  const prefix = String(id).slice(0, 3);
  if (prefix === "003") return "Contact";
  if (prefix === "00Q") return "Lead";
  if (prefix === "006") return "Opportunity";
  return "Account";
}

async function resolveName(org, entity) {
  try {
    const rows = await querySalesforce(
      org,
      `SELECT Name FROM ${entity.object} WHERE Id = '${entity.id}' LIMIT 1`,
    );
    return rows[0]?.Name || entity.id;
  } catch {
    return entity.id;
  }
}

async function runScenario(page, entity, position) {
  const prefix = String(position).padStart(2, "0");
  const result = {
    position,
    entity_id: entity.id,
    object: entity.object,
    name: entity.name,
    record_url: entity.record_url || "",
    status: "failed",
    accepted: false,
    screenshots: [],
  };

  try {
    const dashboardFound = await openRecord(page, entity);
    result.dashboard_rendered = dashboardFound;
    // Full record page for context (dashboard sits in the right sidebar, top).
    await screenshot(page, result, `${prefix}-01-${slug(entity.name)}-record.png`);
    // Close-up of the dashboard so it reads clearly in the GIF.
    await screenshotDashboard(page, result, `${prefix}-02-${slug(entity.name)}-dashboard.png`);

    // The manual step: accept the highest-confidence suggestion.
    const accept = page.getByRole("button", { name: "Accept", exact: true }).first();
    if (await accept.count()) {
      await accept.click({ timeout: 15000 }).catch(() => {});
      await page.waitForTimeout(6000);
      result.accepted = true;
      await screenshotDashboard(page, result, `${prefix}-03-${slug(entity.name)}-after-accept.png`);
    }

    // Reveal the action history for a richer final frame.
    const history = page.getByRole("button", { name: /action history/i }).first();
    if (await history.count()) {
      await history.click({ timeout: 10000 }).catch(() => {});
      await page.waitForTimeout(2500);
      await screenshotDashboard(page, result, `${prefix}-04-${slug(entity.name)}-history.png`);
    }

    result.status = result.screenshots.length > 0 ? "passed" : "failed";
  } catch (error) {
    result.error = error.message;
    await screenshot(page, result, `${prefix}-09-${slug(entity.name)}-error.png`).catch(() => {});
  }

  console.log(
    `${result.status === "passed" ? "PASS" : "FAIL"}: ${entity.object} ${entity.name}` +
      `${result.error ? ` — ${result.error}` : ""}`,
  );
  return result;
}

async function openRecord(page, entity) {
  // Prefer the AgentMemory Demo app (its action override makes the dashboard the
  // active record page); fall back to the plain record URL (org default page).
  const candidates = [
    `/lightning/app/${APP_API_NAME}/r/${entity.object}/${entity.id}/view`,
    `/lightning/r/${entity.object}/${entity.id}/view`,
  ];

  for (const path of candidates) {
    const url = await getOrgOpenUrl(targetOrg, path);
    await page.goto(url, { waitUntil: "domcontentloaded", timeout: 120000 });
    await page.waitForTimeout(5000);
    // Playwright CSS selectors pierce open shadow roots, so the custom element
    // resolves even inside Lightning's shadow DOM.
    const found = await page.locator("c-agent-memory-dashboard").count().catch(() => 0);
    if (found > 0) {
      await page.waitForTimeout(2000);
      return true;
    }
  }

  return false;
}

async function screenshot(page, result, fileName) {
  const path = `${artifactDir}/screenshots/${fileName}`;
  await page.screenshot({ path, fullPage: true });
  result.screenshots.push(path);
}

async function screenshotDashboard(page, result, fileName) {
  const path = `${artifactDir}/screenshots/${fileName}`;
  const dashboard = page.locator("c-agent-memory-dashboard").first();
  try {
    if (await dashboard.count()) {
      await dashboard.scrollIntoViewIfNeeded({ timeout: 5000 }).catch(() => {});
      await page.waitForTimeout(800);
      await dashboard.screenshot({ path });
      result.screenshots.push(path);
      return;
    }
  } catch {
    // Fall through to a full-page capture if the element screenshot fails.
  }
  await page.screenshot({ path, fullPage: true });
  result.screenshots.push(path);
}

function slug(value) {
  return (
    String(value)
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 40) || "record"
  );
}

async function writeResults(scenarios) {
  const passed = scenarios.filter((scenario) => scenario.status === "passed").length;
  await writeJsonFile(`${artifactDir}/ui-scenario-results.json`, {
    target_org: targetOrg,
    generated_at: new Date().toISOString(),
    instance_url: instanceUrl,
    passed,
    failed: scenarios.length - passed,
    record_links: entities.map((entity) => ({
      object: entity.object,
      name: entity.name,
      id: entity.id,
      url: entity.record_url || "",
    })),
    scenarios,
  });
}
