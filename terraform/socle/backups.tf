# Durée de conservation des sauvegardes (en jours)
variable "backup_retention_days" {
  description = "Nombre de jours avant suppression automatique d'une sauvegarde"
  type        = number
  default     = 90
}

# Bucket des sauvegardes (dumps PostgreSQL, volume media) : socle, survit à la destruction de la base
resource "aws_s3_bucket" "backups" {
  bucket = "taiga-ledevagilles-backups"

  lifecycle {
    prevent_destroy = true
  }
}

# Versionnement : une sauvegarde écrasée ou supprimée par erreur reste récupérable
resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Chiffrement côté serveur, clé gérée par S3 (gratuit)
resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Les quatre verrous contre tout accès public
resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Cycle de vie : supprime les sauvegardes après N jours, et les anciennes versions 7 jours plus tard
resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "expiration-sauvegardes"
    status = "Enabled"

    filter {}

    expiration {
      days = var.backup_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# Nom du bucket, utile pour le script de sauvegarde
output "backups_bucket" {
  value = aws_s3_bucket.backups.bucket
}
