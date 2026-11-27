# ID du VPC, lu par staging/ et production/
output "vpc_id" {
  value = aws_vpc.main.id
}

# ID de chaque sous-réseau, par nom (ex. subnet_ids["staging-c"])
output "subnet_ids" {
  value = { for nom, sr in aws_subnet.main : nom => sr.id }
}

# ID de chaque security group, par nom (ex. security_group_ids["nodes"])
output "security_group_ids" {
  value = { for nom, sg in aws_security_group.main : nom => sg.id }
}
