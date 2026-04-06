output "public_ip" {
  value = aws_eip.epicbook_eip.public_ip
}

output "admin_user" {
  value = "ubuntu"
}

output "rds_endpoint" {
  value = aws_db_instance.epicbook_rds.address
}

output "ssh_command" {
  value = "ssh -i epicbook-key.pem ubuntu@${aws_eip.epicbook_eip.public_ip}"
}

output "app_url" {
  value = "http://${aws_eip.epicbook_eip.public_ip}"
}
