# Claude Code 稼働環境 (AWS EC2 / Ubuntu) — Terraform

Ubuntu 24.04 LTS の EC2 を東京リージョンに立て、起動時に Node.js(LTS) と
Claude Code を自動インストールする最小構成。

## この構成で作られるもの
- **VPC × 1**（新規） `claude-code-J32474-vpc`
- **パブリックサブネット × 1**（新規） `claude-code-J32474-subnet`
- IGW / ルートテーブル
- EC2（Ubuntu 24.04, t3.medium）
- **Elastic IP（外部IP固定）**
- SSM 接続用 IAM ロール / インスタンスプロファイル
- セキュリティグループ（アウトバウンドのみ許可、SSH 既定オフ）

## 構成の方針
- 接続は既定で **SSM Session Manager**（インバウンドポートを一切開けない）
- IMDSv2 強制・ルートボリューム暗号化・SSH 既定オフ
- VS Code Remote-SSH も **ポート開放なし**（SSM の ProxyCommand 経由）で利用可能
- 認証情報・トークンはコードに一切含めない（Claude Code の認証は手動）

## 前提
- Terraform >= 1.5 / AWS Provider ~> 5.0
- 接続に SSM を使う場合、ローカルに AWS CLI と Session Manager Plugin

## デプロイ
```bash
cp terraform.tfvars.example terraform.tfvars   # 必要に応じて編集
terraform init
terraform validate
terraform plan
terraform apply
```

## 接続方法

### A. SSM Session Manager（推奨・ポート開放不要）
```bash
aws ssm start-session --target <instance-id> --region ap-northeast-1
```
接続後:
```bash
sudo su - ubuntu
cd ~/your-project
claude          # 初回はブラウザ認証（下記）
```

### B. VS Code Remote-SSH（ポート開放なし・SSM 経由）
1. `terraform.tfvars` に `ssh_public_key` を設定して apply
2. ローカルの `~/.ssh/config`:
   ```
   Host claude-code-j32474
     HostName <instance-id>
     User ubuntu
     ProxyCommand sh -c "aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p --region ap-northeast-1"
   ```
3. VS Code の Remote-SSH で接続 → 統合ターミナルで `claude` を起動

### C. 直接 SSH（非推奨）
`enable_ssh_ingress = true` と `allowed_ssh_cidr = ["<自分のIP>/32"]` を設定。
接続先は Elastic IP（`terraform output public_ip`）。

## Claude Code の認証（手動・プロビジョニング後）
`claude` を起動するとログイン用 URL が表示されるので、手元の PC のブラウザで開いて
コードを貼り戻す。ヘッドレスな EC2 でもこの方式で認証できる。

**Team ライセンスでサブスク認証が使えるかは要確認**（プラン仕様は変わりうる）:
- プラン/シート/課金: https://support.claude.com
- インストール/認証の最新手順: https://docs.claude.com/en/docs/claude-code/overview

## 後片付け
```bash
terraform destroy
```

## 注意
- 開発用の単一インスタンス構成。本番用途では tfstate のリモート管理
  （S3 + DynamoDB ロック等）を検討すること。
- Elastic IP は割り当て中は課金対象。使わないときは destroy 推奨。
