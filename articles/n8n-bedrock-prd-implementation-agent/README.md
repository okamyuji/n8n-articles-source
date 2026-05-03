# n8n + Bedrock PRD/DesignDoc Implementation Agent

Zenn記事「n8nとBedrockでPRD/DesignDocから実装PRまで運ぶAgent」の再現アセットです。Form入力からGeminiでPRD/DesignDocを生成してGoogle Driveに保存し、GitHubにPRブランチを作って、AWS Bedrock(Claude Sonnet 4.6)で動くLambdaが実装パッチを生成して同PRにコミットし、最後にPRコメントへ自動実装サマリを投稿する構成です。

## 全体像

```
n8n Form Trigger (Shared Secret 認証)
  └─> Verify Shared Secret (timing-safe compare)
        └─> Prepare Request (slugify + system prompt)
              └─> Gemini 2.5 Flash (PRD/DesignDoc を JSON で生成)
                    └─> Parse Gemini Output (length / forbidden pattern guard)
                          └─> Markdown→HTML & Google Drive Upload (PRD)
                                └─> Google Drive Upload (DesignDoc)
                                      └─> GitHub: branch + commit + PR
                                            └─> Invoke Bedrock Implementer Lambda
                                                  └─> validatePath で危険パス遮断
                                                        └─> GitHub Contents API で PR ブランチへコミット
                                                              └─> PR コメントへ自動実装サマリ投稿
```

## 前提

- 記事1のn8n self-hostが稼働済み
- 記事2の `n8n-runtime-user` IAMユーザーが存在（無ければscripts/03が新規作成）
- AWS CLI v2とNode.js 24.xがローカルにある
- GitHub Personal Access Token（`repo` + `pull-requests` スコープ）
- Google Cloud ConsoleでDrive APIとGenerative Language(Gemini) APIのクレデンシャル発行済み
- Form経由で実装依頼する権限を持つ人に渡すShared Secret

## 手順

```sh
# 1. 環境変数を読み込む
cp .env.example .env
$EDITOR .env
set -a; source .env; set +a

# 2. IAM Role/Policy + GitHub TokenをSSMへ
bash scripts/01-prepare-iam-and-ssm.sh

# 3. Lambdaをビルド + デプロイ
bash scripts/02-deploy-implementer-lambda.sh

# 4. n8n用IAM ユーザーへLambda Invoke権限を付与
bash scripts/03-create-n8n-runtime-user.sh

# 5. PRD_AGENT_FORM_SECRETをn8nコンテナへ手動で投入（指示を表示）
bash scripts/04-set-form-secret.sh

# 6. n8nのWeb UIにworkflows/prd-implementation-agent.workflow.jsonをインポート
#    インポート後、各ノードのcredentialを自分のものに張り替える
#    - Generate PRD and DesignDoc: Google Gemini (PaLM) Api
#    - Get Base Branch Ref / Create GitHub Branch / Commit DesignDoc / Create GitHub PR
#      / Post Implementation Summary: GitHub account
#    - Upload PRD / DesignDoc as HTML: Google Drive OAuth2 Api
#    - Invoke Bedrock Implementer: AWS (article 2と同じn8n-runtime-userのキー)
#
#    また workflow JSON内に `REPLACE_WITH_YOUR_DRIVE_FOLDER_ID` のプレースホルダがあるので
#    自分のDrive folder IDに置換してからActivateする。
#    Form TriggerのwebhookIdとversionIdはn8nインポート時に再生成される。
```

## ファイル構成

```
.
├── README.md
├── .env.example
├── scripts/
│   ├── 00-common.sh
│   ├── 01-prepare-iam-and-ssm.sh
│   ├── 02-deploy-implementer-lambda.sh
│   ├── 03-create-n8n-runtime-user.sh
│   ├── 04-set-form-secret.sh           # 手動操作のガイドのみ表示
│   └── 99-cleanup.sh
├── lambda/
│   └── prd-design-bedrock-implementer/
│       ├── index.mjs                   # Bedrock呼び出し + GitHub Contents API + path validation
│       └── package.json
├── workflows/
│   └── prd-implementation-agent.workflow.json
├── iam/
│   ├── lambda-trust-policy.json
│   ├── implementer-policy.json
│   └── n8n-runtime-policy.json
└── templates/
    ├── prd-template-ja.md              # n8nのCode NodeからURL参照される
    └── design-doc-template-ja.md
```

## セキュリティ運用上の注意

- 全ての固有値（AWS Account ID, リージョン）は `${AWS_ACCOUNT_ID}` `${AWS_DEFAULT_REGION}` 形式でIAM JSONに書かれており、`scripts/01` の中で `envsubst` 置換してからputされる。リポジトリ内には実値は無い。
- `GITHUB_TOKEN` `PRD_AGENT_FORM_SECRET` は `.env` 経由でexportし、SSM投入後はシェル履歴から削除する。`set +o history` を併用するとさらに安全。
- workflow JSONに含まれる `__REPLACE_WITH_YOUR_*__` と `REPLACE_WITH_YOUR_DRIVE_FOLDER_ID` はn8nインポート時に各自が置換する。
- Lambdaの `validatePath()` は `.github/`, `.env*`, `Caddyfile`, `iam-*.json`, `*.pem`, `id_rsa*` などCI設定とシークレット系のパスへの書き込みを全て拒否する。Bedrockが攻撃的な計画を出してもこの層で遮断される。
- Lambdaの `SYSTEM_PROMPT` でも「破壊的変更や危険な操作は絶対にしない」「禁止パスを変更しない」を明記している。
- Form TriggerのShared Secretはtiming-safe compareで照合する（短絡比較によるサイドチャネル防止）。
- Bedrock呼び出しはinference profile経由で、IAM Resourceは `ap-northeast-1` と `ap-northeast-3` の両方のfoundation-model ARNを許可する（JPプロファイルの大阪ルーティング対応）。

## 関連 Zenn 記事

- 記事1: n8nをAWSにセルフホストする
- 記事2: GuardDuty通知をn8n + Bedrockで要約するSecurity Agent
