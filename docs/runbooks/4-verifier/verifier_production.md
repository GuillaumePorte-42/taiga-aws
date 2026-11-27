# Runbook – Vérifier la production (réseau, pare-feu, Swarm)

**Pourquoi** : avant de déployer, s'assurer que le chemin Internet → ALB → nœuds est ouvert, que les deux pare-feu (security group et UFW) sont en place et que le cluster Swarm est entier. Si quelque chose ne marche pas après le déploiement, on sait alors que le problème vient de la stack, pas du réseau.

**Où** : dans sa VM, à la racine de `taiga-infrastructure`, clé SSH dans l'agent (`docs/runbooks/1-equipe/se_connecter_ssh.md`). Toutes les commandes sont **en lecture seule**, sauf l'étape 5.

## 1. Le code et AWS sont d'accord
```bash
terraform -chdir=terraform/production plan
```
Attendu : `No changes`. **Un `destroy` inattendu → on s'arrête** : souvent un collègue a appliqué depuis sa branche, pas encore fusionnée ; attendre sa fusion, `git pull`, refaire le `plan`.

## 2. Les 3 nœuds sont derrière l'ALB
```bash
aws elbv2 describe-target-health --target-group-arn $(aws elbv2 describe-target-groups --names taiga-tg-production --query "TargetGroups[0].TargetGroupArn" --output text) --query "TargetHealthDescriptions[].[Target.Id,Target.Port,TargetHealth.State]" --output table
```
| État | Sens |
|---|---|
| `healthy` | Taiga répond sur 9000 |
| `unhealthy` | rien ne répond sur 9000 (normal avant le déploiement de la stack) |
| `unused` | instance arrêtée, ou ALB absent |
| tableau vide | nœuds pas inscrits : `apply` de `production/` |

## 3. Le security group des nœuds
```bash
aws ec2 describe-security-group-rules --filters Name=group-id,Values=$(aws ec2 describe-security-groups --filters Name=group-name,Values=taiga-sg-nodes --query "SecurityGroups[0].GroupId" --output text) --query 'SecurityGroupRules[?IsEgress==`false`].[FromPort,IpProtocol,ReferencedGroupInfo.GroupId,CidrIpv4]' --output table
```
Attendu : la dernière colonne à `None` partout (toutes les sources sont des SG, aucune plage d'IP) ; 9000 depuis le SG de l'ALB ; 2377, 7946 (tcp et udp), 4789 et le protocole `50` (ESP, sans port) depuis `taiga-sg-nodes` lui-même ; 22 depuis le bastion et la CI ; 8080 et 9100 depuis la supervision. Pour mettre un nom sur un `sg-…` :
```bash
aws ec2 describe-security-groups --group-ids <sg-…> --query "SecurityGroups[0].GroupName" --output text
```

## 4. UFW sur chaque nœud
```bash
for n in node-1 node-2 node-3; do echo "== $n"; ssh $n sudo ufw status; done
```
Attendu : `Status: active` ; 22 depuis `10.0.1.0/24` (bastion) et `10.0.12.0/24` (CI) ; 9100 et 8080 depuis `10.0.11.0/24` (supervision) ; 9000 depuis `10.0.1-3.0/24` (ALB) ; 2377, 7946 tcp/udp, 4789/udp et `esp` depuis `10.0.11-13.0/24` (nœuds ; UFW l'affiche `10.0.11.0/24/esp`). `Status: inactive` → étape 5.

## 5. Poser UFW sans casser le cluster (un nœud à la fois)
**Jamais `sudo ufw enable` à la main** : sans les règles Swarm, les nœuds ne se voient plus. Depuis `ansible/` :
1. Repérer le `Leader` : `ssh node-1 sudo docker node ls`. On le traite **en dernier**.
2. Un nœud qui n'est pas `Leader` :
   ```bash
   ansible-playbook -i inventories/production/aws_ec2.yml playbooks/site.yml --limit taiga-node-3
   ```
   Attendu : `failed=0` (1er passage ≈ `changed=15`, ensuite `changed=0`).
3. Contrôler avant de continuer : `ssh node-3 sudo ufw status` puis l'étape 6. Un nœud `Down` → on s'arrête et on regarde `role_swarm_node.yml`.
4. Recommencer avec l'autre nœud, puis le `Leader`.

## 6. Le cluster Swarm
```bash
ssh node-1 sudo docker node ls
```
Attendu : 3 lignes `Ready` / `Active`, un `Leader` et deux `Reachable`, même version de Docker partout. 3 managers = majorité de 2 : le cluster survit à la perte d'un nœud (prouvé : `docs/runbooks/4-verifier/tester_haute_disponibilite.md`).

## 7. Le réseau entre les nœuds (overlay chiffré)
Le réseau `taiga-reseau` est chiffré par Swarm avec IPsec (**ESP, protocole IP 50**). Si ESP est bloqué, chaque nœud ne joint que les conteneurs **de son propre nœud** : services en `2/3`, gateway relancée en boucle.
```bash
for n in node-1 node-2 node-3; do echo "== $n"; ssh $n 'sudo docker pull -q alpine:3.20 >/dev/null && sudo docker run --rm --network taiga-reseau alpine:3.20 wget -qO /dev/null -T 5 -S http://taiga-front/ 2>&1 | head -1'; done
```
Attendu : `HTTP/1.1 200 OK` trois fois. Le `docker pull -q` d'abord : sur un nœud neuf, l'image n'est pas là, et le `| head -1` ne montrerait que `Unable to find image` en coupant le téléchargement (vécu à la reconstruction du 05/11). `download timed out` → vérifier ESP dans le SG (étape 3) et dans UFW (étape 4).

## Pièges
- Une règle ajoutée dans le SG doit aussi l'être dans UFW (`ansible/playbooks/group_vars/role_swarm_node.yml`), et inversement : un flux doit passer les deux.
- UFW ne connaît que des adresses : la CI et la supervision partagent les sous-réseaux des nœuds. Le SG, lui, filtre par identité.
- Docker publie ses ports en contournant UFW : pour le 9000, c'est le SG qui protège vraiment.
- Un réseau overlay **chiffré** demande d'autoriser ESP (protocole IP 50) en plus des ports Swarm : la doc Docker le précise, et c'est passé inaperçu jusqu'au 03/11 (la plupart des requêtes tombaient sur une copie du même nœud).
