---
layout: default
title: Launch Live Demo
nav_order: 2
---

<link rel="stylesheet" href="{{ '/assets/live-demo.css' | relative_url }}">

# Launch Live Demo

Use this secure launch form to provision a Salesforce scratch org from your own Dev Hub. Choose the duration that fits your demo window. The Salesforce auth URL is sent directly to the short-lived broker over HTTPS, claimed once by GitHub Actions, and deleted after claim or TTL expiry.

<form
  id="live-demo-form"
  class="live-demo-form"
  action="javascript:void(0)"
  method="post"
  data-broker-url="https://salesforce-agentmemory-auth-broker.jay-agentforce.workers.dev/launch"
  autocomplete="off"
>
  <div class="live-demo-grid">
    <label>
      <span>Name</span>
      <input name="name" type="text" maxlength="120" required>
    </label>

    <label>
      <span>Email</span>
      <input name="email" type="email" required>
    </label>

    <label>
      <span>GitHub Username</span>
      <input name="githubUsername" type="text" maxlength="39" required>
    </label>

    <label>
      <span>Fork URL</span>
      <input
        name="forkUrl"
        type="url"
        placeholder="https://github.com/your-user/Salesforce-AgentMemory"
        required
      >
      <small class="live-demo-hint">
        The URL of <strong>your own fork</strong> of this repository. If you haven't forked it yet,
        open <a href="https://github.com/jayavardhan-raju/Salesforce-AgentMemory/fork" target="_blank" rel="noopener">this fork link</a>,
        click <strong>Create fork</strong>, then copy your new fork's address
        (<code>https://github.com/&lt;your-username&gt;/Salesforce-AgentMemory</code>).
      </small>
    </label>

    <input type="hidden" name="scratchOrgMode" value="reuse">

    <label>
      <span>Scratch Org Duration</span>
      <select name="scratchOrgDurationDays" required>
        <option value="7">7 days</option>
        <option value="14">14 days</option>
        <option value="21">21 days</option>
        <option value="30" selected>30 days</option>
      </select>
    </label>
  </div>

  <label class="live-demo-secret">
    <span>Salesforce Dev Hub Auth URL</span>
    <textarea
      name="salesforceAuthUrl"
      rows="5"
      placeholder="force://..."
      spellcheck="false"
      autocomplete="off"
      required
    ></textarea>
    <small class="live-demo-hint">
      Your Dev Hub's Salesforce CLI auth URL (it starts with <code>force://</code>). It lets the
      automation create the scratch org on your behalf. Generate it with the Salesforce CLI
      (<a href="https://developer.salesforce.com/tools/salesforcecli" target="_blank" rel="noopener">install it here</a>):
    </small>
    <pre class="live-demo-commands"><code># 1. Log in to your Dev Hub (opens a browser)
sf org login web --alias DevHub
# 2. Print its details; copy the sfdxAuthUrl value
sf org display --target-org DevHub --verbose --json</code></pre>
    <small class="live-demo-hint">
      Copy the value of <code>sfdxAuthUrl</code> from the JSON output and paste it above.
      It contains a refresh token, so treat it like a password &mdash; it is sent only to the
      short-lived broker over HTTPS and deleted right after the scratch org is created.
    </small>
  </label>

  <div class="live-demo-actions">
    <button type="submit" id="live-demo-submit">Launch 30-Day Demo</button>
    <p id="live-demo-status" role="status" aria-live="polite">Form script loading...</p>
  </div>
</form>

<section id="live-demo-result" class="live-demo-result" hidden>
  <h2>Request accepted</h2>
  <p>
    GitHub Actions is provisioning a Salesforce AgentMemory scratch org.
    Watch your email for the login credentials, expiration date, scenario results, and artifact link.
  </p>
  <dl>
    <dt>Request ID</dt>
    <dd id="live-demo-request-id"></dd>
    <dt>Scratch org duration</dt>
    <dd id="live-demo-duration"></dd>
    <dt>Auth URL claim expires</dt>
    <dd id="live-demo-expires-at"></dd>
  </dl>
</section>

## What Happens Next

1. The broker validates the Dev Hub auth URL and stores it with a short TTL.
2. The broker triggers a `repository_dispatch` event in `jayavardhan-raju/Salesforce-AgentMemory`.
3. GitHub Actions verifies your fork, claims the auth URL once, masks it, logs into your Dev Hub, and deletes the temp auth file.
4. The workflow reuses an existing active scratch org when one is usable; otherwise it creates a Developer-edition scratch org for the selected duration, deploys the app, assigns the `AgentMemory_Access` permission set, runs the three demo scenarios (TC1–TC3) plus the `AgentMemoryServiceTest` suite with code coverage, captures evidence, and sends a Mailtrap email.

The auth URL is never stored in GitHub Issues, workflow inputs, logs, artifacts, or email.

<script src="{{ '/assets/live-demo.js' | relative_url }}"></script>
