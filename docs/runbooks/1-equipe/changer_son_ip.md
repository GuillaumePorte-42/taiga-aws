# Runbook – Mettre à jour les IP de l'équipe (SSH sur le bastion)

**Pourquoi** : le bastion n'accepte le SSH que depuis les IP listées dans Parameter Store (`/taiga/reseau/ips_equipe`, type `StringList`, format `1.2.3.4/32,5.6.7.8/32`). Nouvelle connexion Internet (box qui change d'IP, autre lieu, soutenance) = plus d'accès tant que la liste n'est pas à jour.

**Où** : dans sa VM. L'accès AWS (CLI) ne dépend pas de l'IP, seul le SSH en dépend.

**Qui** : une seule personne écrit la liste (les autres lui envoient leur IP), pour ne pas s'écraser.

## 1. Trouver son IP publique
```bash
MON_IP=$(curl -s https://checkip.amazonaws.com)
echo $MON_IP
```
Ou ouvrir https://checkip.amazonaws.com dans un navigateur. **Pas `ipconfig`** : il donne l'adresse locale. Une adresse en `192.168.`, `10.` ou `172.16.` à `172.31.` est privée et ne marchera pas.

## 2. Lire la liste, puis la réécrire
```bash
aws ssm get-parameter --region eu-west-3 --name /taiga/reseau/ips_equipe --query Parameter.Value --output text
```
```bash
aws ssm put-parameter --region eu-west-3 --name /taiga/reseau/ips_equipe --type StringList --value "AUTRE_IP/32,${MON_IP}/32" --overwrite
```
`--overwrite` remplace **toute** la liste : garder les IP des autres, **retirer** son ancienne IP. La première fois, la valeur est `A_REMPLIR` : ne pas la garder.

## 3. Appliquer dans `terraform/reseau/`
```bash
terraform apply -target=aws_vpc_security_group_ingress_rule.bastion_ssh
```
Ciblé pour ne pas rallumer la NAT (voir `docs/runbooks/2-chaque-jour/eteindre_rallumer_nat.md`). Attendu : seulement des règles `bastion_ssh` ajoutées ou supprimées.

## Vérifier
`ssh` vers le bastion. Ou, dans la console : `taiga-sg-bastion` → règles entrantes.

## Jour J (soutenance)
Mettre à jour la liste le matin même, depuis la salle, et tester le SSH avant de passer. Plan B : ajouter la règle à la main dans la console (Terraform la retirera au prochain `apply`).

