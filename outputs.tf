output "instance_id" {
  description = "EC2 インスタンス ID"
  value       = aws_instance.this.id
}

output "public_ip" {
  description = "固定外部 IP（Elastic IP）"
  value       = aws_eip.this.public_ip
}

output "ssm_session_command" {
  description = "SSM Session Manager で接続するコマンド（ポート開放不要）"
  value       = "aws ssm start-session --target ${aws_instance.this.id} --region ${var.region}"
}

output "ssh_command" {
  description = "SSH 接続コマンド（enable_ssh_ingress=true かつ鍵設定時のみ有効）"
  value = var.ssh_public_key != "" ? (
    "ssh -i <your-key.pem> ubuntu@${aws_eip.this.public_ip}"
  ) : "n/a (ssh_public_key 未設定)"
}
