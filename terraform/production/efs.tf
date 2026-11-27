# Stockage partagé EFS des nœuds Swarm de production.
# Monté sur chaque nœud par le rôle Ansible "efs" (ansible/roles/efs/), dans /mnt/efs.

# Sous-réseaux et SG, lus depuis reseau/ via les locals de donnees.tf (local.subnets et local.sgs)
locals {
  efs_subnet_ids = [ # les 3 sous-réseaux applicatifs, un mount target par zone
    local.subnets["applicatif-a"],
    local.subnets["applicatif-b"],
    local.subnets["applicatif-c"],
  ]
  efs_sg_id = local.sgs["efs"] # le SG efs (port 2049 autorisé depuis le SG nodes)
}

# Le système de fichiers EFS
resource "aws_efs_file_system" "efs" {
  creation_token   = "taiga-production-efs" # identifiant unique : évite de créer deux EFS si l'apply est relancé
  encrypted        = true                   # données chiffrées au repos, comme les disques des instances
  performance_mode = "generalPurpose"       # mode standard, adapté à une application web
  throughput_mode  = "elastic"              # le débit s'adapte à l'usage, facturé à la consommation

  tags = {
    Name = "taiga-production-efs" # les autres tags (Projet, Environnement…) viennent des default_tags du provider
  }
}

# Un point d'accès réseau (mount target) par zone, pour que chaque nœud joigne l'EFS dans sa propre zone
resource "aws_efs_mount_target" "efs" {
  for_each = toset(local.efs_subnet_ids) # crée un mount target pour chaque sous-réseau de la liste

  file_system_id  = aws_efs_file_system.efs.id # l'EFS auquel il donne accès
  subnet_id       = each.value                 # le sous-réseau (donc la zone) où il est placé
  security_groups = [local.efs_sg_id]          # protégé par le SG efs : seul le port 2049 depuis les nœuds est autorisé
}

# Active les sauvegardes automatiques de l'EFS par AWS Backup
# (plan quotidien géré par AWS, conservation 35 jours)
resource "aws_efs_backup_policy" "efs" {
  file_system_id = aws_efs_file_system.efs.id # l'EFS à sauvegarder

  backup_policy {
    status = "ENABLED" # sauvegardes activées
  }
}

# ID de l'EFS écrit dans Parameter Store : Ansible le lit pour monter l'EFS, rien à recopier à la main
resource "aws_ssm_parameter" "efs_id" {
  name  = "/taiga/production/efs_id"
  type  = "String"
  value = aws_efs_file_system.efs.id

  tags = {
    Name = "taiga-efs-id"
  }
}

# ID de l'EFS, affiché après l'apply (aussi écrit dans /taiga/production/efs_id)
output "efs_id" {
  value = aws_efs_file_system.efs.id
}