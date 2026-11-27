# Runbook – Éteindre et rallumer la NAT Gateway

**Pourquoi** : la NAT coûte ~35 $/mois + le trafic. Elle ne sert qu'aux machines des sous-réseaux privés pour sortir sur Internet (images Docker, mises à jour). Sans machine privée allumée, on l'éteint.

**Où** : dans sa VM, dossier `taiga-infrastructure/terraform/reseau`.

## Éteindre
```bash
terraform destroy -target=aws_nat_gateway.main -target=aws_eip.nat
```
Attendu : `3 to destroy` (NAT, Elastic IP, route vers la NAT). Plusieurs minutes. L'avertissement sur `-target` est normal.

## Rallumer
```bash
terraform apply
```
Attendu : `3 to add`. 1 à 3 minutes. **Le matin, la NAT passe avant les machines** (ordre complet : `docs/runbooks/2-chaque-jour/arreter_demarrer.md`).

## Vérifier
`terraform plan` : `3 to add` si elle est éteinte, `No changes` si elle est allumée. Et son état :
```bash
aws ec2 describe-nat-gateways --filter Name=tag:Name,Values=taiga-nat Name=state,Values=available --query "NatGateways[].State" --output text
```
Attendu : `available`.

## Pièges
- **Jamais de suppression dans la console** : le state croit encore la NAT là, et l'IP élastique reste réservée (payante). Si c'est fait : relancer la même commande `destroy -target` (le rafraîchissement doit retirer la NAT du state, puis détruire l'IP et la route : proposé le 05/11, à confirmer en lisant le plan), surtout pas libérer l'IP à la main.
- Les 3 IP « sans nom » de la liste des Elastic IPs sont celles de l'ALB (*Service managed : alb*), pas des NAT.

## Règle d'équipe
Celui qui finit la journée éteint la NAT ; le premier qui en a besoin la rallume. Quand on travaille plusieurs jours de suite sur les machines privées, on peut la garder allumée la semaine (~1,20 $/jour).
