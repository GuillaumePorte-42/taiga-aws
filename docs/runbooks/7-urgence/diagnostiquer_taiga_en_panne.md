# Runbook – Diagnostiquer Taiga en panne

**Pourquoi** : Taiga ne répond pas, répond mal (`502`, `503`, `403`, page blanche) ou une partie seulement marche. On remonte le chemin de la requête, de l'extérieur vers l'intérieur, et on s'arrête à la première étape qui ne donne pas l'attendu. Toutes les commandes sont **en lecture seule**, sauf la section « Réparer ».

**Où** : dans sa VM, à la racine de `taiga-infrastructure`, agent SSH chargé, config SSH à jour (`docs/runbooks/1-equipe/se_connecter_ssh.md`).

## Le chemin d'une requête
```
navigateur → DNS → ALB (règles 10, 11, 20, 30) → port 9000 d'un nœud → gateway nginx → front / back / events / protected
                                                                            → back → base (RDS en prod, conteneur en staging)
```
Production : 3 nœuds Swarm, les conteneurs se parlent par le réseau overlay chiffré `taiga-reseau`. Staging : une machine, Docker Compose.

## 1. Qui répond ?
```bash
curl -sI https://taiga-ledevagilles.fr | grep -i -E "^HTTP|^server"
curl -sI https://staging.taiga-ledevagilles.fr | grep -i -E "^HTTP|^server"
```
| Réponse | Sens | Aller à |
|---|---|---|
| `200` | le site répond ; le problème est dans l'application (une page, la connexion…) | 5 |
| `403` « Accès réservé à l'équipe » (staging) | votre IP n'est pas dans `ips_equipe` (ou la NAT pour la CI) | `docs/runbooks/1-equipe/changer_son_ip.md` |
| `502` / `503` avec `server: awselb/2.0` | l'ALB n'a aucune machine saine derrière lui | 2 |
| `502` avec `server: nginx` | la gateway tourne, mais pas ce qu'il y a derrière (back, front) | 3 (prod) ou 4 (staging) |
| rien, *timeout*, `Could not resolve host` | ALB détruit (le soir), ou DNS | `terraform -chdir=terraform/commun plan` |

Juste après un redémarrage, `502` et `503` sont **normaux** quelques minutes : base qui démarre (5 à 10 min), conteneurs relancés, contrôles de santé de l'ALB (2 réussites de suite, toutes les 30 s).

## 2. L'ALB voit-il des machines saines ?
```bash
aws elbv2 describe-target-health --target-group-arn $(aws elbv2 describe-target-groups --names taiga-tg-production --query "TargetGroups[0].TargetGroupArn" --output text) --query "TargetHealthDescriptions[].[Target.Id,TargetHealth.State]" --output table
```
Pour le staging : `taiga-tg-staging`. Attendu : `healthy`. `unused` = instance arrêtée ; `unhealthy` = rien ne répond `200` sur le port 9000 → 3 ou 4.

## 3. Production : le cluster et les services
```bash
ssh node-1 'sudo docker node ls; sudo docker service ls'
```
Attendu : 3 nœuds `Ready` / `Active`, un `Leader` ; services en `3/3` ou `1/1`. Si node-1 ne répond pas, prendre `node-2`.

