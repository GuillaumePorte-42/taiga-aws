# Runbook – Se connecter en SSH (bastion et machines privées)

**Pourquoi** : seul le bastion est joignable depuis Internet. Les autres machines se joignent en rebondissant par lui (`ProxyJump`). Terraform génère la config SSH avec les IP à jour : un fichier par dossier Terraform.

**Où** : dans sa VM, à la racine de `taiga-infrastructure`.

## La première fois
1. **Créer sa clé** (une seule fois, dans sa VM ; une phrase de passe est conseillée) :
   ```bash
   ssh-keygen -t ed25519 -C "<prenom>-taiga" -f ~/.ssh/taiga_bastion
   ```
   Deux fichiers : `~/.ssh/taiga_bastion` (privée, ne quitte jamais la VM) et `~/.ssh/taiga_bastion.pub` (publique).
2. **Déposer sa clé publique** dans le dépôt, sur une branche à son nom :
   ```bash
   cp ~/.ssh/taiga_bastion.pub cles_ssh/<prenom>.pub
   ssh-keygen -lf cles_ssh/<prenom>.pub
   ```
   La 2e commande doit afficher une empreinte `SHA256:…`. Puis commit, MR, fusion dans `staging`. La clé n'arrive que sur les instances **créées après** la fusion (voir `cles_ssh/README.md`).
3. Avoir son IP publique dans `/taiga/reseau/ips_equipe` (voir `docs/runbooks/1-equipe/changer_son_ip.md`).
4. Ajouter **en première ligne** de `~/.ssh/config` (l'étoile prend `taiga_config` et `taiga_config_staging`, mais pas la clé `taiga_bastion`) :
   ```
   Include ~/.ssh/taiga_config*
   ```
   Fichier vide ou absent : `echo 'Include ~/.ssh/taiga_config*' > ~/.ssh/config`. Sinon, l'ajouter en haut avec `nano` (au-dessus de tout bloc `Host`).

   **Déjà l'ancienne ligne sans étoile** (avant le staging) : la mettre à jour.
   ```bash
   sed -i 's|^Include ~/.ssh/taiga_config$|Include ~/.ssh/taiga_config*|' ~/.ssh/config && grep Include ~/.ssh/config
   ```

## Après chaque `apply` dans `terraform/commun/` (et après un arrêt / redémarrage du bastion)
```bash
terraform -chdir=terraform/commun output -raw ssh_config > ~/.ssh/taiga_config
chmod 600 ~/.ssh/config ~/.ssh/taiga_config
```

## Après chaque `apply` dans `terraform/staging/`
```bash
terraform -chdir=terraform/staging output -raw ssh_config > ~/.ssh/taiga_config_staging
chmod 600 ~/.ssh/taiga_config_staging
```
## Après chaque `apply` dans `terraform/production/`
La première fois seulement : `terraform -chdir=terraform/production init`.
```bash
terraform -chdir=terraform/production output -raw ssh_config > ~/.ssh/taiga_config_production
chmod 600 ~/.ssh/taiga_config_production
```
Rien à changer dans `~/.ssh/config` : l'`Include ~/.ssh/taiga_config*` prend aussi ce fichier.

Ces fichiers sont réécrits à chaque fois : ne rien y modifier à la main.

| Fichier | Généré par | Machines |
|---|---|---|
| `~/.ssh/taiga_config` | `terraform/commun` | `bastion`, `monitoring`, `ci` |
| `~/.ssh/taiga_config_staging` | `terraform/staging` | `staging` |
| `~/.ssh/taiga_config_production` | `terraform/production` | `node-1`, `node-2`, `node-3` |

## Se connecter
```bash
ssh bastion
ssh monitoring
ssh ci
ssh staging
ssh node-1
ssh node-2
ssh node-3
```
Au premier `ssh`, attendre une minute après l'`apply` (cloud-init pose les clés).

Avec Ansible (depuis `ansible/`) : la clé doit être dans l'agent, car Ansible ne lit pas les alias `Host`.
```bash
eval "$(ssh-agent -s)" && ssh-add ~/.ssh/taiga_bastion
ansible-playbook -i inventories/staging/aws_ec2.yml playbooks/ping.yml
ansible-playbook -i inventories/production/aws_ec2.yml playbooks/ping.yml
```

## Vérifier
- Sans se connecter : `ssh -G staging | grep -i -e ^hostname -e ^proxyjump`.
- Sur le bastion : `ssh-keygen -lf ~/.ssh/authorized_keys` (une ligne par personne).
- Qui s'est connecté : `sudo journalctl -u ssh --since "1 hour ago" | grep "Accepted publickey"` (empreinte de la clé utilisée).

## En cas de problème
| Message | Cause probable | Solution |
|---|---|---|
| attente puis *timeout* | son IP n'est pas dans la liste | `docs/runbooks/1-equipe/changer_son_ip.md` |
| `Permission denied (publickey)` | mauvaise clé, ou instance créée avant l'ajout de sa clé | `ssh -v bastion` : vérifier la clé proposée ; recréer l'instance ou Ansible |
| `Could not resolve hostname bastion` | `taiga_config` absent ou `Include` manquant | refaire « La première fois » et « Après chaque apply » |
| `Could not resolve hostname staging` (ou `node-1`) | `Include` sans étoile, ou `taiga_config_staging` / `taiga_config_production` absent | `grep Include ~/.ssh/config` ; régénérer le fichier de l'environnement |
| `Output "ssh_config" not found` | `apply` pas encore fait depuis l'ajout de la sortie, ou `init` manquant | `terraform -chdir=terraform/<env> init`, puis `apply` depuis `staging` à jour |
| Ansible : `Permission denied (publickey)` mais `ssh` marche | clé absente de l'agent SSH | `eval "$(ssh-agent -s)" && ssh-add ~/.ssh/taiga_bastion` |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | nouvelle machine sur une IP déjà vue | `ssh-keygen -R <ip>` puis reconnecter |
| `AuthFailure` sur une commande `aws` ou `terraform`, ou inventaire Ansible vide (`no hosts matched`) alors que `aws sts get-caller-identity` marche | heure de la VM décalée (veille du PC) | comparer `date -u` et `curl -sI https://ec2.eu-west-3.amazonaws.com \| grep -i '^date'`, puis `sudo timedatectl set-ntp true && sudo systemctl restart systemd-timesyncd` |

## Pièges
- La clé privée ne va jamais sur le bastion : le rebond la garde sur son poste.
- L'IP publique du bastion change à chaque arrêt / redémarrage : régénérer `taiga_config`. Les IP privées (supervision, CI, staging, nœuds) ne changent qu'à la recréation de l'instance.

## La routine (chaque matin, ou après un `apply`)
```bash
git switch staging && git pull
terraform -chdir=terraform/commun output -raw ssh_config > ~/.ssh/taiga_config
terraform -chdir=terraform/staging output -raw ssh_config > ~/.ssh/taiga_config_staging
terraform -chdir=terraform/production output -raw ssh_config > ~/.ssh/taiga_config_production
chmod 600 ~/.ssh/taiga_config*
eval "$(ssh-agent -s)" && ssh-add ~/.ssh/taiga_bastion
ssh bastion hostname
```
