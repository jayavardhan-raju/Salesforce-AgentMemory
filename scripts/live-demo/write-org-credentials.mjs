import { parseArgs } from "node:util";

import { expirationDate, readJsonFile, sfJson, writeJsonFile } from "./lib.mjs";

const { values } = parseArgs({
  options: {
    "target-org": { type: "string" },
    "password-json": { type: "string" },
    credentials: { type: "string" },
    summary: { type: "string" },
    "duration-days": { type: "string", default: "30" },
  },
});

if (!values["target-org"] || !values["password-json"] || !values.credentials || !values.summary) {
  throw new Error(
    "Usage: node write-org-credentials.mjs --target-org <alias> --password-json <file> --credentials <runner-temp-file> --summary <artifact-file> --duration-days 30",
  );
}

const display = await sfJson(["org", "display", "--target-org", values["target-org"]]);
const passwordOutput = await readJsonFile(values["password-json"]);
const password = passwordOutput.result?.password || passwordOutput.result?.usernamePassword?.password;
const username = display.result?.username;
const instanceUrl = display.result?.instanceUrl;
const loginUrl = display.result?.loginUrl || instanceUrl;
const orgId = display.result?.id;
const expiresAt = process.env.SCRATCH_ORG_EXPIRATION_DATE || expirationDate(values["duration-days"]);

if (!username || !password || !loginUrl) {
  throw new Error("Unable to resolve scratch org login credentials from Salesforce CLI output");
}

const credentials = {
  username,
  password,
  login_url: loginUrl,
  instance_url: instanceUrl,
  org_id: orgId,
  expires_at: expiresAt,
  scratch_org_duration_days: Number(values["duration-days"]),
};

await writeJsonFile(values.credentials, credentials);
await writeJsonFile(values.summary, {
  username,
  login_url: loginUrl,
  instance_url: instanceUrl,
  org_id: orgId,
  expires_at: expiresAt,
  scratch_org_duration_days: Number(values["duration-days"]),
});

console.log(`Wrote redacted scratch org summary for ${username}`);
