# =============================================================================
# commun/instances.tf — PFD-17 · ADR-03
# Instances communes aux deux environnements : bastion, supervision, CI.
# Les clés SSH de l'équipe (cles_ssh/*.pub) sont posées par cloud-init au premier démarrage.
# Le tag Role sert à l'inventaire dynamique Ansible (PFD-59).
# =============================================================================

locals {
  instances = {
    # Instances partagées : une ligne par machine
    bastion    = { type = "t3.micro", subnet = "public-a", sg = "bastion", disk = 10, role = "bastion", public_ip = true }
    monitoring = { type = "t3.small", subnet = "applicatif-a", sg = "monitoring", disk = 20, role = "monitoring", public_ip = false }
    ci         = { type = "t3.small", subnet = "applicatif-b", sg = "ci", disk = 20, role = "ci", public_ip = false } # runner seul (SonarCloud, ADR-16) ; repasser en t3.medium si manque de mémoire
  }

  # Clés publiques de l'équipe : un fichier .pub par personne dans terraform/cles_ssh/
  cles_equipe = [
    for f in fileset("${path.module}/../../cles_ssh", "*.pub") :
    trimspace(file("${path.module}/../../cles_ssh/${f}"))
  ]
}

resource "aws_instance" "main" {
  for_each = local.instances

  user_data = "#cloud-config\n${yamlencode({ ssh_authorized_keys = local.cles_equipe })}"
  iam_instance_profile = (
    each.key == "ci"
    ? aws_iam_instance_profile.ci.name
    : aws_iam_instance_profile.base.name
  )

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
