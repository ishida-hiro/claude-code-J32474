locals {
  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

#############################################
# Data sources
#############################################
data "aws_availability_zones" "available" {
  state = "available"
}

# Ubuntu 24.04 LTS (Noble, amd64) の最新公式 AMI（Canonical）
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

#############################################
# Networking（VPC・サブネットを 1 個ずつ新規作成）
#############################################
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = "${var.project_name}-vpc" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.project_name}-igw" })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(local.tags, { Name = "${var.project_name}-subnet" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.tags, { Name = "${var.project_name}-rt" })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

#############################################
# Security Group
#############################################
resource "aws_security_group" "this" {
  name        = "${var.project_name}-sg"
  description = "SG for Claude Code dev EC2"
  vpc_id      = aws_vpc.this.id

  # アウトバウンドは npm / GitHub / Anthropic OAuth・API 用に許可
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${var.project_name}-sg" })
}

# インバウンド SSH（既定は無効。SSM を使うため）
resource "aws_security_group_rule" "ssh" {
  count             = var.enable_ssh_ingress ? 1 : 0
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.allowed_ssh_cidr
  security_group_id = aws_security_group.this.id
  description       = "SSH from allowed CIDRs only"
}

#############################################
# IAM（SSM Session Manager 用）
#############################################
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.project_name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = local.tags
}

# ポート開放なしで接続するための SSM 権限
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.project_name}-profile"
  role = aws_iam_role.this.name
  tags = local.tags
}

#############################################
# Key pair (optional)
#############################################
resource "aws_key_pair" "this" {
  count      = var.ssh_public_key != "" ? 1 : 0
  key_name   = "${var.project_name}-key"
  public_key = var.ssh_public_key
  tags       = local.tags
}

#############################################
# EC2 instance (Ubuntu)
#############################################
resource "aws_instance" "this" {
  # 既存インスタンスを作り直さないため AMI は変数で固定する。
  # data.aws_ami.ubuntu は most_recent = true なので、Canonical が新しいイメージを
  # 公開するたびに ID が変わり、ami は変更不可属性のため destroy/create になる。
  ami                    = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.this.id]
  iam_instance_profile   = aws_iam_instance_profile.this.name
  key_name               = var.ssh_public_key != "" ? aws_key_pair.this[0].key_name : null

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    node_version = var.node_version
    nvm_version  = var.nvm_version
    timezone     = var.timezone
    env_vars     = var.instance_environment
  })
  # true だと user_data の差分でインスタンスが作り直される。初期セットアップは
  # 適用済みで、ルート EBS 上の環境を失いたくないため false にしている。
  # user_data を変更しても既存インスタンスには反映されない（再作成時のみ有効）。
  user_data_replace_on_change = false

  # IMDSv2 を強制（設定ドリフト・SSRF 対策）
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(local.tags, { Name = "${var.project_name}-ec2" })

  # 作り直し防止の二重の歯止め。ami_id の固定を外してしまった場合でも、稼働中の
  # インスタンスが AMI の更新で置き換わることはない。
  # OS イメージを入れ替えたいときは、この ignore_changes を一時的に外すか、
  # 新しいインスタンスを別途作って移行すること。
  lifecycle {
    ignore_changes = [ami]
  }
}

#############################################
# Elastic IP（外部IP固定）
#############################################
resource "aws_eip" "this" {
  instance = aws_instance.this.id
  domain   = "vpc"

  tags = merge(local.tags, { Name = "${var.project_name}-eip" })
}

