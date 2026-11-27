# Runbook – Ouvrir Grafana (et Prometheus)

**Pourquoi** : regarder les tableaux de bord (machines, conteneurs, base) ou les cibles de Prometheus. Grafana et Prometheus n'écoutent **qu'en local** sur la machine de supervision (`127.0.0.1`) : on y accède par un **tunnel SSH**, jamais par Internet. Fonctionnement : `ansible/roles/supervision/README.md`.

**Où** : dans sa VM, agent SSH chargé, config SSH à jour (`docs/runbooks/1-equipe/se_connecter_ssh.md`).

## Ce qui doit être allumé
| Pour… | Il faut |
|---|---|
| ouvrir Grafana | bastion + supervision (pas besoin de l'ALB ni de la NAT) |
| voir des données | les machines surveillées allumées (prod, staging) ; la RDS pour le tableau de la base |

## 1. Ouvrir le tunnel
```bash
ssh -N -L 3000:127.0.0.1:3000 monitoring
```
Attendu : la commande **ne rend pas la main** (c'est normal, le tunnel est ouvert). La laisser tourner dans ce terminal ; `Ctrl+C` pour fermer.

Pour Prometheus, même principe sur le port 9090 : `ssh -N -L 9090:127.0.0.1:9090 monitoring`.

## 2. Se connecter
Navigateur de la VM : `http://localhost:3000`. Utilisateur `admin`. Mot de passe dans Parameter Store, copié dans le presse-papier **sans l'afficher** :
```bash
aws ssm get-parameter --name /taiga/admin/grafana_admin_password --with-decryption --query Parameter.Value --output text | xclip -selection clipboard
```
(`sudo apt install xclip` si besoin), puis `Ctrl+V` dans le champ.

## Vérifier (sans navigateur)
Dans un autre terminal, tunnel ouvert :
```bash
read -r GF_PASS < <(aws ssm get-parameter --name /taiga/admin/grafana_admin_password --with-decryption --query Parameter.Value --output text)
curl -s -u "admin:$GF_PASS" http://localhost:3000/api/search | python3 -c "import sys,json; [print(d['title']) for d in json.load(sys.stdin)]"
```
Attendu : les tableaux de bord du dossier `Taiga` (machines node_exporter, conteneurs cAdvisor, PostgreSQL).

Les cibles de Prometheus, sans tunnel :
```bash
ssh monitoring "curl -s localhost:9090/api/v1/targets" | python3 -c "import sys,json; [print(t['labels']['job'], t['labels']['instance'], t['health']) for t in json.load(sys.stdin)['data']['activeTargets']]"
```
Attendu : `up` pour tout ce qui est allumé ; une machine éteinte apparaît `down` (normal).

## Dépannage
| Symptôme | Cause probable | Que faire |
|---|---|---|
| `channel … open failed: administratively prohibited` | tunnels SSH interdits sur la supervision | `common_ssh_tcp_forwarding: "local"` dans `role_monitoring.yml`, puis `site.yml --limit role_monitoring` |
| `bind: Address already in use` | un tunnel est déjà ouvert sur 3000 | le fermer, ou utiliser `-L 3001:127.0.0.1:3000` et `http://localhost:3001` |
| mot de passe refusé | Grafana ne lit le mot de passe de Parameter Store **qu'à son premier démarrage** | s'il a été changé dans Parameter Store : `grafana cli admin reset-admin-password` dans le conteneur |
| « No data » sur le tableau des conteneurs | cAdvisor ne voit pas les conteneurs (label `name` absent) | `docs/runbooks/7-urgence/diagnostiquer_taiga_en_panne.md`, section 6 ; Docker doit être en `overlay2` (rôle `docker`) |
| une machine absente de Prometheus | elle était éteinte quand `supervision.yml` a été lancé (la config est générée depuis les instances allumées) | relancer `supervision.yml` avec l'inventaire `tous`, tout allumé |

## Pièges
- Grafana n'est **jamais exposé** sur Internet : c'est voulu (piste écartée pour l'instant : un nom de domaine derrière l'ALB, réservé aux IP de l'équipe).
- Les tableaux sont gérés par Ansible : une modification faite dans l'interface est perdue au prochain playbook. Ne pas cliquer sur *Save dashboard*.
