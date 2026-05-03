import {
  BedrockRuntimeClient,
  InvokeModelCommand
} from "@aws-sdk/client-bedrock-runtime";
import { SSMClient, GetParameterCommand } from "@aws-sdk/client-ssm";

const MODEL_ID =
  process.env.MODEL_ID ||
  "jp.anthropic.claude-sonnet-4-6-20251022-v1:0";
const MAX_TOKENS = Number(process.env.MAX_TOKENS || 16000);
const REGION = process.env.AWS_REGION || "ap-northeast-1";
const GITHUB_TOKEN_PARAM =
  process.env.GITHUB_TOKEN_PARAM || "/prd-agent/prod/github-token";
const TOKEN_CACHE_MS = 5 * 60 * 1000;

const SYSTEM_PROMPT = `あなたはシニアソフトウェアエンジニアです。
渡された PRD と DesignDoc に基づいて、対象リポジトリに最小限かつ的確な実装変更を加える「ファイル変更プラン」を JSON のみで返してください。

厳守事項:
- DesignDocに書かれた範囲を逸脱しない
- 既存リポジトリのスタイルや命名規約を尊重する
- 「テストを通すためだけ」のテストではなく本質的なテスト観点を書く
- 不要な依存追加・スコープ拡大・テンプレ的な空ファイル生成を避ける
- 破壊的変更や危険な操作(rm相当、認証情報のリポジトリ追加等)は絶対にしない
- すべてのファイル content は完全な最終形(差分ではなく全文)を含めること
- 次のパスは絶対に変更しない: .github/, .gitlab/, Dockerfile*, docker-compose.*, Caddyfile, iam-*.json, deploy.sh, bootstrap.sh, .env*, secrets/, credentials*, *-lock.json, *.lock, .ssh/, id_rsa*, id_ed25519*, *.pem, *.key, *.p12, *.pfx

出力形式: 以下の JSON オブジェクトのみ。Markdown フェンス禁止、前後に説明文を付けない。
{
  "summary_markdown": "実装サマリ Markdown(PRに投稿される)",
  "files": [
    {
      "path": "リポジトリ相対パス",
      "operation": "create | update | delete",
      "content": "ファイル全体の内容(create/update時のみ。deleteのときは省略可)",
      "rationale": "1〜3文の根拠"
    }
  ]
}

files は 1〜30 件以内。`;

const bedrock = new BedrockRuntimeClient({ region: REGION, maxAttempts: 5 });
const ssm = new SSMClient({ region: REGION });

let cachedToken = null;
let cachedAt = 0;

const DENIED_PATH_PATTERNS = [
  /^\.github\//i,
  /^\.gitlab\//i,
  /(^|\/)Dockerfile(\.|$)/i,
  /(^|\/)docker-compose\./i,
  /(^|\/)Caddyfile$/i,
  /(^|\/)iam-.*\.json$/i,
  /(^|\/)deploy\.sh$/i,
  /(^|\/)bootstrap\.sh$/i,
  /(^|\/)\.env($|\.)/i,
  /(^|\/)secrets?\//i,
  /(^|\/)credentials?($|\.|\/)/i,
  /(^|\/)package-lock\.json$/i,
  /(^|\/)pnpm-lock\.yaml$/i,
  /(^|\/)yarn\.lock$/i,
  /(^|\/)Gemfile\.lock$/i,
  /(^|\/)\.ssh\//i,
  /(^|\/)id_rsa/i,
  /(^|\/)id_ed25519/i,
  /\.pem$/i,
  /\.key$/i,
  /\.p12$/i,
  /\.pfx$/i
];

function validatePath(p) {
  if (typeof p !== "string") return "path must be a string";
  if (p.length === 0) return "path is empty";
  if (p.length > 200) return "path exceeds 200 chars";
  if (p.startsWith("/")) return "path must be relative";
  if (p.includes("\0")) return "path contains null byte";
  if (p.split("/").some((seg) => seg === "..")) {
    return "path contains '..' segment";
  }
  for (const pattern of DENIED_PATH_PATTERNS) {
    if (pattern.test(p)) return `denied by pattern ${pattern}`;
  }
  return null;
}

async function getGithubToken() {
  const now = Date.now();
  if (cachedToken && now - cachedAt < TOKEN_CACHE_MS) return cachedToken;
  const out = await ssm.send(
    new GetParameterCommand({
      Name: GITHUB_TOKEN_PARAM,
      WithDecryption: true
    })
  );
  cachedToken = out.Parameter.Value;
  cachedAt = now;
  return cachedToken;
}

async function githubRequest(token, method, path, body) {
  const url = `https://api.github.com${path}`;
  const headers = {
    Authorization: `Bearer ${token}`,
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "prd-design-bedrock-implementer/1.0"
  };
  const options = { method, headers };
  if (body !== undefined) {
    headers["Content-Type"] = "application/json";
    options.body = JSON.stringify(body);
  }
  const resp = await fetch(url, options);
  const text = await resp.text();
  let parsed = null;
  try {
    parsed = text ? JSON.parse(text) : null;
  } catch (_) {}
  if (!resp.ok && resp.status !== 404) {
    throw new Error(
      `GitHub ${method} ${path} -> ${resp.status}: ${text.slice(0, 500)}`
    );
  }
  return { status: resp.status, body: parsed };
}

