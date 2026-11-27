# =============================================================================
# commun/alb.tf — répartiteur de charge public, partagé par staging et production
# =============================================================================

# L'ALB : seul point d'entrée web, dans les 3 sous-réseaux publics
resource "aws_lb" "taiga" {
  name               = "taiga-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [local.sgs["alb"]]
  subnets            = [local.subnets["public-a"], local.subnets["public-b"], local.subnets["public-c"]]

  # Refuse les requêtes aux en-têtes HTTP mal formés (protection contre certaines attaques)
  drop_invalid_header_fields = true
}

# Port 80 : tout est redirigé vers HTTPS (redirection permanente)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.taiga.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# Port 443 : HTTPS avec notre certificat ; un nom inconnu reçoit une 404
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.taiga.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.taiga.certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Site inconnu"
      status_code  = "404"
    }
  }
}

# Un target group par environnement : la liste des machines qui reçoivent le trafic, sur le port 9000
resource "aws_lb_target_group" "taiga" {
  for_each = toset(["staging", "production"])

  name     = "taiga-tg-${each.key}"
  port     = 9000
  protocol = "HTTP"
  vpc_id   = data.terraform_remote_state.reseau.outputs.vpc_id

  # L'ALB demande "/" toutes les 30 s ; 2 réponses 200 de suite = machine en service
  health_check {
    path                = "/"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}


# IP de l'équipe, déjà utilisées pour le bastion (format "1.2.3.4/32,5.6.7.8/32")
data "aws_ssm_parameter" "ips_equipe" {
  name = "/taiga/reseau/ips_equipe"
}

# Règle 10 : staging, depuis une IP de l'équipe → machines du staging
resource "aws_lb_listener_rule" "staging_equipe" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  condition {
    host_header {
      values = ["staging.taiga-ledevagilles.fr"]
    }
  }
  condition {
    source_ip {
      values = split(",", data.aws_ssm_parameter.ips_equipe.insecure_value)
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.taiga["staging"].arn
  }
}

# Règle 20 : staging, depuis toute autre IP → accès refusé
resource "aws_lb_listener_rule" "staging_refus" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 20

  condition {
    host_header {
      values = ["staging.taiga-ledevagilles.fr"]
    }
  }

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Accès réservé à l'équipe"
      status_code  = "403"
    }
  }
}

# Règle 30 : le domaine principal → machines de production
resource "aws_lb_listener_rule" "production" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 30

  condition {
    host_header {
      values = ["taiga-ledevagilles.fr"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.taiga["production"].arn
  }
}

# IP publique de la NAT (créée par reseau/, détruite le soir avec la NAT : relue ici à chaque apply du matin) : adresse de sortie de la CI et de la supervision
data "aws_eip" "nat" {
  tags = {
    Name = "taiga-nat-eip"
  }
}

# Règle 11 : staging, depuis la NAT (la CI, dans le VPC) → machines du staging
resource "aws_lb_listener_rule" "staging_ci" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 11

  condition {
    host_header {
      values = ["staging.taiga-ledevagilles.fr"]
    }
  }
  condition {
    source_ip {
      values = ["${data.aws_eip.nat.public_ip}/32"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.taiga["staging"].arn
  }
}
