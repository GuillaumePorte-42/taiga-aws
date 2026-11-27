# Journaux des conteneurs de Taiga en production (PFD-62, ADR-15)
# Les conteneurs y écrivent grâce au pilote « awslogs » de Docker, déclaré dans la stack.
resource "aws_cloudwatch_log_group" "taiga-production" {
  name              = "/taiga/production"
  retention_in_days = 7 # conservation courte : suffisant pour le diagnostic, et peu coûteux
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.taiga-production.name
}

