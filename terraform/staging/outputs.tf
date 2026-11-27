output "private_ips" {
  description = "IP privée de l'instance staging"
  value       = { for nom, i in aws_instance.main : nom => i.private_ip }
}

# Bloc SSH du staging (par rebond sur le bastion) : terraform output -raw ssh_config > ~/.ssh/taiga_config_staging
output "ssh_config" {
  description = "Contenu de ~/.ssh/taiga_config_staging"
  value       = <<-EOT
    # Généré par Terraform (terraform/staging) : ne pas modifier à la main
    Host staging
        HostName ${aws_instance.main["staging"].private_ip}
        User ubuntu
        IdentityFile ~/.ssh/taiga_bastion
        IdentitiesOnly yes
        ProxyJump bastion
  EOT
}