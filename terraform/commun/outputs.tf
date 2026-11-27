output "bastion_public_ip" {
  description = "IP publique du bastion (change si l'instance est arrêtée puis redémarrée)"
  value       = aws_instance.main["bastion"].public_ip
}

output "private_ips" {
  description = "IP privées des instances de production et communes"
  value       = { for nom, i in aws_instance.main : nom => i.private_ip }
}

# Config SSH prête à l'emploi : le bastion, puis la supervision et la CI par rebond.
# Usage : terraform output -raw ssh_config > ~/.ssh/taiga_config (voir docs/runbooks/1-equipe/se_connecter_ssh.md)
output "ssh_config" {
  description = "Contenu de ~/.ssh/taiga_config, inclus par ~/.ssh/config"
  value       = <<-EOT
    # Généré par Terraform (terraform/commun) : ne pas modifier à la main
    Host bastion
        HostName ${aws_instance.main["bastion"].public_ip}
        User ubuntu
        IdentityFile ~/.ssh/taiga_bastion
        IdentitiesOnly yes

    Host monitoring
        HostName ${aws_instance.main["monitoring"].private_ip}
        User ubuntu
        IdentityFile ~/.ssh/taiga_bastion
        IdentitiesOnly yes
        ProxyJump bastion

    Host ci
        HostName ${aws_instance.main["ci"].private_ip}
        User ubuntu
        IdentityFile ~/.ssh/taiga_bastion
        IdentitiesOnly yes
        ProxyJump bastion
  EOT
}
