# Les 8 security groups du tableau (description sans accents : AWS les refuse)
locals {
  security_groups = {
    alb        = "ALB : HTTPS et HTTP depuis Internet"
    bastion    = "Bastion : SSH depuis les IP de l equipe"
    nodes      = "Noeuds Swarm de prod"
    staging    = "Instance staging"
    rds        = "Base RDS PostgreSQL"
    efs        = "Stockage partage EFS"
    monitoring = "Instance de supervision"
    ci         = "Runner GitLab et SonarQube : SSH depuis le bastion"
  }
}

# Un security group par ligne, sans règle : les règles sont des ressources à part
resource "aws_security_group" "main" {
  for_each = local.security_groups

  name        = "taiga-sg-${each.key}"
  description = each.value
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "taiga-sg-${each.key}"
  }
}

# Matrice des flux entrants : qui (source) peut joindre quel SG, sur quel port
locals {
  regles_entree = {
    "alb-https" = { sg = "alb", port = 443, proto = "tcp", source = null, cidr = "0.0.0.0/0" }
    "alb-http"  = { sg = "alb", port = 80, proto = "tcp", source = null, cidr = "0.0.0.0/0" }

    "nodes-taiga"          = { sg = "nodes", port = 9000, proto = "tcp", source = "alb", cidr = null }
    "nodes-ssh-bastion"    = { sg = "nodes", port = 22, proto = "tcp", source = "bastion", cidr = null }
    "nodes-ssh-ci"         = { sg = "nodes", port = 22, proto = "tcp", source = "ci", cidr = null }
    "nodes-swarm-gestion"  = { sg = "nodes", port = 2377, proto = "tcp", source = "nodes", cidr = null }
    "nodes-swarm-tcp"      = { sg = "nodes", port = 7946, proto = "tcp", source = "nodes", cidr = null }
    "nodes-swarm-udp"      = { sg = "nodes", port = 7946, proto = "udp", source = "nodes", cidr = null }
    "nodes-swarm-overlay"  = { sg = "nodes", port = 4789, proto = "udp", source = "nodes", cidr = null }
    "nodes-metriques-9100" = { sg = "nodes", port = 9100, proto = "tcp", source = "monitoring", cidr = null }
    "nodes-metriques-8080" = { sg = "nodes", port = 8080, proto = "tcp", source = "monitoring", cidr = null }

    "staging-taiga"          = { sg = "staging", port = 9000, proto = "tcp", source = "alb", cidr = null }
    "staging-ssh-bastion"    = { sg = "staging", port = 22, proto = "tcp", source = "bastion", cidr = null }
    "staging-ssh-ci"         = { sg = "staging", port = 22, proto = "tcp", source = "ci", cidr = null }
    "staging-metriques-9100" = { sg = "staging", port = 9100, proto = "tcp", source = "monitoring", cidr = null }
    "staging-metriques-8080" = { sg = "staging", port = 8080, proto = "tcp", source = "monitoring", cidr = null }

    "rds-postgres-nodes"      = { sg = "rds", port = 5432, proto = "tcp", source = "nodes", cidr = null }
    "rds-postgres-monitoring" = { sg = "rds", port = 5432, proto = "tcp", source = "monitoring", cidr = null }

    "efs-nfs" = { sg = "efs", port = 2049, proto = "tcp", source = "nodes", cidr = null }

    "monitoring-ssh"         = { sg = "monitoring", port = 22, proto = "tcp", source = "bastion", cidr = null }
    "bastion-metriques-9100" = { sg = "bastion", port = 9100, proto = "tcp", source = "monitoring", cidr = null }

    "monitoring-ssh-ci" = { sg = "monitoring", port = 22, proto = "tcp", source = "ci", cidr = null }

    "ci-ssh-bastion"    = { sg = "ci", port = 22, proto = "tcp", source = "bastion", cidr = null }
    "ci-metriques-9100" = { sg = "ci", port = 9100, proto = "tcp", source = "monitoring", cidr = null }
  }
}

# Une règle d'entrée par ligne : source = un autre SG, ou une plage d'adresses (cidr)
resource "aws_vpc_security_group_ingress_rule" "main" {
  for_each = local.regles_entree

  security_group_id            = aws_security_group.main[each.value.sg].id
  ip_protocol                  = each.value.proto
  from_port                    = each.value.port
  to_port                      = each.value.port
  referenced_security_group_id = each.value.source == null ? null : aws_security_group.main[each.value.source].id
  cidr_ipv4                    = each.value.cidr

  tags = {
    Name = each.key
  }
}

# Sortie ouverte sur chaque SG, comme prévu (durcissement = piste d'amélioration)
resource "aws_vpc_security_group_egress_rule" "tout" {
  for_each = aws_security_group.main

  security_group_id = each.value.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# Liste des IP de l'équipe, lue dans Parameter Store (créée par le socle, remplie à la main : voir docs/runbooks/1-equipe/changer_son_ip.md)
data "aws_ssm_parameter" "ips_equipe" {
  name = "/taiga/reseau/ips_equipe"
}

# Une règle SSH sur le bastion par IP de l'équipe ("a/32,b/32" découpé en liste)
resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each = toset(split(",", data.aws_ssm_parameter.ips_equipe.insecure_value))

  security_group_id = aws_security_group.main["bastion"].id
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = each.value

  tags = {
    Name = "bastion-ssh-${each.value}"
  }
}

# ESP (protocole IP 50, sans port) entre les nœuds : le réseau overlay de Taiga est chiffré par Swarm avec IPsec
resource "aws_vpc_security_group_ingress_rule" "nodes_esp" {
  security_group_id            = aws_security_group.main["nodes"].id
  ip_protocol                  = "50"
  referenced_security_group_id = aws_security_group.main["nodes"].id

  tags = {
    Name = "nodes-swarm-esp"
  }
}