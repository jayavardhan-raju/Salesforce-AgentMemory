import { execFile } from "node:child_process";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

export const SOURCE_REPO = process.env.SOURCE_REPO || "jayavardhan-raju/Salesforce-AgentMemory";

export async function readJsonFile(path) {
  return JSON.parse(await readFile(path, "utf8"));
}

export async function writeJsonFile(path, value) {
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

export async function ensureDir(path) {
  await mkdir(path, { recursive: true });
}

export async function readDispatchPayload() {
  const eventPath = process.env.GITHUB_EVENT_PATH;
  if (!eventPath) {
    throw new Error("GITHUB_EVENT_PATH is required");
  }

  const event = await readJsonFile(eventPath);
  const payload = event.client_payload || {};

  if (!payload.request_id) {
    throw new Error("repository_dispatch payload is missing request_id");
  }

  return payload;
}

export function parseGitHubRepoUrl(value) {
  const url = new URL(value);
  if (url.hostname.toLowerCase() !== "github.com") {
    throw new Error("Fork URL must use github.com");
  }

  const [owner, repo] = url.pathname.replace(/\.git$/, "").split("/").filter(Boolean);
  if (!owner || !repo) {
    throw new Error("Fork URL must point to a GitHub repository");
  }

  return { owner, repo, fullName: `${owner}/${repo}` };
}

export async function run(command, args, options = {}) {
  try {
    const result = await execFileAsync(command, args, {
      cwd: options.cwd || process.cwd(),
      env: { ...process.env, ...options.env },
      maxBuffer: options.maxBuffer || 20 * 1024 * 1024,
    });
    return result;
  } catch (error) {
    if (options.allowFailure) {
      return error;
    }

    const stderr = error.stderr ? `\n${error.stderr}` : "";
    const stdout = error.stdout ? `\n${error.stdout}` : "";
    throw new Error(`${command} ${args.join(" ")} failed${stdout}${stderr}`);
  }
}

export async function runJson(command, args, options = {}) {
  const result = await run(command, args, options);
  const stdout = result.stdout || "";
  const firstBrace = stdout.indexOf("{");
  if (firstBrace < 0) {
    throw new Error(`${command} ${args.join(" ")} did not return JSON`);
  }

  return JSON.parse(stdout.slice(firstBrace));
}

export async function sfJson(args, options = {}) {
  return runJson("sf", [...args, "--json"], options);
}

export async function sfText(args, options = {}) {
  return run("sf", args, options);
}

export async function querySalesforce(targetOrg, query) {
  const output = await sfJson(["data", "query", "--target-org", targetOrg, "--query", query]);
  return output.result?.records || [];
}

export async function getOrgOpenUrl(targetOrg, path = "") {
  const args = ["org", "open", "--target-org", targetOrg, "--url-only"];
  if (path) {
    args.push("--path", path);
  }

  const output = await sfJson(args);
  return output.result?.url || output.result;
}

export function githubRunUrl() {
  const server = process.env.GITHUB_SERVER_URL || "https://github.com";
  const repository = process.env.GITHUB_REPOSITORY || SOURCE_REPO;
  const runId = process.env.GITHUB_RUN_ID;
  return runId ? `${server}/${repository}/actions/runs/${runId}` : `${server}/${repository}/actions`;
}

export function addMask(value) {
  if (value) {
    process.stdout.write(`::add-mask::${value}\n`);
  }
}

export function expirationDate(durationDays) {
  const expiry = new Date(Date.now() + Number(durationDays) * 24 * 60 * 60 * 1000);
  return expiry.toISOString();
}

export function escapeSoql(value) {
  return String(value).replace(/\\/g, "\\\\").replace(/'/g, "\\'");
}
