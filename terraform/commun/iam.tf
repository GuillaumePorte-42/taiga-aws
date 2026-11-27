# =============================================================================
# commun/iam.tf — PFD-17
# Trois rôles, en moindre privilège :
#  - base       : envoyer les journaux des conteneurs vers CloudWatch (bastion, supervision, staging)
#  - production : base + déposer et relire les sauvegardes (postgres/, media/), jamais supprimer
#  - ci         : base + lire les secrets /taiga/* + lister les instances (inventaire Ansible)
# Aucune clé d'accès AWS n'est stockée sur les instances.
# =============================================================================

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "journaux" {
  statement {
    sid = "JournauxDesConteneurs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["arn:aws:logs:eu-west-3:*:log-group:/taiga/*"]
  }
}

data "aws_iam_policy_document" "inventaire" {
  statement {
    sid       = "InventaireDynamiqueAnsible"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"] # cette action ne se restreint pas par ressource
  }
}

# Sauvegardes de la production : déposer et relire dans postgres/ et media/, jamais supprimer
data "aws_iam_policy_document" "sauvegardes" {
  # Lister le contenu du bucket, mais seulement sous les deux préfixes
  statement {
    sid       = "ListerLesSauvegardes"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${local.bucket_sauvegardes}"]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["postgres/*", "media/*"]
    }
  }
  # Déposer et relire les fichiers des deux préfixes (pas de Delete : refusé par défaut)
  statement {
    sid     = "DeposerEtRelire"
    actions = ["s3:PutObject", "s3:GetObject"]
    resources = [
      "arn:aws:s3:::${local.bucket_sauvegardes}/postgres/*",
      "arn:aws:s3:::${local.bucket_sauvegardes}/media/*",
    ]
  }
}

resource "aws_iam_policy" "journaux" {
  name   = "taiga-ec2-journaux"
  policy = data.aws_iam_policy_document.journaux.json
}

resource "aws_iam_policy" "inventaire" {
  name   = "taiga-ci-inventaire"
  policy = data.aws_iam_policy_document.inventaire.json
}

# Politique des sauvegardes de la production (document "sauvegardes" plus haut)
resource "aws_iam_policy" "sauvegardes" {
  name   = "taiga-ec2-sauvegardes"
  policy = data.aws_iam_policy_document.sauvegardes.json
}

# --- Rôle de base (aussi utilisé par staging/) --------------------------------
resource "aws_iam_role" "base" {
  name               = "taiga-ec2-base"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "base_journaux" {
  role       = aws_iam_role.base.name
  policy_arn = aws_iam_policy.journaux.arn
}

resource "aws_iam_instance_profile" "base" {
  name = "taiga-ec2-base"
  role = aws_iam_role.base.name
}

# --- Rôle des nœuds de production : base + sauvegardes -------------------------
resource "aws_iam_role" "production" {
  name               = "taiga-ec2-production"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# Les journaux, comme toutes les instances
resource "aws_iam_role_policy_attachment" "production_journaux" {
  role       = aws_iam_role.production.name
  policy_arn = aws_iam_policy.journaux.arn
}

# Les sauvegardes, seulement pour la production
resource "aws_iam_role_policy_attachment" "production_sauvegardes" {
  role       = aws_iam_role.production.name
  policy_arn = aws_iam_policy.sauvegardes.arn
}

# Le porte-badge que les nœuds de production porteront
resource "aws_iam_instance_profile" "production" {
  name = "taiga-ec2-production"
  role = aws_iam_role.production.name
}

# --- Rôle de l'instance CI ----------------------------------------------------
resource "aws_iam_role" "ci" {
  name               = "taiga-ec2-ci"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ci_journaux" {
  role       = aws_iam_role.ci.name
  policy_arn = aws_iam_policy.journaux.arn
}

resource "aws_iam_role_policy_attachment" "ci_secrets" {
  role       = aws_iam_role.ci.name
  policy_arn = data.aws_iam_policy.lecture_secrets.arn # PFD-32
}

resource "aws_iam_role_policy_attachment" "ci_inventaire" {
  role       = aws_iam_role.ci.name
  policy_arn = aws_iam_policy.inventaire.arn
}

resource "aws_iam_instance_profile" "ci" {
  name = "taiga-ec2-ci"
  role = aws_iam_role.ci.name
}
