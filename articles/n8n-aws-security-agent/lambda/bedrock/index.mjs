import {
  BedrockRuntimeClient,
  InvokeModelCommand
} from "@aws-sdk/client-bedrock-runtime";

const MODEL_ID =
  process.env.MODEL_ID ||
  "jp.anthropic.claude-haiku-4-5-20251001-v1:0";
const MAX_TOKENS = Number(process.env.MAX_TOKENS || 2048);
const REGION = process.env.AWS_REGION || "ap-northeast-1";

const SYSTEM_PROMPT = `あなたはAWSセキュリティ運用の一次調査アシスタントです。
以下を厳守してください。

- 検知ソースはAWS GuardDutyです。新しい検知方式は推測しないでください。
- 与えられたデータにない事実を断定しないでください。
- 機微情報(AccessKeyId、メール、トークン)が原文に含まれていればマスク済みかを確認し、漏れていればさらにマスクして出力してください。
- 自動実行を勧める文言を出さないでください。破壊的操作は人間が承認します。

出力は Slack の mrkdwn 形式で書きます。Markdownの見出し(#)や太字(**)は使わず、次の規則に従ってください。

- セクション見出しは行頭で *セクション名* のように単一アスタリスクで囲む
- 強調は *語句* (単一アスタリスク)
- 箇条書きは行頭に • (中黒)を使う
- コードや識別子は \` でくくる
- 各セクションは空行で区切る
- 全体は3000文字以内に収める

出力構成:

*概要*
1段落で何が起きたかを説明する。

*重大度評価*
Critical / High / Medium / Low / Informational のいずれかを選び、根拠を1から2文で書く。

*確認できた事実*
• CloudTrail 等から取れた事実だけを列挙する

*不正利用の可能性*
Low / Medium / High / Critical を選び、根拠を述べる。

*追加調査すべきこと*
• 人が次に確認すべき API や画面を挙げる

*推奨初動*
• 封じ込め: ...
• 復旧: ...
• 再発防止: ...

*自動実行してはいけない操作*
• エージェントが触ってはいけない操作`;

const client = new BedrockRuntimeClient({
  region: REGION,
  maxAttempts: 5
});

export const handler = async (event) => {
  const finding = event.finding || {};
  const investigation = event.investigation || {};

  const userPrompt = `GuardDuty Finding(正規化済み):\n${JSON.stringify(finding)}\n\n一次調査Lambdaの結果:\n${JSON.stringify(investigation)}\n\n上記を使って、定義された出力フォーマットでまとめてください。`;

  const body = {
    anthropic_version: "bedrock-2023-05-31",
    max_tokens: MAX_TOKENS,
    system: SYSTEM_PROMPT,
    messages: [{ role: "user", content: userPrompt }]
  };

  const response = await client.send(
    new InvokeModelCommand({
      modelId: MODEL_ID,
      contentType: "application/json",
      accept: "application/json",
      body: JSON.stringify(body)
    })
  );

  const text = new TextDecoder().decode(response.body);
  const parsed = JSON.parse(text);
  const summary =
    (parsed.content && parsed.content[0] && parsed.content[0].text) ||
    JSON.stringify(parsed);

  return { summary, modelId: MODEL_ID };
};
