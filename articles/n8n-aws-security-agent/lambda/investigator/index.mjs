import {
  CloudTrailClient,
  LookupEventsCommand
} from "@aws-sdk/client-cloudtrail";
import {
  IAMClient,
  GetAccessKeyLastUsedCommand,
  ListAccessKeysCommand
} from "@aws-sdk/client-iam";

const LOOKBACK_HOURS = Number(process.env.LOOKBACK_HOURS || 24);
const MAX_EVENTS = Number(process.env.MAX_EVENTS || 50);

export const handler = async (event) => {
  const region = event.region || "ap-northeast-1";
  const username = event.username || null;
  const accessKeyId = event.accessKeyId || null;
  const instanceId = event.instanceId || null;

  const startTime = new Date(Date.now() - LOOKBACK_HOURS * 60 * 60 * 1000);
  const endTime = new Date();

  const cloudtrail = new CloudTrailClient({ region });
  const iam = new IAMClient({ region: "us-east-1" });

  const lookupParams = {
    StartTime: startTime,
    EndTime: endTime,
    MaxResults: MAX_EVENTS
  };
  if (username) {
    lookupParams.LookupAttributes = [
      { AttributeKey: "Username", AttributeValue: username }
    ];
  } else if (accessKeyId) {
    lookupParams.LookupAttributes = [
      { AttributeKey: "AccessKeyId", AttributeValue: accessKeyId }
    ];
  }

  const trailEvents = await cloudtrail
    .send(new LookupEventsCommand(lookupParams))
    .catch((e) => ({ Events: [], error: e.message }));

  let accessKeyLastUsed = null;
  if (accessKeyId) {
    accessKeyLastUsed = await iam
      .send(new GetAccessKeyLastUsedCommand({ AccessKeyId: accessKeyId }))
      .catch((e) => ({ error: e.message }));
  }

  let userKeys = null;
  if (username) {
    userKeys = await iam
      .send(new ListAccessKeysCommand({ UserName: username }))
      .catch((e) => ({ error: e.message }));
  }

  const events = (trailEvents.Events || []).map((e) => ({
    eventId: e.EventId,
    eventName: sanitizeForPrompt(e.EventName, 120),
    eventTime: e.EventTime,
    username: sanitizeForPrompt(e.Username, 120),
    sourceIp: sanitizeForPrompt(extractSourceIp(e.CloudTrailEvent), 64),
    userAgent: sanitizeForPrompt(extractUserAgent(e.CloudTrailEvent), 256),
    resources: e.Resources
  }));

  const masked = maskSecrets({
    region,
    startTime,
    endTime,
    inputs: { username, accessKeyId, instanceId },
    cloudTrailEvents: events,
    cloudTrailError: trailEvents.error,
    accessKeyLastUsed,
    userKeys
  });

  return masked;
};

function extractSourceIp(cloudTrailEventJson) {
  try {
    const parsed = JSON.parse(cloudTrailEventJson || "{}");
    return parsed.sourceIPAddress || null;
  } catch {
    return null;
  }
}

function extractUserAgent(cloudTrailEventJson) {
  try {
    const parsed = JSON.parse(cloudTrailEventJson || "{}");
    return parsed.userAgent || null;
  } catch {
    return null;
  }
}

function sanitizeForPrompt(value, maxLen) {
  if (value == null) return value;
  if (typeof value !== "string") return value;
  const stripped = value
    .replace(/[\r\n\t]+/g, " ")
    .replace(/[\x00-\x1f\x7f]/g, "")
    .replace(/`+/g, "'")
    .replace(/\$\{/g, "$ {");
  return stripped.length > maxLen
    ? stripped.slice(0, maxLen) + "...(truncated)"
    : stripped;
}

function maskSecrets(obj) {
  const text = JSON.stringify(obj);
  const masked = text
    .replace(
      /-----BEGIN [A-Z ]{0,32}PRIVATE KEY-----[\s\S]{0,8192}?-----END [A-Z ]{0,32}PRIVATE KEY-----/g,
      "***PRIVATE_KEY***"
    )
    .replace(/AKIA[0-9A-Z]{16}/g, "AKIA****************")
    .replace(/ASIA[0-9A-Z]{16}/g, "ASIA****************")
    .replace(/ghp_[A-Za-z0-9]{30,255}/g, "ghp_***MASKED***")
    .replace(/gho_[A-Za-z0-9]{30,255}/g, "gho_***MASKED***")
    .replace(/ghu_[A-Za-z0-9]{30,255}/g, "ghu_***MASKED***")
    .replace(/ghs_[A-Za-z0-9]{30,255}/g, "ghs_***MASKED***")
    .replace(/ghr_[A-Za-z0-9]{30,255}/g, "ghr_***MASKED***")
    .replace(/github_pat_[A-Za-z0-9_]{60,255}/g, "github_pat_***MASKED***")
    .replace(/xox[baprs]-[A-Za-z0-9-]{10,255}/g, "xox*-***MASKED***")
    .replace(
      /eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/g,
      "***JWT***"
    )
    .replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, "***EMAIL***")
    .replace(
      /"(secret|token|password|authorization|api[_-]?key)"\s*:\s*"[^"]+"/gi,
      '"$1":"***MASKED***"'
    );
  return JSON.parse(masked);
}
