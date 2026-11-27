# Rôle `swarm`

Forme le cluster **Docker Swarm** de la production : 3 nœuds, **tous managers** (Raft : le cluster continue avec 2 managers sur 3 ; haute disponibilité prouvée le 03/11). Lancé par `playbooks/swarm.yml`, inventaire `production`, après `docker.yml`.

## Ce qu'il fait
| Tâche | Quoi |
|---|---|
| prérequis | `python3-docker` (bibliothèque utilisée par les modules `community.docker`) |
| création | sur le **premier nœud du play** : `docker swarm init --advertise-addr <IP privée>` (ne fait rien si le cluster existe) |
| ajout | sur les autres : `docker swarm join` comme **manager**, avec le jeton lu dans le résultat du premier nœud (`hostvars`) |

## L'utiliser
```bash
ansible-playbook -i inventories/production/aws_ec2.yml playbooks/swarm.yml
ssh node-1 'sudo docker node ls'
```
Attendu : 3 nœuds `Ready` / `Active`, un `Leader`, deux `Reachable`.

## Réseau entre les nœuds (security group `nodes` et UFW)
2377/tcp (gestion du cluster), 7946/tcp+udp (découverte), 4789/udp (VXLAN, réseau overlay) et **ESP** (protocole IP 50, sans port) : le réseau overlay de Taiga est **chiffré** (IPsec). Sans ESP, les services ne se joignent plus d'un nœud à l'autre (corrigé le 03/11).

## Pièges
- **Toujours l'inventaire `production`** : le premier hôte du play crée le cluster. Depuis le 04/11, `swarm.yml` ne vise plus que `role_swarm_node` (le staging tourne en Docker Compose, ADR-03).
- L'ordre de l'inventaire dynamique peut changer : sans conséquence sur un cluster existant (« init » ne fait rien, « join » non plus si le nœud est déjà membre).
- Une reconstruction crée un **nouveau** cluster : la stack est redéployée ensuite (`taiga_production.yml` ou le bouton de la CI).
