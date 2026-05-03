# n8n + AWS Security Agent (GuardDuty → Bedrock → Slack)

Zenn記事「GuardDuty 通知を n8n + Bedrock で要約する Security Agent」の再現アセットです。GuardDuty Finding を EventBridge → リレーLambda → n8n Webhook → Bedrock 要約Lambda → Slack の経路で流す構成を、`.env` を作って `scripts/01〜06` を順に走らせるだけで再構築できます。

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

- 記事1の n8n self-host が稼働済み（KMS Key `alias/n8n-secrets` が存在し、Webhook が外から叩ける）
- `aws` CLI v2 がインストール済みでプロファイル `n8n-admin` が使える
- Node.js 24.x がローカルにある（Lambdaの `npm install` 用）
- `zip`, `jq`, `gettext` (`envsubst`) が PATH にある
- 個人 Slack ワークスペース + Incoming Webhook URL を発行済み

## 手順

```sh
# 1. 環境変数を読む
cp .env.example .env
$EDITOR .env
set -a; source .env; set +a

# 2. IAM ロール / GuardDuty 有効化
bash scripts/01-prepare-iam.sh

# 3. Lambda 3関数をビルドしてデプロイ
#    N8N_WEBHOOK_URL がまだ確定していなければ、先にプレースホルダを入れて、
#    n8n Workflow を Activate した後に再実行する
bash scripts/02-deploy-lambdas.sh

# 4. EventBridge -> リレー Lambda の配線
bash scripts/03-guardduty-eventbridge.sh

# 5. SSM に Bearer token と Slack Webhook URL を投入
#    N8N_WEBHOOK_BEARER は openssl rand -hex 32 で生成して export してから走らせる
bash scripts/04-register-secrets.sh

# 6. n8n 用の専用 IAM ユーザーとアクセスキーを発行
#    出力された AccessKeyId / SecretAccessKey は n8n の AWS credential UI に直接貼る
bash scripts/05-create-n8n-runtime-user.sh

# 7. n8n Web UI で workflows/aws-security-agent.workflow.json をインポートして
#    - Webhook ノードに Header Auth credential を作って `Authorization: Bearer <token>`
#    - awsLambda ノード2つに 6 で発行した AWS credential を割り当て
#    - Slack Notify ノードの url を `${SLACK_WEBHOOK_URL}` の実値に置換
#    - Activate

# 8. サンプル Finding を発火して end-to-end を確認
bash scripts/06-smoke-test.sh
```

## ファイル構成

```
.
├── README.md                        # この資料
├── .env.example                     # 必要な環境変数のテンプレート
├── scripts/
│   ├── 00-common.sh                 # 共通の env 検証
│   ├── 01-prepare-iam.sh            # GuardDuty + Lambda IAM ロール
│   ├── 02-deploy-lambdas.sh         # 3 Lambda の build + deploy
│   ├── 03-guardduty-eventbridge.sh  # EventBridge ルール + 権限 + ターゲット
│   ├── 04-register-secrets.sh       # SSM SecureString に bearer / slack url
│   ├── 05-create-n8n-runtime-user.sh # n8n 用 IAM ユーザー
│   ├── 06-smoke-test.sh             # GuardDuty サンプル Finding 発火
│   └── 99-cleanup.sh                # teardown 提案（destructive はコメントアウト）
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

- すべての IAM ポリシー JSON は `${AWS_ACCOUNT_ID}` `${AWS_DEFAULT_REGION}` `${KMS_KEY_ID}` を `envsubst` で置換してから put される。リポジトリ内に固有値は残らない。
- `N8N_WEBHOOK_BEARER` と `SLACK_WEBHOOK_URL` は `.env` 経由で export し、SSM 投入後はシェル履歴から削除する。
- 投資家Lambdaは `maskSecrets()` を出力直前にもう一度通し、CloudTrail 内に紛れ込んだ AKIA, ghp_, xoxb_, JWT, 秘密鍵, メールアドレスをマスクする。
- Bedrock IAM ポリシーは `arn:aws:bedrock:*::foundation-model/...` をワイルドカード region で書く。`jp.` 推論プロファイルは東京と大阪を行き来するため、固定 region だと `ap-northeast-3` にルートされた時に弾かれる。