async function getFileSha(token, owner, repo, path, ref) {
  const enc = encodeURIComponent(path).replace(/%2F/g, "/");
  const r = await githubRequest(
    token,
    "GET",
    `/repos/${owner}/${repo}/contents/${enc}?ref=${encodeURIComponent(ref)}`
  );
  if (r.status === 404) return null;
  if (Array.isArray(r.body)) throw new Error(`Path is a directory: ${path}`);
  return r.body && r.body.sha ? r.body.sha : null;
}

async function applyFile(token, owner, repo, branch, file, message) {
  const enc = encodeURIComponent(file.path).replace(/%2F/g, "/");
  const url = `/repos/${owner}/${repo}/contents/${enc}`;
  if (file.operation === "delete") {
    const sha = await getFileSha(token, owner, repo, file.path, branch);
    if (!sha) return { path: file.path, skipped: "missing for delete" };
    const r = await githubRequest(token, "DELETE", url, {
      message,
      branch,
      sha
    });
    return {
      path: file.path,
      operation: "delete",
      status: r.status,
      commit: r.body?.commit?.sha
    };
  }
  const existingSha = await getFileSha(token, owner, repo, file.path, branch);
  const payload = {
    message,
    branch,
    content: Buffer.from(file.content || "", "utf8").toString("base64")
  };
  if (existingSha) payload.sha = existingSha;
  const r = await githubRequest(token, "PUT", url, payload);
  return {
    path: file.path,
    operation: existingSha ? "update" : "create",
    status: r.status,
    commit: r.body?.commit?.sha
  };
}

function parseBedrockJson(text) {
  const cleaned = text
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();
  try {
    return JSON.parse(cleaned);
  } catch (_) {
    const start = cleaned.indexOf("{");
    const end = cleaned.lastIndexOf("}");
    if (start >= 0 && end > start) {
      return JSON.parse(cleaned.slice(start, end + 1));
    }
    throw new Error(
      "Bedrock output is not valid JSON. Head 200: " + cleaned.slice(0, 200)
    );
  }
}

export const handler = async (event) => {
  const required = [
    "task_title",
    "prd_markdown",
    "design_doc_markdown",
    "target_repository",
    "branch_name"
  ];
  for (const key of required) {
    if (!event[key]) throw new Error(`Missing field: ${key}`);
  }
  const [owner, repo] = String(event.target_repository).split("/");
  if (!owner || !repo) {
    throw new Error("target_repository must be owner/repo");
  }

  const userPrompt = JSON.stringify(
    {
      task_title: event.task_title,
      target_repository: event.target_repository,
      base_branch: event.base_branch || "main",
      branch_name: event.branch_name,
      additional_constraints: event.additional_constraints || null,
      prd_markdown: event.prd_markdown,
      design_doc_markdown: event.design_doc_markdown
    },
    null,
    2
  );

  const body = {
    anthropic_version: "bedrock-2023-05-31",
    max_tokens: MAX_TOKENS,
    system: SYSTEM_PROMPT,
    messages: [{ role: "user", content: userPrompt }]
  };

  const response = await bedrock.send(
    new InvokeModelCommand({
      modelId: MODEL_ID,
      contentType: "application/json",
      accept: "application/json",
      body: JSON.stringify(body)
    })
  );
  const respText = new TextDecoder().decode(response.body);
  const parsed = JSON.parse(respText);
  const modelText =
    (parsed.content && parsed.content[0] && parsed.content[0].text) || "";
  const plan = parseBedrockJson(modelText);
  if (!Array.isArray(plan.files) || plan.files.length === 0) {
    throw new Error("Bedrock returned no files");
  }

  const token = await getGithubToken();
  const safeTitle = String(event.task_title).slice(0, 60);
  const commitMessage = `feat: ${safeTitle} (Bedrock implementation)`;
  const results = [];
  for (const file of plan.files) {
    if (!file.path || !file.operation) {
      results.push({ path: file.path || "?", error: "missing path or operation" });
      continue;
    }
    if (!["create", "update", "delete"].includes(file.operation)) {
      results.push({
        path: file.path,
        error: `unsupported operation: ${file.operation}`
      });
      continue;
    }
    const pathError = validatePath(file.path);
    if (pathError) {
      results.push({
        path: file.path,
        error: `path rejected: ${pathError}`,
        rationale: file.rationale || null
      });
      continue;
    }
    try {
      const r = await applyFile(
        token,
        owner,
        repo,
        event.branch_name,
        file,
        commitMessage
      );
      results.push({ ...r, rationale: file.rationale || null });
    } catch (e) {
      results.push({ path: file.path, error: e.message });
    }
  }

  return {
    summary_markdown: plan.summary_markdown || "(summary missing)",
    files_changed: results,
    model_id: MODEL_ID,
    branch: event.branch_name,
    target_repository: event.target_repository
  };
};
