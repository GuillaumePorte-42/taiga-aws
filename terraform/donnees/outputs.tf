# Adresse DNS de la base, à donner à taiga-back (POSTGRES_HOST) et à postgres_exporter
# Toujours utiliser ce nom, jamais une IP : il suit le principal après une bascule Multi-AZ
output "rds_address" {
  value = aws_db_instance.main.address
}

# Port PostgreSQL de la base
output "rds_port" {
  value = aws_db_instance.main.port
}