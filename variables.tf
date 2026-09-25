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

# --- 初期セットアップ（user_data）用 ---------------------------------------
variable "node_version" {
  description = "nvm でインストールする Node.js のバージョン指定（例: lts/*, 22, 20.11.0）"
  type        = string
  default     = "lts/*"
}

variable "nvm_version" {
  description = "導入する nvm のバージョンタグ"
  type        = string
  default     = "v0.40.1"
}

variable "timezone" {
  description = "インスタンスのタイムゾーン"
  type        = string
  default     = "Asia/Tokyo"
}

variable "instance_environment" {
  description = <<-EOT
    インスタンスに永続設定する環境変数のマップ。
    /etc/profile.d/claude-code-env.sh に書き出され、ログインシェルで有効になる。
    ★機密情報（API キー・トークン等）は絶対に入れないこと（user_data はメタデータ経由で参照され得るため）。
  EOT
  type        = map(string)
  default = {
    TZ = "Asia/Tokyo"
  }
}

# --- 自動停止スケジュール ---------------------------------------------------
variable "enable_auto_stop" {
  description = "EventBridge Scheduler による EC2 の自動停止を有効にするか"
  type        = bool
  default     = true
}

variable "auto_stop_schedule" {
  description = <<-EOT
    自動停止のスケジュール式（cron または rate）。
    既定は毎日 22:00（auto_stop_timezone のタイムゾーン基準）。
    cron の書式は cron(分 時 日 月 曜日 年) で、日と曜日のどちらかは ? にする。
  EOT
  type        = string
  default     = "cron(0 22 * * ? *)"
}

variable "auto_stop_timezone" {
  description = "auto_stop_schedule を解釈するタイムゾーン"
  type        = string
  default     = "Asia/Tokyo"
}

# --- 自動起動スケジュール（現在は無効） -------------------------------------
# main.tf の「自動起動」ブロックと合わせてコメントを外すと有効になる。
#
# variable "enable_auto_start" {
#   description = "EventBridge Scheduler による EC2 の自動起動を有効にするか"
#   type        = bool
#   default     = true
# }
#
# variable "auto_start_schedule" {
#   description = <<-EOT
#     自動起動のスケジュール式（cron または rate）。
#     既定は平日 09:00（auto_start_timezone のタイムゾーン基準）。
#     土日も起動したい場合は "cron(0 9 * * ? *)" にする。
#   EOT
#   type        = string
#   default     = "cron(0 9 ? * MON-FRI *)"
# }
#
# variable "auto_start_timezone" {
#   description = "auto_start_schedule を解釈するタイムゾーン"
#   type        = string
#   default     = "Asia/Tokyo"
# }
