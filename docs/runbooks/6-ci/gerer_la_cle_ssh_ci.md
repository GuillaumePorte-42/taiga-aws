# Runbook – Clé SSH de la CI (déploiement du staging)

**Pourquoi** : le job `deployer-staging` (PFD-81) lance Ansible depuis le runner `taiga-ci` et doit se connecter en SSH au staging. Il a **sa propre clé**, jamais celle d'un humain : on peut la révoquer seule, et les journaux montrent ce que la CI a fait.

**Où** : dans sa VM, à la racine de `taiga-infrastructure`, `staging` à jour.

**État** : clé posée sur le staging le 30/10 (Guillaume, PFD-81). L'étape 5 sera complétée avec le job `deployer-staging`.

**Empreinte de la clé** : `SHA256:y4bi0yw8jVSXKC4SfGl05RZSy6eITqINHwshZoUP7kA` (`taiga-ci-deploy-staging`, ED25519).

## Où vit chaque morceau
| Morceau | Où | Pourquoi |
|---|---|---|
| Clé privée | Parameter Store `/taiga/staging/ci_ssh_private_key` (`SecureString`) | le rôle IAM de la machine CI lit déjà `/taiga/*` ; GitLab ne sait pas masquer une valeur sur plusieurs lignes |
| Clé publique | `cles_ssh/ci/taiga_ci.pub` (dans Git) | un **sous-dossier** : `cles_ssh/*.pub` (lu par Terraform pour le `user_data`) ne la prend pas, donc elle n'arrive ni sur le bastion, ni sur le monitoring, ni en production |
| Autorisation sur le staging | tâche Ansible `ansible.posix.authorized_key` | posée tout de suite sans recréer la machine, et remise après une reconstruction |

⚠️ Ne pas mettre la clé de la CI à la racine de `cles_ssh/` : elle serait autorisée partout, et le changement de `user_data` toucherait toutes les instances (production comprise).

## 1. Générer la clé (une seule fois)
```bash
ssh-keygen -t ed25519 -N "" -C "taiga-ci-deploy-staging" -f ~/taiga_ci
```
Deux fichiers : `~/taiga_ci` (privée) et `~/taiga_ci.pub` (publique). Pas de phrase de passe : un job ne peut pas en taper. Ne jamais afficher la clé privée (`cat`, chat, capture).

## 2. Ranger la clé privée dans Parameter Store
```bash
aws ssm put-parameter --name /taiga/staging/ci_ssh_private_key --type SecureString --value "file://$HOME/taiga_ci" --region eu-west-3
```
Attendu : `{"Version": 1, "Tier": "Standard"}`. Vérifier sans afficher la valeur :
```bash
aws ssm describe-parameters --parameter-filters "Key=Name,Values=/taiga/staging/ci_ssh_private_key" --query "Parameters[].[Name,Type]" --output table --region eu-west-3
```
Attendu : une ligne `SecureString`.

## 3. Mettre la clé publique dans le dépôt, puis supprimer la privée de la VM
```bash
mkdir -p cles_ssh/ci && cp ~/taiga_ci.pub cles_ssh/ci/taiga_ci.pub
ssh-keygen -lf cles_ssh/ci/taiga_ci.pub
rm ~/taiga_ci
```
La 2e commande affiche l'empreinte `SHA256:…` (à noter dans la MR). Après le `rm`, la seule copie de la clé privée est dans Parameter Store.

## 4. Autoriser la clé sur le staging (Ansible)
Même schéma que les règles UFW par groupe :

| Fichier | Contenu |
|---|---|
| `ansible/roles/common/defaults/main.yml` | `common_cles_ssh_supplementaires: []` (aucune clé en plus par défaut) |
| `ansible/roles/common/tasks/ssh.yml` | tâche « Ajouter les clés SSH supplémentaires » (`ansible.posix.authorized_key`, `user: ubuntu`, boucle sur la liste) |
| `ansible/playbooks/group_vars/role_staging.yml` | la liste du groupe `role_staging` : `"{{ playbook_dir }}/../../cles_ssh/ci/taiga_ci.pub"` |

Depuis `ansible/` (agent SSH chargé : `ssh-add ~/.ssh/taiga_bastion`) :
```bash
ansible-playbook -i inventories/staging playbooks/site.yml --limit role_staging --list-hosts
ansible-playbook -i inventories/staging playbooks/site.yml --limit role_staging
ssh staging "ssh-keygen -lf ~/.ssh/authorized_keys"
```
Attendu : `hosts (1): taiga-staging` ; la tâche en `changed` avec `(item=taiga_ci.pub)`, `failed=0` ; **4 clés** sur le staging (les 3 de l'équipe + `taiga-ci-deploy-staging`). Relancé : la tâche est en `ok` (idempotent).

`role_staging` est un **groupe de machines** (créé par l'inventaire dynamique à partir du tag AWS `Role`), pas un rôle Ansible.

## 5. Vérifier
À compléter avec le job : connexion SSH depuis le runner vers le staging, avec cette clé.

## Révoquer ou changer la clé
1. Retirer `cles_ssh/ci/taiga_ci.pub` (ou mettre `state: absent` dans la tâche), rejouer le playbook sur le staging.
2. Supprimer ou remplacer le paramètre : `aws ssm delete-parameter --name /taiga/staging/ci_ssh_private_key --region eu-west-3`.
3. Pour une nouvelle clé : refaire les étapes 1 à 4 (`put-parameter … --overwrite` à l'étape 2).

## Pièges
- La clé publique **à la racine** de `cles_ssh/` : elle irait sur toutes les machines par Terraform.
- Le `user_data` n'est lu par cloud-init qu'**au premier démarrage** : le modifier n'ajoute rien sur une machine qui existe déjà.
- `get-parameter --with-decryption` affiche la clé : à n'utiliser que dans le job, redirigé vers un fichier `0600`.
- Jamais `exclusive: true` dans `authorized_key` : le module supprimerait les clés de l'équipe, et plus personne ne pourrait se connecter.
- `site.yml --check` échoue sur « Extraire l'archive » (node_exporter) après un redémarrage : `/tmp` est vidé, et en simulation l'archive n'est pas téléchargée. C'est normal ; en vrai lancement, ça passe.
- `Permission denied (publickey)` avec Ansible : l'agent SSH est vide (nouveau terminal) → `eval "$(ssh-agent -s)" && ssh-add ~/.ssh/taiga_bastion`.
