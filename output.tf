output "db_endpoint" {
  description = "The DNS endpoint address for the primary RDS instance."
  # References the address attribute of the 'primary' resource
  value       = aws_db_instance.primary.address
}

output "db_name" {
  description = "The initial database name created on the RDS instance."
  # References the db_name attribute of the 'primary' resource
  value       = aws_db_instance.primary.db_name
}

output "db_username" {
  description = "The master username for the RDS instance."
  value       = aws_db_instance.primary.username
}

output "internal_lb_dns" {
  description = "internal lb dns"
  value = aws_lb.app_tier_internal_lb.dns_name
}

output "external_lb_dns" {
  description = "external lb dns"
  value = aws_lb.web_tier_internet_lb.dns_name
}

output "public_ip" {
  description = "web app public ip"
  value = aws_instance.web_tier.public_ip
}