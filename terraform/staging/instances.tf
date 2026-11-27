# =============================================================================
# staging/instances.tf — PFD-17
# L'instance staging tout-en-un (Taiga + PostgreSQL 16 en conteneur), zone C.
# =============================================================================

locals {
  instances = {
    staging = { type = "t3.medium", subnet = "staging-c", sg = "staging", disk = 20, role = "staging", public_ip = false }
  }

  # Clés publiques de l'équipe : un fichier .pub par personne dans terraform/cles_ssh/
  cles_equipe = [
    for f in fileset("${path.module}/../../cles_ssh", "*.pub") :
    trimspace(file("${path.module}/../../cles_ssh/${f}"))
  ]
}

resource "aws_instance" "main" {
  for_each = local.instances

  # Au premier démarrage, cloud-init pose les clés de l'équipe pour l'utilisateur ubuntu
  user_data            = "#cloud-config\n${yamlencode({ ssh_authorized_keys = local.cles_equipe })}"
  iam_instance_profile = data.aws_iam_instance_profile.base.name

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = each.value.type
  subnet_id                   = local.subnets[each.value.subnet]
  vpc_security_group_ids      = [local.sgs[each.value.sg]]
  associate_public_ip_address = each.value.public_ip

  # IMDSv2 obligatoire : protège les identifiants du rôle IAM contre le vol
  # par requête forgée. Hop limit 2 : les conteneurs (jobs CI, Docker) y accèdent.
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  # Disque chiffré, supprimé avec l instance : les données vivent dans RDS et EFS
  root_block_device {
    volume_type           = "gp3"
    volume_size           = each.value.disk
    encrypted             = true
    delete_on_termination = true
  }

  # Projet, Environnement et GerePar sont posés par default_tags
  tags = {
    Name = "taiga-${each.key}"
    Role = each.value.role
  }

  # Une nouvelle version d Ubuntu ne doit pas recréer les instances par surprise
  lifecycle {
    ignore_changes = [ami]
  }
}
