import { ensureDir, parseGitHubRepoUrl, readDispatchPayload, SOURCE_REPO, writeJsonFile } from "./lib.mjs";

const payload = await readDispatchPayload();
const fork = parseGitHubRepoUrl(payload.fork_url);
const requester = String(payload.github_username || "").trim();

if (!requester) {
  throw new Error("repository_dispatch payload is missing github_username");
}

if (fork.owner.toLowerCase() !== requester.toLowerCase()) {
  throw new Error(`Fork owner ${fork.owner} does not match requester ${requester}`);
}

const token = process.env.GITHUB_TOKEN;
if (!token) {
  throw new Error("GITHUB_TOKEN is required to verify the requester fork");
}

// Bound the GitHub API call with a timeout. Node's fetch (undici) uses unref'd
// sockets, so a stalled top-level `await fetch()` can let the event loop drain
// with the await still pending -> Node exits 13 ("unsettled top-level await").
// An explicit AbortSignal guarantees this promise settles.
let response;
try {
  response = await fetch(`https://api.github.com/repos/${fork.owner}/${fork.repo}`, {
    headers: {
      accept: "application/vnd.github+json",
      authorization: `Bearer ${token}`,
      "user-agent": "salesforce-agentmemory-live-demo",
      "x-github-api-version": "2022-11-28",
    },
    signal: AbortSignal.timeout(30000),
  });
} catch (error) {
  const reason = error?.name === "TimeoutError" ? "timed out after 30s" : "network error";
  throw new Error(`GitHub fork verification request for ${fork.fullName} failed (${reason}): ${error?.message || error}`);
}

if (!response.ok) {
  throw new Error(`Unable to read fork metadata for ${fork.fullName}: HTTP ${response.status}`);
}

const repo = await response.json();
const parent = repo.parent?.full_name || repo.source?.full_name || "";

if (!repo.fork || parent.toLowerCase() !== SOURCE_REPO.toLowerCase()) {
  throw new Error(`${fork.fullName} is not a fork of ${SOURCE_REPO}`);
}

const artifactDir = process.env.ARTIFACT_DIR;
if (artifactDir) {
  await ensureDir(artifactDir);
  await writeJsonFile(`${artifactDir}/request.json`, {
    request_id: payload.request_id,
    name: payload.name,
    email: payload.email,
    github_username: requester,
    fork_url: payload.fork_url,
    verified_fork: fork.fullName,
    source_repo: SOURCE_REPO,
    scratch_org_mode: payload.scratch_org_mode || "create",
    scratch_org_duration_days: Number(payload.scratch_org_duration_days || 30),
  });
}

console.log(`Verified requester fork: ${fork.fullName}`);
