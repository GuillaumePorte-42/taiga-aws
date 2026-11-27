# Runbook – Vérifier les mails (Mailpit en staging, SES en production)

**Pourquoi** : Taiga envoie des mails (invitations, mot de passe oublié, exports, notifications). En staging, ils vont dans **Mailpit**, un faux serveur qui les garde sans rien envoyer ; en production, ils partent par **Amazon SES**. Ce runbook dit comment les voir, ajouter un destinataire autorisé, et tester SES depuis le staging.

**Où** : dans sa VM, dossier `ansible/` de `taiga-infrastructure`, agent SSH chargé, identifiants AWS valides. Réglages : `ansible/roles/taiga/README.md` (« Les mails ») ; SES : `terraform/socle/ses.tf`.

## 1. Voir les mails du staging (Mailpit)
**Par l'interface** : tunnel SSH (autorisé sur le staging, `common_ssh_tcp_forwarding: "local"`) :
```bash
ssh -N -L 8025:127.0.0.1:8025 staging
```
Attendu : la commande **ne rend pas la main** (tunnel ouvert ; `bind [::1]:8025: Cannot assign requested address` est sans effet : pas d'IPv6 dans la VM). Puis `http://localhost:8025` dans le navigateur de la VM. `Ctrl+C` pour fermer.

**Sans navigateur** (API de Mailpit) :
```bash
ansible -i inventories/staging/aws_ec2.yml role_staging -b -m shell -a "curl -s localhost:8025/api/v1/messages | python3 -c \"import sys,json; [print(m['From']['Address'], '->', m['To'][0]['Address'], '|', m['Subject']) for m in json.load(sys.stdin)['messages']]\""
```
Attendu : une ligne par mail (expéditeur `no-reply@staging.taiga-ledevagilles.fr`).

Test rapide : sur le staging, « Mot de passe oublié ? » avec `admin`, ou *Settings → Project → Export* (le mail contient le lien de l'export : il passe par RabbitMQ, async, SMTP, puis la passerelle).

Les mails de Mailpit sont en mémoire : ils disparaissent quand le conteneur redémarre (voulu).

## 2. Ajouter un destinataire SES (bac à sable)
Le compte SES est en **bac à sable** : il n'envoie **qu'aux adresses vérifiées** (200 mails / 24 h). Chacun vérifie **sa** adresse (elle ne va pas dans le dépôt) :
```bash
aws sesv2 create-email-identity --email-identity <adresse>
```
Attendu : `"IdentityType": "EMAIL_ADDRESS"`, puis un mail d'Amazon Web Services dans la boîte (regarder les spams) : **cliquer sur le lien**.
```bash
aws sesv2 list-email-identities --query 'EmailIdentities[].[IdentityName,IdentityType,VerificationStatus]' --output table
```
Attendu : `taiga-ledevagilles.fr | DOMAIN | SUCCESS` et l'adresse en `SUCCESS`. `PENDING` : pas encore cliqué ; lien expiré → relancer `create-email-identity`.
- Retirer une adresse : `aws sesv2 delete-email-identity --email-identity <adresse>`.
- État du compte : `aws sesv2 get-account --query '{production:ProductionAccessEnabled,quota24h:SendQuota.Max24HourSend}'` → `false`, `200`.

## 3. Tester SES depuis le staging (sans commit)
On lance le playbook du staging en remplaçant les réglages mail **le temps d'un lancement** (`-e`, priorité maximale). Prévenir l'équipe (« le staging envoie par SES pendant 15 min »). Le compte qui reçoit doit avoir une **adresse vérifiée** dans son profil Taiga.
```bash
ansible-playbook -i inventories/staging/aws_ec2.yml playbooks/taiga.yml \
  -e taiga_email_hote=email-smtp.eu-west-3.amazonaws.com \
  -e taiga_email_port=587 \
  -e taiga_email_tls=True \
  -e "taiga_email_utilisateur={{ lookup('amazon.aws.aws_ssm', '/taiga/staging/email_host_user', region='eu-west-3') }}" \
  -e "taiga_email_mot_de_passe={{ taiga_secrets.email_host_password }}"
```
Les identifiants sont des **expressions** évaluées par Ansible : aucun secret dans l'historique du terminal. Attendu : `changed` sur « Écrire le .env » et « Lancer Taiga », `failed=0`. Puis « mot de passe oublié » → mail dans la vraie boîte ; *Afficher l'original* → **DKIM : PASS** (signé par `taiga-ledevagilles.fr`).

**Revenir à Mailpit** (obligatoire après le test) :
```bash
ansible-playbook -i inventories/staging/aws_ec2.yml playbooks/taiga.yml
```

## 4. Vérifier en production
Invitation : *projet → Team → Add member* → une adresse vérifiée → le mail arrive. Si rien n'arrive en 2 minutes :
```bash
ssh node-1 "sudo docker service logs --since 10m taiga_taiga-async 2>&1 | grep -i -E 'smtp|mail|error|not verified' | tail -20"
ssh node-1 "sudo docker service logs --since 10m taiga_taiga-back 2>&1 | grep -i -E 'smtp|mail|error|not verified' | tail -20"
```

## Dépannage
| Symptôme | Cause | Solution |
|---|---|---|
| `Email address is not verified` | destinataire non vérifié (bac à sable) | partie 2 |
| `Authentication Credentials Invalid` | identifiants SMTP | `terraform -chdir=terraform/socle plan` (paramètres à jour ?), redéployer |
| le mail arrive en **spam** | domaine neuf, peu de réputation | « Non spam » une fois ; DMARC en place (`socle/ses.tf`) ; piste : domaine MAIL FROM |
| bouton « Inviter » sans effet | adresse non vérifiée, déjà membre, faute de frappe | F12 → Réseau → réponse de l'API ; journaux du back |
| l'inviteur ne reçoit rien | normal : Taiga n'écrit pas à celui qui fait l'action | — |
| tunnel `administratively prohibited` | tunnels non autorisés sur la machine | `common_ssh_tcp_forwarding: "local"` dans `role_staging.yml`, `site.yml --limit role_staging` |
