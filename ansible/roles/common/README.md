# Rôle `common`

La base de **toutes** les machines : paquets et mises à jour de sécurité automatiques, fuseau horaire, SSH durci, pare-feu UFW, node_exporter (métriques pour Prometheus). Lancé par `playbooks/site.yml`.

## Ce qu'il fait, dans l'ordre
| Fichier | Quoi |
|---|---|
| `tasks/paquets.yml` | `apt upgrade` (sûr), paquets de base, `Europe/Paris`, `unattended-upgrades` |
| `tasks/ssh.yml` | `/etc/ssh/sshd_config.d/99-taiga.conf` : pas de root, pas de mot de passe, pas de redirection de ports (sauf sur le bastion) ; vérifié par `sshd -t` avant d'être posé |
| `tasks/ufw.yml` | autorise SSH **d'abord**, puis 9100 depuis la supervision, puis les règles du groupe, et **seulement ensuite** active UFW (entrée refusée par défaut) |
| `tasks/node_exporter.yml` | binaire téléchargé et vérifié par empreinte SHA-256, utilisateur système sans connexion, service systemd sur 9100 |

## Variables (`defaults/main.yml`)
| Variable | Défaut | Rôle |
|---|---|---|
| `reseau_bastion`, `reseau_ci`, `reseau_supervision` | `10.0.1.0/24`, `10.0.12.0/24`, `10.0.11.0/24` | sources autorisées par UFW (22 et 9100) |
| `ufw_regles_supplementaires` | `[]` | règles propres à un groupe : `playbooks/group_vars/role_<type>.yml` (`{ port, from, proto }`, `proto` = `tcp` par défaut) |
| `common_ufw_actif` | `true` | `false` : pose les règles sans activer UFW (dépannage) |
| `node_exporter_version` | `1.8.2` | version de node_exporter |

## L'utiliser
```bash
ansible-playbook -i inventories/tous/aws_ec2.yml playbooks/site.yml --limit <machine>
```
Sur un cluster Swarm qui tourne : un nœud à la fois, le `Leader` en dernier (`docs/runbooks/4-verifier/verifier_production.md`).

## Pièges
- Un port ouvert dans un security group doit aussi l'être ici (et inversement).
- Le module UFW **ajoute** des règles mais n'efface pas les anciennes : une règle retirée de la liste reste sur la machine (`sudo ufw status numbered` puis `sudo ufw delete <n>`).
- Tunnels SSH (`AllowTcpForwarding`) : **`no`** par défaut (`common_ssh_tcp_forwarding`), donc un `ssh -L` vers une machine privée est refusé (`administratively prohibited`). Ouverts en **`local`** (tunnels `-L` seulement, de la VM vers la machine) là où on en a besoin : la **supervision** (Grafana, Prometheus ; `playbooks/group_vars/role_monitoring.yml`) et le **staging** (interface de Mailpit ; `role_staging.yml`). Le bastion fait le rebond (`ProxyJump`).
- Clés SSH en plus de celles de l'équipe : `common_cles_ssh_supplementaires` (la clé de la CI sur le staging et les 3 nœuds de production, `role_staging.yml` et `role_swarm_node.yml`).
- `--check` : node_exporter échoue (« Source '/tmp/node_exporter-….tar.gz' does not exist ») après un redémarrage, car `/tmp` est vidé et la simulation ne télécharge rien. Sans effet en vrai. Piste : télécharger ailleurs que dans `/tmp`.
