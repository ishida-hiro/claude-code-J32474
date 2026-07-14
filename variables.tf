variable "region" {
  description = "デプロイ先の AWS リージョン（東京）"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "リソース名のプレフィックス（J32474 を含む）"
  type        = string
  default     = "claude-code-J32474"
}

variable "environment" {
  description = "環境タグ (dev / stg / prod)"
  type        = string
  default     = "dev"
}

variable "instance_type" {
  description = "EC2 インスタンスタイプ。Claude Code 自体は軽量なので t3.medium 程度で十分"
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size" {
  description = "ルートボリュームサイズ (GiB)"
  type        = number
  default     = 30
}

variable "vpc_cidr" {
  description = "新規作成する VPC の CIDR"
  type        = string
  default     = "10.20.0.0/16"
}

variable "subnet_cidr" {
  description = "新規作成するパブリックサブネットの CIDR"
  type        = string
  default     = "10.20.1.0/24"
}

# --- 接続方式 ---------------------------------------------------------------
# 既定では SSH ポートを開けず、SSM Session Manager で接続する構成。
# VS Code Remote-SSH をポート開放なしで使う場合は SSM の ProxyCommand 経由が可能
# （README 参照）。その場合は ssh_public_key を設定する。

variable "enable_ssh_ingress" {
  description = "インバウンド SSH(22) を開けるか。可能な限り false のまま SSM を使うこと"
  type        = bool
  default     = false
}

variable "allowed_ssh_cidr" {
  description = "enable_ssh_ingress=true のとき SSH を許可する CIDR。自分の IP を /32 で指定する"
  type        = list(string)
  default     = []
}

variable "ssh_public_key" {
  description = "SSH 鍵ペアに登録する公開鍵。空文字なら鍵ペアを作成しない"
  type        = string
  default     = ""
}