#############################################
# 自動停止（EventBridge Scheduler → EC2 StopInstances）
#############################################
data "aws_iam_policy_document" "scheduler_assume" {
  count = var.enable_auto_stop ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "auto_stop" {
  count              = var.enable_auto_stop ? 1 : 0
  name               = "${var.project_name}-auto-stop-role"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume[0].json
  tags               = local.tags
}

# 対象インスタンスの停止のみを許可（最小権限）
data "aws_iam_policy_document" "auto_stop" {
  count = var.enable_auto_stop ? 1 : 0

  statement {
    actions   = ["ec2:StopInstances"]
    resources = [aws_instance.this.arn]
  }
}

resource "aws_iam_role_policy" "auto_stop" {
  count  = var.enable_auto_stop ? 1 : 0
  name   = "${var.project_name}-auto-stop"
  role   = aws_iam_role.auto_stop[0].id
  policy = data.aws_iam_policy_document.auto_stop[0].json
}

resource "aws_scheduler_schedule" "auto_stop" {
  count       = var.enable_auto_stop ? 1 : 0
  name        = "${var.project_name}-auto-stop"
  description = "毎日 ${var.auto_stop_timezone} の指定時刻に EC2 を停止する"
  group_name  = "default"

  schedule_expression          = var.auto_stop_schedule
  schedule_expression_timezone = var.auto_stop_timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:stopInstances"
    role_arn = aws_iam_role.auto_stop[0].arn

    input = jsonencode({
      InstanceIds = [aws_instance.this.id]
    })

    retry_policy {
      maximum_retry_attempts = 3
    }
  }
}

#############################################
# 自動起動（EventBridge Scheduler → EC2 StartInstances）
#############################################
# ★現在は無効（コメントアウト）。有効にするときは次の 3 か所のコメントを外す:
#   1. この下のブロック（main.tf）
#   2. variables.tf の「自動起動スケジュール」セクション
#   3. outputs.tf の auto_start_schedule
# 既定は平日 09:00 (Asia/Tokyo) 起動。停止側と同じく EC2 API を直接呼ぶ。
# 有効化して push すると HCP Terraform の run が走り、毎朝インスタンスが起動して
# 22:00 の自動停止まで課金が続く点に注意。
#
# data "aws_iam_policy_document" "auto_start_assume" {
#   count = var.enable_auto_start ? 1 : 0
#
#   statement {
#     actions = ["sts:AssumeRole"]
#     principals {
#       type        = "Service"
#       identifiers = ["scheduler.amazonaws.com"]
#     }
#   }
# }
#
# resource "aws_iam_role" "auto_start" {
#   count              = var.enable_auto_start ? 1 : 0
#   name               = "${var.project_name}-auto-start-role"
#   assume_role_policy = data.aws_iam_policy_document.auto_start_assume[0].json
#   tags               = local.tags
# }
#
# # 対象インスタンスの起動のみを許可（最小権限）
# data "aws_iam_policy_document" "auto_start" {
#   count = var.enable_auto_start ? 1 : 0
#
#   statement {
#     actions   = ["ec2:StartInstances"]
#     resources = [aws_instance.this.arn]
#   }
# }
#
# resource "aws_iam_role_policy" "auto_start" {
#   count  = var.enable_auto_start ? 1 : 0
#   name   = "${var.project_name}-auto-start"
#   role   = aws_iam_role.auto_start[0].id
#   policy = data.aws_iam_policy_document.auto_start[0].json
# }
#
# resource "aws_scheduler_schedule" "auto_start" {
#   count       = var.enable_auto_start ? 1 : 0
#   name        = "${var.project_name}-auto-start"
#   description = "${var.auto_start_timezone} の指定時刻に EC2 を起動する"
#   group_name  = "default"
#
#   schedule_expression          = var.auto_start_schedule
#   schedule_expression_timezone = var.auto_start_timezone
#
#   flexible_time_window {
#     mode = "OFF"
#   }
#
#   target {
#     arn      = "arn:aws:scheduler:::aws-sdk:ec2:startInstances"
#     role_arn = aws_iam_role.auto_start[0].arn
#
#     input = jsonencode({
#       InstanceIds = [aws_instance.this.id]
#     })
#
#     retry_policy {
#       maximum_retry_attempts = 3
#     }
#   }
# }
