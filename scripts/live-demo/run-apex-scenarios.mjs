import { parseArgs } from "node:util";

import { ensureDir, run, writeJsonFile } from "./lib.mjs";

// AgentMemory has no Agentforce Grid / Prompt Builder UI to automate, so the
// "execute once" step is: run the three anonymous Apex demo scenarios and the
// AgentMemoryServiceTest unit suite (with code coverage), then record an honest
// pass/fail + coverage summary for the requester email. This script never throws
// on a scenario or test failure; it captures the real outcome so the email
// reflects what actually happened in the requester org.

const { values } = parseArgs({
  options: {
    "target-org": { type: "string" },
    artifacts: { type: "string" },
  },
});

if (!values["target-org"] || !values.artifacts) {
  throw new Error("Usage: node run-apex-scenarios.mjs --target-org <alias> --artifacts <dir>");
}

const targetOrg = values["target-org"];
await ensureDir(values.artifacts);

const SCENARIOS = [
  { name: "TC1 — Sales Cloud: The Ghost Deal", file: "scripts/apex/TC1_SalesCloud_GhostDeal.apex" },
  { name: "TC2 — Service Cloud: The Compounding Signal", file: "scripts/apex/TC2_ServiceCloud_CompoundingSignal.apex" },
  { name: "TC3 — Marketing Cloud: The Silent Buyer", file: "scripts/apex/TC3_MarketingCloud_SilentBuyer.apex" },
];

const scenarios = [];
for (const scenario of SCENARIOS) {
  const outcome = await runAnonymousApex(scenario.file);
  scenarios.push({ name: scenario.name, file: scenario.file, ...outcome });
  console.log(`${outcome.status === "passed" ? "PASS" : "FAIL"}: ${scenario.name}${outcome.detail ? ` — ${outcome.detail}` : ""}`);
}

const tests = await runUnitTests();
console.log(
  `Apex tests: outcome=${tests.outcome} passing=${tests.passing}/${tests.testsRan} coverage=${tests.coverage_percent ?? "n/a"}%`,
);

const passed = scenarios.filter((scenario) => scenario.status === "passed").length;
const failed = scenarios.length - passed;

const results = {
  target_org: targetOrg,
  generated_at: new Date().toISOString(),
  passed,
  failed,
  scenarios,
  tests,
};

await writeJsonFile(`${values.artifacts}/scenario-results.json`, results);
console.log(`Scenario summary: ${passed} passed, ${failed} failed. Wrote scenario-results.json`);

async function runAnonymousApex(file) {
  const result = await run("sf", ["apex", "run", "--file", file, "--target-org", targetOrg, "--json"], {
    allowFailure: true,
  });

  const parsed = parseJson(result.stdout);
  const apex = parsed?.result || {};
  const compiled = apex.compiled !== false;
  const success = apex.success === true;

  if (compiled && success) {
    return { status: "passed", detail: "" };
  }

  const detail =
    apex.compileProblem ||
    apex.exceptionMessage ||
    (parsed?.message ? String(parsed.message) : "Anonymous Apex execution failed");

  return { status: "failed", detail: String(detail).slice(0, 500) };
}

async function runUnitTests() {
  const result = await run(
    "sf",
    [
      "apex",
      "run",
      "test",
      "--class-names",
      "AgentMemoryServiceTest",
      "--code-coverage",
      "--result-format",
      "json",
      "--wait",
      "20",
      "--target-org",
      targetOrg,
      "--json",
    ],
    { allowFailure: true },
  );

  const parsed = parseJson(result.stdout);
  const summary = parsed?.result?.summary || {};
  const coveragePercent = parseCoverage(summary.testRunCoverage ?? summary.orgWideCoverage);

  return {
    outcome: summary.outcome || (parsed?.result ? "Unknown" : "Failed"),
    testsRan: Number(summary.testsRan ?? 0),
    passing: Number(summary.passing ?? 0),
    failing: Number(summary.failing ?? 0),
    coverage_percent: coveragePercent,
    coverage_label: summary.testRunCoverage || summary.orgWideCoverage || null,
  };
}

function parseJson(stdout) {
  const text = stdout || "";
  const firstBrace = text.indexOf("{");
  if (firstBrace < 0) {
    return null;
  }
  try {
    return JSON.parse(text.slice(firstBrace));
  } catch {
    return null;
  }
}

function parseCoverage(value) {
  if (value === undefined || value === null) {
    return null;
  }
  const match = String(value).match(/[\d.]+/);
  return match ? Number(match[0]) : null;
}
