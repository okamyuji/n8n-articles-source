# n8n Self-Host on AWS (EC2 + KMS + SSM + Cloudflare DNS)

Zenn記事「機密情報をディスクに残さないでn8nセルフホストをAWSで構築する」の再現アセットです。EC2(t4g.small) + Docker Compose(n8n + PostgreSQL + Caddy)をCloudflare DNSとLet's Encrypt自動TLSで組み合わせ、機密情報はEC2のディスクに一切平文で置かず、起動のたびにSSM Parameter Storeからtmpfsに展開する設計を再現します。

## 全体像

```
Cloudflare DNS (grey cloud A record)
  └─> Elastic IP
        └─> EC2 (t4g.small, Ubuntu 24.04 ARM64)
              ├─> Instance Profile -> n8n-instance-role
              │      ├─ ssm:GetParametersByPath /n8n/prod
              │      └─ kms:Decrypt alias/n8n-secrets
              ├─> systemd: n8n-secrets.service
              │      └─ tmpfs /run/n8n-secrets/.env
              └─> systemd: docker-n8n.service
                     └─> docker compose up -d
                           ├─ caddy   :80/:443 (Let's Encrypt HTTP-01)
                           ├─ n8n     :5678
                           └─ postgres:5432
```

## 前提

- AWSアカウント（ルートMFA済み）と管理者IAMユーザー（本記事では `n8n-admin`）
- Cloudflareに対象ドメインのネームサーバーを移譲済み
- `aws` v2, `jq`, `openssl`, `ssh`, `gettext` (`envsubst`)
- Cloudflareダッシュボードを操作できる権限

## 手順

```sh
# 1. 環境変数を読み込む
cp .env.example .env
$EDITOR .env
set -a; source .env; set +a

# 2. KMS Key + SSM パラメータ投入（暗号化キー / DBパスワードはローカル生成）
bash scripts/01-prepare-kms-ssm.sh
# 出力された KMS_KEY_ID をシェルへ export してから次へ
export KMS_KEY_ID=<above>

# 3. EC2インスタンスロール + インスタンスプロファイル
bash scripts/02-prepare-iam.sh

# 4. セキュリティグループ + SSHキーペア
bash scripts/03-network-keypair.sh
export SG_ID=<above>

# 5. EC2起動（user-dataにec2/bootstrap.sh）
bash scripts/04-launch-ec2.sh
export INSTANCE_ID=<above>

# 6. Elastic IP割当
bash scripts/05-allocate-eip.sh
# PUBLIC_IPが表示されるのでCloudflareに Aレコード(grey cloud)で登録

# 7. digで伝播確認 → ブラウザで https://${N8N_DOMAIN} にアクセス
dig +short "$N8N_DOMAIN"

# 8. n8nのOwner アカウント作成 → 即時 2FA + USER_MANAGEMENT_DISABLED=trueへ
```

## 再起動テスト

`sudo reboot` した後にも `https://${N8N_DOMAIN}` が復旧することを必ず確認してください。
- `systemctl status n8n-secrets.service docker-n8n.service`
- `mount | grep n8n-secrets` がtmpfsであること
- `sudo cat /run/n8n-secrets/.env` がメモリ上にしか存在しないこと

## ファイル構成

```
.
├── README.md
├── .env.example
├── scripts/
│   ├── 00-common.sh
│   ├── 01-prepare-kms-ssm.sh
│   ├── 02-prepare-iam.sh
│   ├── 03-network-keypair.sh
│   ├── 04-launch-ec2.sh
│   ├── 05-allocate-eip.sh
│   └── 99-cleanup.sh
├── ec2/
│   ├── bootstrap.sh                 # user-data本体（systemd unit / compose / Caddyfileをinline）
│   ├── load-secrets.sh              # SSM → tmpfsを毎起動時に再構築
│   ├── docker-compose.yml.template  # 同梱のcompose単独参照用
│   ├── Caddyfile.template
│   ├── n8n-secrets.service
│   ├── docker-n8n.service
│   └── cron/
│       ├── backup.sh                # 日次pg_dump → S3
│       └── update.sh                # 週次docker compose pull
└── iam/
    ├── n8n-ec2-trust-policy.json
    └── n8n-ec2-permission-policy.json
```

## セキュリティ運用上の注意

- `bootstrap.sh` はEC2のディスクに何も平文で残さない。docker composeのenv_fileは `/run/n8n-secrets/.env` (tmpfs)を指す。再起動するたびにSSMから再ロードされる。
- `iam/n8n-ec2-permission-policy.json` の `Resource` は `${AWS_ACCOUNT_ID}` `${AWS_DEFAULT_REGION}` `${KMS_KEY_ID}` を `envsubst` で置換してからputされる。リポジトリ内に固有値は無い。
- `ssm:GetParametersByPath` は `parameter/n8n/prod` 自身のARNにも権限が必要（非対称仕様）。ポリシーには `parameter/n8n/prod` と `parameter/n8n/prod/*` の両方を入れている。
- `cron/backup.sh` の `BACKUP_BUCKET_NAME` は環境変数経由のみ。シェルスクリプト内に書かない。
- SSH ingressは `MY_IP/32` のみ。`0.0.0.0/0` で開けない。長期運用ならSession Managerを併用。
- IMDSv2強制 (`HttpTokens=required`)、EBS暗号化、Dockerログサイズ上限10MB×3は全てユーザーデータ内で完結。
- `N8N_ENCRYPTION_KEY` を失うとn8nの全クレデンシャルが復号不能になる。SSMから外す前に必ず控えること。
