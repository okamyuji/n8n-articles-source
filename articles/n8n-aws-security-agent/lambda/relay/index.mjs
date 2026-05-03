import { SSMClient, GetParameterCommand } from "@aws-sdk/client-ssm";

const N8N_WEBHOOK_URL = process.env.N8N_WEBHOOK_URL;
const SSM_TOKEN_NAME =
  process.env.SSM_TOKEN_NAME || "/n8n/prod/security-agent/webhook-token";

let cachedToken = null;
let cachedAt = 0;
const TOKEN_CACHE_MS = 5 * 60 * 1000;

const ssm = new SSMClient({});

async function getToken() {
  const now = Date.now();
  if (cachedToken && now - cachedAt < TOKEN_CACHE_MS) {
    return cachedToken;
  }
  const out = await ssm.send(
    new GetParameterCommand({ Name: SSM_TOKEN_NAME, WithDecryption: true })
  );
  cachedToken = out.Parameter.Value;
  cachedAt = now;
  return cachedToken;
}

export const handler = async (event) => {
  if (!N8N_WEBHOOK_URL) {
    throw new Error("N8N_WEBHOOK_URL is not set");
  }
  const token = await getToken();

  const response = await fetch(N8N_WEBHOOK_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
      "X-Aws-Source": event.source || "unknown"
    },
    body: JSON.stringify(event)
  });

  const text = await response.text();
  if (!response.ok) {
    throw new Error(`n8n returned ${response.status}: ${text}`);
  }
  return { status: response.status, body: text };
};
