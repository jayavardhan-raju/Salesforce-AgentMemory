import { parseArgs } from "node:util";
import { appendFile } from "node:fs/promises";

import { ensureDir, readDispatchPayload, run, sfJson, writeJsonFile } from "./lib.mjs";

const { values } = parseArgs({
  options: {
    "target-dev-hub": { type: "string" },
    alias: { type: "string" },
    "duration-days": { type: "string", default: "30" },
    "definition-file": { type: "string" },
    artifacts: { type: "string" },
  },
});

if (!values["target-dev-hub"] || !values.alias || !values["definition-file"] || !values.artifacts) {
  throw new Error(
    "Usage: node select-scratch-org.mjs --target-dev-hub <alias> --alias <scratch-alias> --duration-days <days> --definition-file <path> --artifacts <dir>",
  );
}

const payload = await readDispatchPayload();
const requestedMode = String(payload.scratch_org_mode || "create").toLowerCase();
const durationDays = Number(values["duration-days"]);
const selection = {
  requested_mode: requestedMode,
  effective_mode: "created",
  target_alias: values.alias,
  target_dev_hub: values["target-dev-hub"],
  duration_days: durationDays,
  candidate: null,
  fallback_reason: null,
};

await ensureDir(values.artifacts);

if (requestedMode === "reuse") {
  const candidate = await findReusableScratchOrg(values["target-dev-hub"]);
  selection.candidate = candidate;

  if (candidate) {
    const authCheck = await run("sf", ["org", "display", "--target-org", candidate.SignupUsername, "--json"], {
      allowFailure: true,
    });

    if (authCheck.code === undefined || authCheck.code === 0) {
      await run("sf", ["alias", "set", `${values.alias}=${candidate.SignupUsername}`]);
      selection.effective_mode = "reused";
      selection.username = candidate.SignupUsername;
      selection.expiration_date = candidate.ExpirationDate;
      await exportGitHubEnv({
        SCRATCH_ORG_EFFECTIVE_MODE: "reused",
        SCRATCH_ORG_USERNAME: candidate.SignupUsername,
        SCRATCH_ORG_EXPIRATION_DATE: candidate.ExpirationDate,
      });
      await writeSelection(selection);
      console.log(`Reusing authenticated scratch org ${candidate.SignupUsername}`);
      process.exit(0);
    }

    selection.fallback_reason =
      "Found an active future-dated scratch org, but the GitHub runner does not have local auth for it. A Dev Hub auth URL can query ScratchOrgInfo but cannot mint a CLI auth session for an existing scratch org.";
  } else {
    selection.fallback_reason = "No active future-dated scratch org was found in the requester Dev Hub.";
  }
}

const createOutput = await sfJson([
  "org",
  "create",
  "scratch",
  "--definition-file",
  values["definition-file"],
  "--alias",
  values.alias,
  "--duration-days",
  String(durationDays),
  "--target-dev-hub",
  values["target-dev-hub"],
  "--set-default",
]);

selection.effective_mode = "created";
selection.create_result = createOutput.result || createOutput;
selection.username = selection.create_result?.username;
await exportGitHubEnv({
  SCRATCH_ORG_EFFECTIVE_MODE: "created",
  SCRATCH_ORG_USERNAME: selection.username || "",
  SCRATCH_ORG_EXPIRATION_DATE: "",
});
await writeSelection(selection);
console.log(`Created scratch org ${selection.username || values.alias}`);

async function findReusableScratchOrg(targetDevHub) {
  const output = await sfJson([
    "data",
    "query",
    "--target-org",
    targetDevHub,
    "--query",
    "SELECT Id, SignupUsername, Status, ExpirationDate, CreatedDate FROM ScratchOrgInfo WHERE Status = 'Active' AND ExpirationDate > TODAY ORDER BY ExpirationDate DESC, CreatedDate DESC LIMIT 1",
  ]);

  return output.result?.records?.[0] || null;
}

async function writeSelection(value) {
  await writeJsonFile(`${values.artifacts}/scratch-org-selection.json`, value);
}

async function exportGitHubEnv(envValues) {
  if (!process.env.GITHUB_ENV) {
    return;
  }

  const lines = Object.entries(envValues).map(([key, value]) => `${key}=${value ?? ""}`);
  await appendFile(process.env.GITHUB_ENV, `${lines.join("\n")}\n`, "utf8");
}
