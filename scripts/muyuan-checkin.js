const endpoint = "https://muyuan.do/api/user/checkin";
const month = new Date().toISOString().slice(0, 7);
const statusEndpoint = `${endpoint}?month=${month}`;

if (process.platform === "win32") {
  process.stdout.setDefaultEncoding("utf8");
  process.stderr.setDefaultEncoding("utf8");
}

const accessToken = process.env.MUYUAN_ACCESS_TOKEN?.trim();
const userId = process.env.MUYUAN_USER_ID?.trim();

if (!userId) {
  console.error("Missing MUYUAN_USER_ID.");
  process.exit(1);
}

if (!accessToken) {
  console.error("Missing MUYUAN_ACCESS_TOKEN.");
  process.exit(1);
}

const headers = {
  Authorization: `Bearer ${accessToken}`,
  "New-Api-User": userId,
  Accept: "application/json, text/plain, */*"
};

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function parseResponse(response) {
  const contentType = response.headers.get("content-type") || "";
  const rawBody = await response.text();
  let payload = rawBody;

  if (contentType.includes("application/json") && rawBody) {
    try {
      payload = JSON.parse(rawBody);
    } catch {
      payload = rawBody;
    }
  }

  const message =
    typeof payload === "object" && payload !== null
      ? payload.message || payload.msg || payload.error || JSON.stringify(payload)
      : String(payload || "");

  return { rawBody, payload, message };
}

function getRetryDelayMs(response, payload, attempt) {
  const retryAfterHeader = response.headers.get("retry-after");
  const payloadRetryAfter =
    typeof payload === "object" && payload !== null ? payload.retry_after : undefined;
  const retryAfterSeconds = Number(retryAfterHeader || payloadRetryAfter);

  if (Number.isFinite(retryAfterSeconds) && retryAfterSeconds > 0) {
    return retryAfterSeconds * 1000;
  }

  return Math.min(15000 * attempt, 60000);
}

async function postCheckinWithRetry(maxAttempts = 3) {
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    const response = await fetch(endpoint, {
      method: "POST",
      headers
    });

    const parsed = await parseResponse(response);
    const retryableHttpError = response.status === 502 || response.status === 503 || response.status === 504;
    const retryableCloudflareError =
      typeof parsed.payload === "object" &&
      parsed.payload !== null &&
      parsed.payload.cloudflare_error === true &&
      parsed.payload.retryable === true;

    if ((retryableHttpError || retryableCloudflareError) && attempt < maxAttempts) {
      const delayMs = getRetryDelayMs(response, parsed.payload, attempt);
      console.log(
        `Retryable upstream error on attempt ${attempt}/${maxAttempts}. Waiting ${Math.round(delayMs / 1000)}s before retry.`
      );
      await sleep(delayMs);
      continue;
    }

    return { response, ...parsed };
  }

  throw new Error("Unexpected retry loop exit.");
}

async function fetchCheckinStatus() {
  const response = await fetch(statusEndpoint, {
    method: "GET",
    headers
  });
  const { payload } = await parseResponse(response);

  if (!response.ok) {
    return false;
  }

  return payload?.success === true && payload?.data?.stats?.checked_in_today === true;
}

console.log("Auth mode: bearer token");

const { response, rawBody, payload, message } = await postCheckinWithRetry();
const appSuccess =
  typeof payload === "object" && payload !== null && "success" in payload
    ? payload.success === true
    : undefined;

console.log(`MUYUAN check-in HTTP ${response.status}`);
if (message) {
  console.log(`Response: ${message}`);
}

if (!response.ok) {
  if (response.status === 403 && rawBody.includes("Just a moment")) {
    console.error("Blocked by Cloudflare managed challenge.");
  }
  process.exit(1);
}

if (appSuccess === false) {
  const checkedInToday = await fetchCheckinStatus();
  if (checkedInToday) {
    console.log("Already checked in today.");
    process.exit(0);
  }
  process.exit(1);
}
