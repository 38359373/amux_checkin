const endpoint = "https://muyuan.do/api/user/checkin";

const accessToken = process.env.MUYUAN_ACCESS_TOKEN?.trim();
const userId = process.env.MUYUAN_USER_ID?.trim();

if (!userId) {
  console.error("Missing MUYUAN_USER_ID. Add it as a GitHub Actions secret.");
  process.exit(1);
}

if (!accessToken) {
  console.error("Missing MUYUAN_ACCESS_TOKEN. Add it as a GitHub Actions secret.");
  process.exit(1);
}

const headers = {
  Authorization: `Bearer ${accessToken}`,
  "New-Api-User": userId,
  Accept: "application/json, text/plain, */*"
};

console.log("Auth mode: bearer token");

const response = await fetch(endpoint, {
  method: "POST",
  headers
});

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

console.log(`MUYUAN check-in HTTP ${response.status}`);
if (message) {
  console.log(`Response: ${message}`);
}

if (!response.ok) {
  process.exit(1);
}
