# Rôle `docker`

Installe Docker Engine (et ses greffons Compose et Buildx) depuis le **dépôt APT officiel de Docker**, sur toutes les machines sauf le bastion. Lancé par `playbooks/docker.yml` (aussi par `ci.yml` et `supervision.yml`).

## Ce qu'il fait, dans l'ordre
| Tâche | Quoi |
|---|---|
| prérequis | `ca-certificates`, `curl` |
| clé et dépôt | clé GPG de Docker dans `/etc/apt/keyrings/docker.asc`, dépôt `download.docker.com/linux/ubuntu noble stable` |
| installation | `docker-ce`, `docker-ce-cli`, `docker-ce-rootless-extras`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`, **à la version épinglée** dans `defaults/main.yml` |
| service | démarré et activé au démarrage ; `ubuntu` dans le groupe `docker` |
| stockage | `/etc/docker/daemon.json` : `features.containerd-snapshotter = false` (retour au stockage classique **overlay2**), en **gardant** les autres réglages du fichier ; Docker redémarré seulement si le fichier change (handler) |

## Pourquoi overlay2
Le nouvel entrepôt d'images de containerd (activé par défaut dans les versions récentes de Docker) empêche **cAdvisor** de voir les conteneurs : plus de métriques de conteneurs dans Prometheus (PFD-36, 03/11).

## Versions épinglées
Les versions sont dans `defaults/main.yml` (`docker_version`, `docker_containerd_version`, `docker_buildx_version`, `docker_compose_version`). Ce sont celles relevées le 05/11 sur le staging et node-1, avant la reconstruction : celles avec lesquelles Taiga, Swarm et cAdvisor ont été testés. Une machine neuve reçoit donc **la même version** que les autres, et pas la dernière du dépôt.

Relever la version d'une machine :
```bash
dpkg -l | grep -E 'docker|containerd'
```
Changer de version : modifier `defaults/main.yml` par une MR, lancer `docker.yml --check` puis pour de vrai sur le **staging** d'abord, puis mettre à jour `docs/reference/versions_outils.md`.

## L'utiliser
```bash
ansible-playbook -i inventories/tous/aws_ec2.yml playbooks/docker.yml
```
`docker.yml` est en `serial: 1` : **une machine à la fois**. Le rôle peut redémarrer Docker ; deux nœuds Swarm ne doivent jamais redémarrer ensemble (quorum de 2 managers sur 3).

## Pièges
- **Machine déjà plus récente** que la version épinglée : sans `allow_downgrade`, apt refuse de **descendre** de version et la tâche devrait échouer (pas encore vu chez nous). C'est voulu (on le voit au lieu de le subir) ; on décide alors en équipe d'épingler la nouvelle version ou de descendre.
- **Version retirée du dépôt** : si Docker ne la propose plus, l'installation échoue. Vérifier avec `apt-cache madison docker-ce | head -5`.
- Un `apt upgrade` lancé à la main peut encore monter Docker. Piste : `ansible.builtin.dpkg_selections` en `hold` pour le bloquer aussi.
- Le dépôt vise `noble` (Ubuntu 24.04) en dur : à changer avec l'AMI.
- Docker publie ses ports **en contournant UFW** : c'est le security group qui protège vraiment (`docs/runbooks/4-verifier/verifier_production.md`).
