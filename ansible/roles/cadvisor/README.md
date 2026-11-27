# Rôle `cadvisor`

Un conteneur cAdvisor par machine qui fait tourner Taiga (staging et nœuds de production) : il mesure le processeur, la mémoire et le réseau de **chaque conteneur**, et les publie sur le port 8080 pour Prometheus. Lancé par `playbooks/cadvisor.yml` (après le rôle `docker`).

## Variables (`defaults/main.yml`)
| Variable | Défaut |
|---|---|
| `cadvisor_image` | `gcr.io/cadvisor/cadvisor:v0.49.1` (version fixée) |
| `cadvisor_port` | `8080` |

## L'utiliser
```bash
ansible-playbook -i inventories/tous/aws_ec2.yml playbooks/cadvisor.yml
```
Vérifier : `ssh staging "sudo docker ps --filter name=cadvisor"` → `Up`.

## Pièges
- Conteneur **privilégié**, avec les dossiers du système en lecture seule : il observe, il ne modifie rien.
- Le port 8080 n'est ouvert qu'à la supervision : par le security group, et par UFW (`playbooks/group_vars/role_*.yml`). Docker publie le port en contournant UFW : c'est le security group qui protège vraiment.
- **cAdvisor « aveugle » au démarrage des nœuds de production** (vu le 05/11 et le 06/11, 2 rallumages sur 2 ; le staging, lui, démarre bien) : le conteneur répond et se dit `healthy`, mais ne voit **aucun** conteneur. Dans `docker logs cadvisor` : `Registration of the docker container factory failed: … client version 1.24 is too old. Minimum supported API version is 1.40`. Explication retenue (non lue dans le code de cAdvisor) : Docker n'est pas encore prêt quand cAdvisor démarre, son client se replie sur une vieille version de l'API, refusée par Docker 29, et ne réessaie jamais. Contournement : `sudo docker restart cadvisor` sur chaque nœud (contrôle du matin, `docs/runbooks/2-chaque-jour/arreter_demarrer.md`). Détecté par l'alerte `CadvisorAveugle`.
- Un **healthcheck ne suffirait pas** : celui de cAdvisor (`/healthz`) répond OK même aveugle, et Docker seul ne relance pas un conteneur `unhealthy` (seul Swarm remplace une tâche malade ; ici, cAdvisor est un simple conteneur).
- Pistes : une version plus récente de cAdvisor (vérifier dans ses notes de version que le client négocie l'API), ou un démarrage qui attend que Docker réponde (service systemd après `docker.service`).
