# Inscrit l'instance staging dans le target group de l'ALB, sur le port 9000 de la machine
resource "aws_lb_target_group_attachment" "staging" {
  for_each = aws_instance.main

  target_group_arn = data.aws_lb_target_group.staging.arn
  target_id        = each.value.id
  port             = 9000
}