Un service incomplet : où sont ses copies, et pourquoi elles ne démarrent pas.
```bash
ssh node-1 'sudo docker service ps taiga_taiga-front --format "table {{.Name}}\t{{.Node}}\t{{.CurrentState}}\t{{.Error}}" | head -10'
```
Ses journaux (toutes les copies, avec le nœud) :
```bash
ssh node-1 'sudo docker service logs taiga_taiga-gateway --tail 30 2>&1'
```
Le réseau entre les nœuds (le front doit répondre depuis **chaque** nœud) :
```bash
for n in node-1 node-2 node-3; do echo "== $n"; ssh $n 'sudo docker pull -q alpine:3.20 >/dev/null && sudo docker run --rm --network taiga-reseau alpine:3.20 wget -qO /dev/null -T 5 -S http://taiga-front/ 2>&1 | head -1'; done
```
Attendu : `HTTP/1.1 200 OK` trois fois (le `docker pull -q` évite le `Unable to find image` d'un nœud neuf).

## 4. Staging : les conteneurs
```bash
ssh staging 'sudo docker compose -f /opt/taiga/docker-compose.yml ps'
ssh staging 'sudo docker compose -f /opt/taiga/docker-compose.yml logs --tail 50 taiga-back'
```
Attendu : 10 conteneurs `Up` (dont `taiga-mailpit`). Quelles images tournent : `… images` au lieu de `ps`.

## 5. La base
```bash
aws rds describe-db-instances --db-instance-identifier taiga-db --query "DBInstances[0].DBInstanceStatus" --output text
```
Attendu : `available` (prod). `stopped` ou `starting` : attendre ; Swarm relance le back tout seul. Staging : la base est le conteneur `taiga-db` (4).

## 6. La supervision (ce qui s'est passé avant)
Grafana (`docs/runbooks/4-verifier/ouvrir_grafana.md`) : tableaux machines, conteneurs, base. Les cibles de Prometheus :
```bash
ssh monitoring "curl -s localhost:9090/api/v1/targets" | python3 -c "import sys,json; [print(t['labels']['job'], t['labels']['instance'], t['health'], t['lastError']) for t in json.load(sys.stdin)['data']['activeTargets']]"
```

## Réparer (après avoir compris)
| Symptôme | Cause probable | Que faire |
|---|---|---|
| service en `2/3`, une copie `Pending` « no suitable node (max replicas per node) » | un nœud en `Drain` / `Down`, ou mise à jour bloquée | nœud : `docker node update --availability active <nœud>` (après avoir demandé à l'équipe) ; sinon `ssh node-1 'sudo docker service update --force taiga_taiga-front'` |
| gateway relancée toutes les ~2 min, `499` sur `GET /` dans ses journaux | nginx n'obtient pas de réponse du front : réseau entre nœuds (ESP bloqué) | 3 (test `wget`) ; ESP doit être autorisé dans le SG `nodes` et UFW (`docs/runbooks/4-verifier/verifier_production.md`) |
| `host not found in upstream "taiga-back"` au démarrage de la gateway | nginx démarre avant que le DNS de Swarm connaisse le back | attendre : Swarm la relance |
| `connection refused` vers le 8080 (Prometheus) | cAdvisor absent | depuis `ansible/` : `ansible-playbook -i inventories/tous/aws_ec2.yml playbooks/cadvisor.yml` |
| service en `0/1`, tâche en `Preparing`, *ERROR* `registry-1.docker.io … context deadline exceeded` | le nœud n'a pas pu télécharger l'image (démarré avant la NAT, ou Docker Hub lent) ; un conteneur jamais démarré n'a **pas de journaux** | depuis le nœud : `curl -s -o /dev/null -w '%{http_code}\n' https://registry-1.docker.io/v2/` (`401` = il sort) ; puis `ssh node-1 'sudo docker service update --force <service>'` (vécu le 06/11 avec `taiga-events`) |
| Grafana : « Conteneurs Taiga » sans valeur pour la prod, alerte `CadvisorAveugle` | cAdvisor démarré « aveugle » (`client version 1.24 is too old` dans `docker logs cadvisor`) | `sudo docker restart cadvisor` sur chaque nœud (`docs/runbooks/2-chaque-jour/arreter_demarrer.md`, contrôles du matin) |
| Grafana : sondes « Injoignable » en code `0`, mais `curl` répond `200` depuis la VM | la supervision ne résout pas le nom (`ssh monitoring "curl -sS https://taiga-ledevagilles.fr"` → `Could not resolve host`) : réponse négative en cache après la recréation du DNS par `commun/` | `ssh monitoring "dig taiga-ledevagilles.fr @169.254.169.253"` : `NXDOMAIN` → attendre ~15 min ; `NOERROR` avec des IP → chercher ailleurs |
| `The swarm does not have a leader` | moins de 2 managers sur 3 | ne redémarrer **aucun** autre nœud ; rallumer les nœuds arrêtés |
| correction faite à la main sur une machine | elle sera écrasée au prochain déploiement | corriger par Git, MR, playbook |

## Pièges
- Lire **qui** répond (`server:`) avant de chercher : un `502` de l'ALB et un `502` de nginx n'ont pas la même cause.
- Un test qui passe depuis un nœud ne prouve rien pour les autres : en prod, tester depuis les trois.
- Ne pas relancer un playbook pendant qu'un collègue travaille sur les mêmes machines : demander d'abord.
