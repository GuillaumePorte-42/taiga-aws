# Récupération automatique de l'ID du compte AWS courant
data "aws_caller_identity" "current" {}

locals {
  # Déclaration des environments
  environments = ["staging", "production"]

  # Dictionnaire des secrets avec leurs longueurs spécifiques
  generated_secrets = {
    postgres_password      = 32
    secret_key             = 50
    rabbitmq_pass          = 32
    rabbitmq_erlang_cookie = 32
  }

  # Création de la matrice (environnement x secret) incluant la longueur
  secret_pairs = flatten([
    for env in local.environments : [
      for secret_name, secret_length in local.generated_secrets : {
        env    = env
        name   = secret_name
        length = secret_length
        key    = "${env}-${secret_name}"
      }
    ]
  ])

  secret_map = { for item in local.secret_pairs : item.key => item }
}

# 1. Génération des 8 mots de passe aléatoires (avec longueurs variables)
resource "random_password" "secrets" {
  for_each = local.secret_map

  length  = each.value.length
  special = false
}

# 2. Stockage des 8 secrets générés dans AWS Parameter Store (SSM)
resource "aws_ssm_parameter" "generated_secrets" {
  for_each = local.secret_map

  name  = "/taiga/${each.value.env}/${each.value.name}"
  type  = "SecureString"
  value = random_password.secrets[each.key].result

  # Option : Ajout des tags pour le suivi
  tags = {
    Project = "taiga"
    Env     = each.value.env
  }
}

# 3. Mot de passe SMTP de SES (déduit de la clé de l'utilisateur taiga-ses-smtp, voir ses.tf), pour les deux environnements
resource "aws_ssm_parameter" "email_host_password" {
  for_each = toset(local.environments)

  name  = "/taiga/${each.key}/email_host_password"
  type  = "SecureString"
  value = aws_iam_access_key.ses_smtp.ses_smtp_password_v4

  tags = {
    Project = "taiga"
    Env     = each.key
  }
}


# 3 bis. Identifiant SMTP de SES (l'ID de la clé d'accès), pour les deux environnements
resource "aws_ssm_parameter" "email_host_user" {
  for_each = toset(local.environments)

  name  = "/taiga/${each.key}/email_host_user"
  type  = "SecureString"
  value = aws_iam_access_key.ses_smtp.id

  tags = {
    Project = "taiga"
    Env     = each.key
  }
}

# 4. Politique IAM : lecture des secrets /taiga/* (tous les environnements)
resource "aws_iam_policy" "taiga_read_secrets" {
  name        = "taiga-lecture-secrets"
  description = "Permet la lecture des parametres SSM sous /taiga/*"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        # Restriction stricte au compte courant et à la région eu-west-3
        Resource = "arn:aws:ssm:eu-west-3:${data.aws_caller_identity.current.account_id}:parameter/taiga/*"
      }
    ]
  })
}

# 5. IP publiques de l'équipe (format "1.2.3.4/32", séparées par des virgules), autorisées en SSH sur le bastion ; valeur saisie à la main
resource "aws_ssm_parameter" "ips_equipe" {
  name  = "/taiga/reseau/ips_equipe"
  type  = "StringList"
  value = "A_REMPLIR"

  lifecycle {
    ignore_changes = [value]
  }

  tags = {
    Project = "taiga"
    Env     = "reseau"
  }
}

# 6. Mot de passe administrateur de Grafana (supervision, commune aux deux environnements)
resource "random_password" "grafana_admin" {
  length  = 32
  special = false
}

resource "aws_ssm_parameter" "grafana_admin_password" {
  name  = "/taiga/admin/grafana_admin_password"
  type  = "SecureString"
  value = random_password.grafana_admin.result

  tags = {
    Project = "taiga"
    Env     = "admin"
  }
}

# Output de l'ARN de la politique IAM
output "taiga_read_secrets_policy_arn" {
  value       = aws_iam_policy.taiga_read_secrets.arn
  description = "ARN de la politique IAM de lecture des secrets"
}
# 7. Mot de passe de l'utilisateur PostgreSQL « monitoring » (lecture des statistiques, PFD-34)
resource "random_password" "postgres_monitoring" {
  length  = 32
  special = false
}

resource "aws_ssm_parameter" "postgres_monitoring_password" {
  name  = "/taiga/production/postgres_monitoring_password"
  type  = "SecureString"
  value = random_password.postgres_monitoring.result

  tags = {
    Project = "taiga"
    Env     = "production"
  }
}

# 8. Mot de passe du super-utilisateur du staging (le compte est recréé par Ansible après chaque reconstruction)
resource "random_password" "staging_admin" {
  length  = 32
  special = false
}

resource "aws_ssm_parameter" "staging_admin_password" {
  name  = "/taiga/staging/admin_password"
  type  = "SecureString"
  value = random_password.staging_admin.result

  tags = {
    Project = "taiga"
    Env     = "staging"
  }
}


# 9. Mot de passe du compte e2e-test du staging (tests E2E et de charge de la CI)
resource "random_password" "staging_e2e" {
  length  = 32
  special = false
}

# Le paramètre existait déjà (créé à la main le 02/11) : on garde sa valeur actuelle ; sur un nouveau compte AWS, il prendra le mot de passe aléatoire
resource "aws_ssm_parameter" "staging_e2e_password" {
  name  = "/taiga/staging/e2e_password"
  type  = "SecureString"
  value = random_password.staging_e2e.result

  lifecycle {
    ignore_changes = [value]
  }

  tags = {
    Project = "taiga"
    Env     = "staging"
  }
}