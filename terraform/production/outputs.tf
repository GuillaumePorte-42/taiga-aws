output "private_ips" {
  description = "IP privées des instances de production et communes"
  value       = { for nom, i in aws_instance.main : nom => i.private_ip }
}

# Blocs SSH des nœuds (par rebond sur le bastion) : terraform output -raw ssh_config > ~/.ssh/taiga_config_production
output "ssh_config" {
  description = "Contenu de ~/.ssh/taiga_config_production"
  value       = <<-EOT
    # Généré par Terraform (terraform/production) : ne pas modifier à la main
    %{for nom, i in aws_instance.main~}
    Host ${nom}
        HostName ${i.private_ip}
        User ubuntu
        IdentityFile ~/.ssh/taiga_bastion
        IdentitiesOnly yes
        ProxyJump bastion

    %{endfor~}
  EOT
}