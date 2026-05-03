# n8n-articles-source

Zennで公開しているn8n関連3記事の再現可能なソースアーカイブです。各記事ディレクトリには、aws-cliを段階的に流すための `scripts/`、Lambda関数の `lambda/`、n8nの `workflows/`、IAMポリシーの `iam/` などを配置しています。読者が `.env` を作成して環境変数をexportし、`scripts/01-...sh` から順番に実行することで、記事と同じ構成を自分のAWSアカウントに再構築できる粒度に揃えています。

## 対応記事

| ディレクトリ | Zenn記事 |
|---|---|
| [articles/n8n-aws-cloudflare-selfhost/](https://zenn.dev/okamyuji/articles/n8n-aws-cloudflare-selfhost) | n8nをAWS にセルフホストする |
| [articles/n8n-aws-security-agent/](https://zenn.dev/okamyuji/articles/n8n-aws-security-agent) | GuardDuty通知をn8n + Bedrockで要約するSecurity Agent |
| [articles/n8n-bedrock-prd-implementation-agent/](https://zenn.dev/okamyuji/articles/n8n-bedrock-prd-implementation-agent) | n8nとBedrockでPRD/DesignDocから実装PRまで運ぶ Agent |

## セキュリティ方針

- リポジトリ内のスクリプトとworkflow JSONには、AWS Account ID、IAMユーザー名、EC2のパブリックIP、ドメイン、Slack Webhook URL、API Keyなどの実値を一切含めません。すべて `${VAR}` 形式の環境変数参照、または `<your-...>` 形式のプレースホルダにしています。
- 機密情報は読み手が自分のターミナルで `export` して読み捨てる運用を前提にしており、SSM Parameter StoreのSecureStringに投入するスクリプトのみリポジトリに含めています。
- ローカルではpre-commit + gitleaks、CIではGitHub Actions + gitleaksの二重で秘密混入を遮断しています。

## セットアップ

```sh
# 1. clone
git clone git@github.com:okamyuji/n8n-articles-source.git
cd n8n-articles-source

# 2. pre-commitを有効化
pip install --user pre-commit  # 未導入の場合
pre-commit install

# 3. 共通環境変数を設定
cp .env.example .env
$EDITOR .env
set -a; source .env; set +a

# 4. 興味のある記事ディレクトリへ
cd articles/n8n-aws-security-agent
cat README.md
```

各記事ディレクトリには独自の `.env.example` と `README.md` があります。記事固有の環境変数はそちらで上書きしてください。

## ディレクトリ構成

```
.
├── .env.example                  # 共通環境変数のテンプレート
├── .github/workflows/gitleaks.yml
├── .gitleaks.toml
├── .pre-commit-config.yaml
└── articles/
    ├── n8n-aws-cloudflare-selfhost/
    ├── n8n-aws-security-agent/
    └── n8n-bedrock-prd-implementation-agent/
```

## 動作確認している前提

- macOS / Linux のシェル
- AWS CLI v2
- GitHub CLI (`gh`)
- Docker （ローカルでgitleaksを直接走らせる場合のみ）
- Python 3.x （pre-commitのインストール用）
- Node.js 24.x （Lambdaの構文チェック用）

## ライセンス

個人運用のprivateリポジトリです。記事本文の権利はokamyujiが保持します。

## 関連メモ

- 記事の本文そのものはZenn側に置いてあります。このリポジトリには再現に必要な「実行可能アセット」のみを置いています。
