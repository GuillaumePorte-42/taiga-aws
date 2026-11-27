# Runbook – Tester la haute disponibilité de la production

**Pourquoi** : prouver que Taiga continue de répondre quand un nœud tombe (démo, après un changement réseau ou Swarm, avant une soutenance). On arrête le nœud **leader**, on mesure les erreurs vues par un utilisateur, puis on le rallume.

**Où** : dans sa VM, agent SSH chargé, config SSH à jour. **Prévenir l'équipe** : un nœud de production est arrêté pendant quelques minutes ; personne ne lance de playbook sur la prod pendant le test.

## Ce qui doit être allumé
| Pour… | Il faut |
|---|---|
| le test | RDS `available`, 3 nœuds, ALB (la NAT n'est pas nécessaire) |

## 1. Partir d'un état sain
```bash
ssh node-1 'sudo docker node ls; sudo docker service ls'
```
Attendu : 3 nœuds `Ready` / `Active`, **tous** les services en `3/3` ou `1/1`. Sinon, on ne lance pas le test (`docs/runbooks/7-urgence/diagnostiquer_taiga_en_panne.md`). Noter le nœud `Leader` : c'est lui qu'on arrête.

## 2. Lancer la sonde (deuxième terminal)
```bash
while true; do echo "$(date +%T) $(curl -s -o /dev/null -w '%{http_code}' --max-time 5 https://taiga-ledevagilles.fr/api/v1/)"; sleep 1; done | tee ha-test.log
```
Attendu : une ligne par seconde, `HH:MM:SS 200`. La laisser tourner jusqu'à la fin.

## 3. La panne
Console AWS, **EC2 › Instances** : cocher **seulement** le nœud leader, *Instance state › Stop instance* (pas *Terminate*). Noter l'heure.

## 4. Pendant la panne (depuis un nœud resté allumé)
```bash
ssh node-2 'sudo docker node ls; sudo docker service ls'
```
Attendu : le nœud arrêté `Down` / `Unreachable` ; **un nouveau `Leader`** élu seul ; les services à une copie relancés ailleurs (on peut voir `2/1` un moment : l'ancienne copie, injoignable, est encore comptée). Les services à 3 copies peuvent encore afficher `3/3` : les copies du nœud perdu restent comptées faute de nouvelles ; la sonde montre que les deux autres servent.

## 5. Le retour
Console : *Start instance*. Après 2 à 3 minutes :
```bash
ssh node-1 'sudo docker node ls; sudo docker service ls'
```
Attendu : le nœud `Ready` / `Reachable` (il **ne redevient pas** leader : Raft garde le leader tant qu'il répond) ; tout en `3/3` ou `1/1`.

## Vérifier : le bilan
Arrêter la sonde (`Ctrl+C`), puis :
```bash
awk '{print $2}' ha-test.log | sort | uniq -c
```
Attendu : presque tout en `200`, quelques `502` ou `000` au moment de la panne seulement, rien au retour du nœud.

Résultat du 03/11/2026 (arrêt du leader node-2) : 2 × `502` et 2 × `000` entre 15:25:59 et 15:26:09, soit ~16 s de perturbation, puis `200` ; nouveau leader node-1 ; `taiga-events` relancé ailleurs ; retour à `3/3` sans intervention.

## Dépannage
| Symptôme | Cause probable | Que faire |
|---|---|---|
| état de départ en `2/3` | copie bloquée, nœud en `Drain`, réseau entre nœuds | `docs/runbooks/7-urgence/diagnostiquer_taiga_en_panne.md` |
| erreurs pendant plus de 2 minutes | les nœuds restants ne joignent pas les services des autres (ESP bloqué) | test `wget` de la section 3 du runbook de diagnostic |
| `The swarm does not have a leader` | 2 nœuds arrêtés en même temps | ne jamais arrêter plus d'un nœud ; rallumer |

## Pièges
- Ce test couvre **l'application** (Swarm, ALB, EFS). La base RDS est en Single-AZ : si sa zone tombe, Taiga tombe. Piste : `multi_az = true` (PFD-38).
- Les sauvegardes suivent la bascule : le script vérifie « suis-je le leader ? » à chaque fois (`docs/runbooks/5-donnees/sauvegarder_restaurer.md`).
