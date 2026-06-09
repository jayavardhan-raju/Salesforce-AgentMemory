(function () {
  const form = document.getElementById("live-demo-form");
  if (!form) {
    return;
  }

  const submitButton = document.getElementById("live-demo-submit");
  const status = document.getElementById("live-demo-status");
  const result = document.getElementById("live-demo-result");
  const requestId = document.getElementById("live-demo-request-id");
  const duration = document.getElementById("live-demo-duration");
  const expiresAt = document.getElementById("live-demo-expires-at");

  showStatus("Ready to submit.");

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    clearStatus();

    const brokerUrl = form.dataset.brokerUrl;
    const data = Object.fromEntries(new FormData(form).entries());
    const validationError = validate(data, brokerUrl);

    if (validationError) {
      showStatus(validationError, "error");
      return;
    }

    submitButton.disabled = true;
    showStatus("Submitting secure launch request...");

    try {
      const response = await fetch(brokerUrl, {
        method: "POST",
        headers: {
          "content-type": "application/json",
        },
        body: JSON.stringify({
          name: data.name.trim(),
          email: data.email.trim(),
          githubUsername: data.githubUsername.trim(),
          forkUrl: data.forkUrl.trim(),
          scratchOrgMode: data.scratchOrgMode,
          scratchOrgDurationDays: Number(data.scratchOrgDurationDays),
          salesforceAuthUrl: data.salesforceAuthUrl.trim(),
        }),
      });

      const body = await response.json();
      form.elements.salesforceAuthUrl.value = "";

      if (!response.ok) {
        const fields = Array.isArray(body.fields) ? ` (${body.fields.join(", ")})` : "";
        throw new Error(`${body.error || "Launch failed"}${fields}`);
      }

      form.reset();
      requestId.textContent = body.request_id;
      duration.textContent = `${body.scratch_org_duration_days} days`;
      expiresAt.textContent = new Date(body.expires_at).toLocaleString();
      result.hidden = false;
      showStatus("Launch accepted. Check your email for the demo org details.");
    } catch (error) {
      form.elements.salesforceAuthUrl.value = "";
      showStatus(error.message, "error");
    } finally {
      submitButton.disabled = false;
    }
  });

  function validate(data, brokerUrl) {
    if (!brokerUrl || brokerUrl.includes("<")) {
      return "The broker endpoint is not configured yet.";
    }

    if (!/^[A-Za-z0-9-]{1,39}$/.test((data.githubUsername || "").trim())) {
      return "Enter a valid GitHub username.";
    }

    try {
      const forkUrl = new URL((data.forkUrl || "").trim());
      if (forkUrl.hostname !== "github.com") {
        return "Fork URL must be a github.com repository URL.";
      }
    } catch {
      return "Enter a valid fork URL.";
    }

    const authUrl = (data.salesforceAuthUrl || "").trim();
    if (!/^force:\/\/[^@\s]+@(?:https:\/\/)?[A-Za-z0-9.-]+(?:\/[^\s]*)?$/.test(authUrl)) {
      return "Enter a valid Salesforce Dev Hub auth URL in force://...@instance format.";
    }

    const durationDays = Number(data.scratchOrgDurationDays);
    if (![7, 14, 21, 30].includes(durationDays)) {
      return "Choose a supported scratch org duration.";
    }

    if (!["create", "reuse"].includes(data.scratchOrgMode)) {
      return "Choose whether to create a new scratch org or use an existing one.";
    }

    return "";
  }

  function showStatus(message, state) {
    status.textContent = message;
    if (state) {
      status.dataset.state = state;
    } else {
      delete status.dataset.state;
    }
  }

  function clearStatus() {
    showStatus("");
  }
})();
