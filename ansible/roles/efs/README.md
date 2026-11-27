# Rôle `efs`

Monte le stockage partagé **EFS** de la production dans `/mnt/efs` sur les 3 nœuds, de façon permanente. Taiga y range ses fichiers statiques et ses **médias** (pièces jointes, exports), visibles des 3 nœuds. Lancé par `playbooks/efs.yml` (inventaire `production`).

## Ce qu'il fait
| Tâche | Quoi |
|---|---|
| vérification | s'arrête tout de suite si `efs_id` est vide |
| client NFS | `nfs-common` |
| point de montage | `/mnt/efs` (`0755`) |
| montage | `<efs_id>.efs.eu-west-3.amazonaws.com:/` en NFS 4.1, monté **et** inscrit dans `/etc/fstab` (remonté au redémarrage) |

## D'où vient `efs_id`
Écrit par Terraform (`terraform/production/efs.tf`, ressource `aws_ssm_parameter.efs_id`) dans **`/taiga/production/efs_id`**, lu par `lookup` dans `inventories/production/group_vars/all.yml`. Un EFS recréé (reconstruction, nouveau compte) a un nouvel ID : rien à recopier à la main (depuis le 04/11 ; avant, l'ID était écrit en dur).

## Variables (`defaults/main.yml`)
| Variable | Défaut | Rôle |
|---|---|---|
| `efs_id` | `""` | ID de l'EFS (fs-…) ; en production, lu dans Parameter Store |
| `efs_region` | `eu-west-3` | région |
| `efs_mount_point` | `/mnt/efs` | dossier de montage |
| `efs_mount_options` | `nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport,_netdev` | options recommandées par AWS (`_netdev` : attendre le réseau au démarrage) |

## L'utiliser
```bash
ansible-playbook -i inventories/production/aws_ec2.yml playbooks/efs.yml
ansible -i inventories/production/aws_ec2.yml role_swarm_node -m debug -a "var=efs_id"
```
Attendu : `failed=0`, puis le même `fs-…` pour les 3 nœuds.

## Pièges
- Le SG `efs` n'autorise le port 2049 que depuis le SG `nodes` : le staging ne peut pas le monter (voulu).
- Un EFS recréé est **vide** : restaurer les médias depuis la sauvegarde (`docs/runbooks/5-donnees/sauvegarder_restaurer.md`).
