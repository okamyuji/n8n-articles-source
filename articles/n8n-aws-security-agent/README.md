# n8n + AWS Security Agent (GuardDuty → Bedrock → Slack)

Zenn記事「GuardDuty通知をn8n + Bedrockで要約するSecurity Agent」の再現アセットです。GuardDuty FindingをEventBridge → リレーLambda → n8n Webhook → Bedrock要約Lambda → Slackの経路で流す構成を、`.env` を作って `scripts/01〜06` を順に走らせるだけで再構築できます。

## 全体像

```
GuardDuty Finding
  └─> EventBridge rule
        └─> aws-security-relay-to-n8n (Lambda)
              └─> POST n8n /webhook/aws-security-finding (Header Auth)
                    └─> Normalize Code
                          └─> IF severity >= 4
                                └─> aws-security-investigator-readonly (Lambda)
                                      └─> aws-security-bedrock-summarize (Lambda)
                                            └─> Slack Incoming Webhook
```

## 前提

- 記事1のn8n self-hostが稼働済み（KMS Key `alias/n8n-secrets` が存在し、Webhookが外から叩ける）
- `aws` CLI v2がインストール済みでプロファイル `n8n-admin` が使える
- Node.js 24.xがローカルにある（Lambdaの `npm install` 用）
- `zip`, `jq`, `gettext` (`envsubst`) がPATHにある
- 個人Slackワークスペース + Incoming Webhook URLを発行済み

## 手順

```sh
# 1. 環境変数を読む
cp .env.example .env
$EDITOR .env
set -a; source .env; set +a

# 2. IAMロール / GuardDuty有効化
bash scripts/01-prepare-iam.sh

# 3. Lambda 3関数をビルドしてデプロイ
#    N8N_WEBHOOK_URLがまだ確定していなければ、先にプレースホルダを入れて、
#    n8n WorkflowをActivateした後に再実行する
bash scripts/02-deploy-lambdas.sh

# 4. EventBridge -> リレーLambdaの配線
bash scripts/03-guardduty-eventbridge.sh

# 5. SSMにBearer tokenとSlack Webhook URLを投入
#    N8N_WEBHOOK_BEARERはopenssl rand -hex 32で生成してexportしてから走らせる
bash scripts/04-register-secrets.sh

# 6. n8n用の専用IAMユーザーとアクセスキーを発行
#    出力されたAccessKeyId / SecretAccessKeyはn8nのAWS credential UIに直接貼る
bash scripts/05-create-n8n-runtime-user.sh

# 7. n8n Web UIでworkflows/aws-security-agent.workflow.jsonをインポートして
#    - WebhookノードにHeader Auth credentialを作って `Authorization: Bearer <token>`
#    - awsLambdaノード2つに6で発行したAWS credentialを割り当て
#    - Slack Notifyノードのurlを `${SLACK_WEBHOOK_URL}` の実値に置換
#    - Activate

# 8. サンプルFindingを発火してend-to-endを確認
bash scripts/06-smoke-test.sh
```

## ファイル構成

```
.
├── README.md                        # この資料
├── .env.example                     # 必要な環境変数のテンプレート
├── scripts/
│   ├── 00-common.sh                 # 共通のenv検証
│   ├── 01-prepare-iam.sh            # GuardDuty + Lambda IAMロール
│   ├── 02-deploy-lambdas.sh         # 3 Lambdaのbuild + deploy
│   ├── 03-guardduty-eventbridge.sh  # EventBridgeルール + 権限 + ターゲット
│   ├── 04-register-secrets.sh       # SSM SecureStringにbearer / slack url
│   ├── 05-create-n8n-runtime-user.sh # n8n用IAMユーザー
│   ├── 06-smoke-test.sh             # GuardDutyサンプルFinding発火
│   └── 99-cleanup.sh                # teardown提案（destructiveはコメントアウト）
├── lambda/
│   ├── investigator/{index.mjs, package.json}
│   ├── relay/{index.mjs, package.json}
│   └── bedrock/{index.mjs, package.json}
├── workflows/
│   └── aws-security-agent.workflow.json
└── iam/
    ├── lambda-trust-policy.json
    ├── investigator-policy.json
    ├── relay-policy.json
    ├── bedrock-policy.json
    └── n8n-runtime-policy.json
```

## セキュリティ運用上の注意

- すべてのIAMポリシーJSONは `${AWS_ACCOUNT_ID}` `${AWS_DEFAULT_REGION}` `${KMS_KEY_ID}` を `envsubst` で置換してからputされる。リポジトリ内に固有値は残らない。
- `N8N_WEBHOOK_BEARER` と `SLACK_WEBHOOK_URL` は `.env` 経由でexportし、SSM投入後はシェル履歴から削除する。
- 一次調査Lambdaは `maskSecrets()` を出力直前にもう一度通し、CloudTrail内に紛れ込んだAKIA, ghp_, xoxb_, JWT, 秘密鍵, メールアドレスをマスクする。
- Bedrock IAMポリシーは `arn:aws:bedrock:*::foundation-model/...` をワイルドカードregionで書く。`jp.` 推論プロファイルは東京と大阪を行き来するため、固定regionだと `ap-northeast-3` にルートされた時に弾かれる。
