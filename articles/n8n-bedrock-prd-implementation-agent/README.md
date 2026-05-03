# n8n + Bedrock PRD/DesignDoc Implementation Agent

Zenn記事「n8n と Bedrock で PRD/DesignDoc から実装PRまで運ぶ Agent」の再現アセットです。Form 入力から Gemini で PRD/DesignDoc を生成して Google Drive に保存し、GitHub に PR ブランチを作って、AWS Bedrock (Claude Sonnet 4.6) で動く Lambda が実装パッチを生成して同 PR にコミットし、最後に PR コメントへ自動実装サマリを投稿する構成です。

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

- 記事1の n8n self-host が稼働済み
- 記事2の `n8n-runtime-user` IAM ユーザーが存在（無ければ scripts/03 が新規作成）
- AWS CLI v2 と Node.js 24.x がローカルにある
- GitHub Personal Access Token（`repo` + `pull-requests` スコープ）
- Google Cloud Console で Drive API と Generative Language (Gemini) API のクレデンシャル発行済み
- Form 経由で実装依頼する権限を持つ人に渡す Shared Secret

## 手順

```sh
# 1. 環境変数を読み込む
cp .env.example .env
$EDITOR .env
set -a; source .env; set +a

# 2. IAM Role/Policy + GitHub Token を SSM へ
bash scripts/01-prepare-iam-and-ssm.sh

# 3. Lambda をビルド + デプロイ
bash scripts/02-deploy-implementer-lambda.sh

# 4. n8n 用 IAM ユーザーへ Lambda Invoke 権限を付与
bash scripts/03-create-n8n-runtime-user.sh

# 5. PRD_AGENT_FORM_SECRET を n8n コンテナへ手動で投入（指示を表示）
bash scripts/04-set-form-secret.sh

# 6. n8n の Web UI に workflows/prd-implementation-agent.workflow.json をインポート
#    インポート後、各ノードの credential を自分のものに張り替える
#    - Generate PRD and DesignDoc: Google Gemini (PaLM) Api
#    - Get Base Branch Ref / Create GitHub Branch / Commit DesignDoc / Create GitHub PR
#      / Post Implementation Summary: GitHub account
#    - Upload PRD / DesignDoc as HTML: Google Drive OAuth2 Api
#    - Invoke Bedrock Implementer: AWS (article 2 と同じ n8n-runtime-user のキー)
#
#    また workflow JSON 内に `REPLACE_WITH_YOUR_DRIVE_FOLDER_ID` のプレースホルダがあるので
#    自分の Drive folder ID に置換してから Activate する。
#    Form Trigger の webhookId と versionId は n8n インポート時に再生成される。
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
│       ├── index.mjs                   # Bedrock 呼び出し + GitHub Contents API + path validation
│       └── package.json
├── workflows/
│   └── prd-implementation-agent.workflow.json
├── iam/
│   ├── lambda-trust-policy.json
│   ├── implementer-policy.json
│   └── n8n-runtime-policy.json
└── templates/
    ├── prd-template-ja.md              # n8n の Code Node からURL参照される
    └── design-doc-template-ja.md
```

## セキュリティ運用上の注意

- 全ての固有値（AWS Account ID, リージョン）は `${AWS_ACCOUNT_ID}` `${AWS_DEFAULT_REGION}` 形式で IAM JSON に書かれており、`scripts/01` の中で `envsubst` 置換してから put される。リポジトリ内には実値は無い。
- `GITHUB_TOKEN` `PRD_AGENT_FORM_SECRET` は `.env` 経由で export し、SSM 投入後はシェル履歴から削除する。`set +o history` を併用するとさらに安全。
- workflow JSON に含まれる `__REPLACE_WITH_YOUR_*__` と `REPLACE_WITH_YOUR_DRIVE_FOLDER_ID` は n8n インポート時に各自が置換する。
- Lambda の `validatePath()` は `.github/`, `.env*`, `Caddyfile`, `iam-*.json`, `*.pem`, `id_rsa*` など CI 設定とシークレット系のパスへの書き込みを全て拒否する。Bedrock が攻撃的な計画を出してもこの層で遮断される。
- Lambda の `SYSTEM_PROMPT` でも「破壊的変更や危険な操作は絶対にしない」「禁止パスを変更しない」を明記している。
- Form Trigger の Shared Secret は timing-safe compare で照合する（短絡比較によるサイドチャネル防止）。
- Bedrock 呼び出しは inference profile 経由で、IAM Resource は `ap-northeast-1` と `ap-northeast-3` の両方の foundation-model ARN を許可する（JP プロファイルの大阪ルーティング対応）。

## 関連 Zenn 記事

- 記事1: n8n を AWS にセルフホストする
- 記事2: GuardDuty 通知を n8n + Bedrock で要約する Security Agent
