# Runbook – Arrêter le soir, redémarrer le matin

**Pourquoi** : on paie à l'heure les instances allumées, la NAT, l'ALB et la base RDS. Le soir, on les arrête ou on les détruit ; le stockage presque vide (EFS, buckets, Parameter Store, disque de la RDS) ne coûte presque rien et reste.

**Où** : dans sa VM, à la racine de `taiga-infrastructure`, sur `staging` à jour.

**Qui** : celui qui finit la journée (le soir) ou qui commence (le matin), **après avoir prévenu l'équipe** (« j'arrête tout pour ce soir », « je rallume »). Une seule personne à la fois.

## Ce qui coûte, et ce qu'on en fait
| Ressource | Facturée | Le soir |
|---|---|---|
| Instances (bastion, supervision, CI, staging, nœuds) | à l'heure quand elles tournent ; disque seul quand elles sont arrêtées | **arrêter** (pas détruire : on garde leur configuration et leurs données) |
| NAT Gateway | à l'heure (~1,20 $/jour) | **détruire** (`-target`), **jamais dans la console** |
| ALB | à l'heure (~0,60 $/jour) | **détruire** (`-target`) si personne ne s'en sert |
| RDS `taiga-db` | à l'heure quand elle tourne ; stockage seul quand elle est arrêtée | **arrêter**, **jamais détruire** (données de la production) |
| EFS, buckets, Parameter Store, certificat, target groups | au stockage, ≈ 0 € | garder |

## Le soir
1. **Arrêter la base** :
   ```bash
   aws rds stop-db-instance --db-instance-identifier taiga-db --region eu-west-3 --query "DBInstance.DBInstanceStatus" --output text
   ```
   Attendu : `stopping`. AWS la redémarre seul après 7 jours d'arrêt.
2. **Arrêter toutes les instances du projet** :
   ```bash
   aws ec2 stop-instances --instance-ids $(aws ec2 describe-instances --filters Name=tag:Projet,Values=taiga-ledevagilles Name=instance-state-name,Values=running --query "Reservations[].Instances[].InstanceId" --output text)
   ```
   Attendu : une liste d'instances qui passent de `running` à `stopping`.
3. **Détruire la NAT** (détail : `docs/runbooks/2-chaque-jour/eteindre_rallumer_nat.md`) :
   ```bash
   terraform -chdir=terraform/reseau destroy -target=aws_nat_gateway.main -target=aws_eip.nat
   ```
   Attendu : `3 to destroy` (NAT, Elastic IP, route). Rien d'autre. **Jamais de suppression dans la console** : Terraform ne le saurait pas, l'IP élastique resterait payante, et le matin devient imprévisible (vécu le 05/11 au soir).
4. **Détruire l'ALB** (certificat et target groups gardés) :
   ```bash
   terraform -chdir=terraform/commun destroy -target=aws_lb.taiga
   ```
   Avant `yes`, lire la liste : seulement `aws_lb.taiga`, ses écouteurs, ses règles et les **enregistrements DNS** qui pointent vers lui (`taiga-ledevagilles.fr` et `staging.…` disparaissent jusqu'au matin). **Un certificat, un target group ou une instance dans la liste → répondre `no`.**

## Le matin : l'ordre compte
**Le réseau d'abord, les machines ensuite.** Une machine qui démarre avant la NAT ne peut rien télécharger (une image Docker ratée reste bloquée en `Preparing`), et une supervision qui démarre avant le DNS garde en mémoire « ce nom n'existe pas » (sondes rouges pendant ~15 min). Vécu le 06/11 : 45 min perdues.

0. **L'heure de la VM** (sinon `AuthFailure`) :
   ```bash
   date -u; curl -sI https://ec2.eu-west-3.amazonaws.com | grep -i '^date'
   ```
   Attendu : les deux heures à quelques secondes près. Sinon : `sudo timedatectl set-ntp true && sudo systemctl restart systemd-timesyncd`.
1. **Démarrer la base en premier** (5 à 10 min, elle démarre pendant la suite) :
   ```bash
   aws rds start-db-instance --db-instance-identifier taiga-db --region eu-west-3 --query "DBInstance.DBInstanceStatus" --output text
   ```
   Attendu : `starting`.
2. **Rallumer la NAT** :
   ```bash
   terraform -chdir=terraform/reseau apply
   ```
   Attendu : `3 to add` (NAT, Elastic IP, route), **0 to destroy**. L'`apply` attend que la NAT soit prête (1 à 3 min). Contrôle :
   ```bash
   aws ec2 describe-nat-gateways --filter Name=tag:Name,Values=taiga-nat Name=state,Values=available --query "NatGateways[].State" --output text
   ```
   Attendu : `available`. Rien → attendre, ne pas passer à la suite.
3. **Recréer l'ALB et le DNS** :
   ```bash
   terraform -chdir=terraform/commun apply
   ```
   Attendu : l'ALB, ses écouteurs, ses règles et les 2 enregistrements DNS ; **0 to destroy**. Cet `apply` relit aussi l'IP de la NAT pour la règle 11 (accès de la CI et de la supervision au staging) : toujours **après** l'étape 2. Contrôle :
   ```bash
   dig +short taiga-ledevagilles.fr; dig +short staging.taiga-ledevagilles.fr
   ```
   Attendu : des IP (celles de l'ALB) pour les deux noms.
4. **Démarrer les instances, toutes ensemble** (les 3 nœuds en même temps : un nœud seul n'a pas de quorum, Swarm reste figé) :
   ```bash
   aws ec2 start-instances --instance-ids $(aws ec2 describe-instances --filters Name=tag:Projet,Values=taiga-ledevagilles Name=instance-state-name,Values=stopped --query "Reservations[].Instances[].InstanceId" --output text)
   ```
   Attendu : toutes les instances passent de `stopped` à `pending`.
5. **La routine SSH** (chacun) : `docs/runbooks/1-equipe/se_connecter_ssh.md`, « La routine ». L'IP du bastion a changé : `terraform -chdir=terraform/commun output -raw ssh_config > ~/.ssh/taiga_config`.
6. **Vérifier**, 3 à 5 minutes après le démarrage (le temps que la base soit `available` et que les cibles de l'ALB passent `healthy`) : « Les contrôles du matin » ci-dessous.

Aucun playbook à relancer : sur le staging, `restart: unless-stopped` relance les conteneurs ; en production, Swarm relance les services, et le back se reconnecte dès que la base est `available`.

## Les contrôles du matin (10 min)
1. **Les sites** :
   ```bash
   aws rds describe-db-instances --db-instance-identifier taiga-db --query "DBInstances[0].DBInstanceStatus" --output text --region eu-west-3
   curl -sI https://taiga-ledevagilles.fr | head -1
   curl -sI https://staging.taiga-ledevagilles.fr | head -1
   curl -s -o /dev/null -w '%{http_code}\n' https://taiga-ledevagilles.fr/admin/
   ```
   Attendu : `available`, `HTTP/2 200` deux fois, puis `403`.
2. **Les services de la production** :
   ```bash
   ssh node-1 'sudo docker node ls; sudo docker service ls'
   ```
   Attendu : 3 nœuds `Ready`, tout en `3/3` ou `1/1`. Un service en `0/1` : lire sa colonne *ERROR* (pas ses journaux : un conteneur jamais démarré n'en a pas) :
   ```bash
   ssh node-1 'sudo docker service ps taiga_taiga-events --no-trunc | head -3'
   ```
   `Preparing` + `registry-1.docker.io … deadline exceeded` = image pas téléchargée au démarrage (NAT pas encore là). Vérifier que le nœud sort (`curl -s -o /dev/null -w '%{http_code}\n' https://registry-1.docker.io/v2/` → `401`), puis relancer la tâche :
   ```bash
   ssh node-1 'sudo docker service update --force taiga_taiga-events'
   ```
   Attendu : `verify: Service converged`, puis `1/1`. Des lignes `Failed … No such container` dans `docker service ps` sont des **traces des arrêts de machines**, pas des pannes ; seules les `non-zero exit` sont de vrais plantages.
3. **cAdvisor** sur les 3 nœuds (bug connu : il démarre parfois « aveugle », vu 2 rallumages sur 2 en production) :
   ```bash
   for n in node-1 node-2 node-3; do echo "== $n"; ssh $n "sudo docker logs cadvisor 2>&1 | grep -i 'container factory' | tail -1"; done
   ```
   Attendu : `Registration of the docker container factory successfully`. Si `client version 1.24 is too old` :
   ```bash
   for n in node-1 node-2 node-3; do ssh $n 'sudo docker restart cadvisor'; done
   ```
   puis relancer la boucle de contrôle. Dans Grafana, la case « Conteneurs Taiga » doit afficher une valeur pour la production. L'alerte `CadvisorAveugle` le signale aussi après 5 min.
4. **Grafana** (`docs/runbooks/4-verifier/ouvrir_grafana.md`) : « État du site » en vert, alertes déclenchées en baisse. **Sondes rouges en code 0 alors que `curl` marche depuis la VM** → regarder le DNS depuis la supervision avant de chercher plus loin :
   ```bash
   ssh monitoring "dig taiga-ledevagilles.fr @169.254.169.253 | grep -E 'status|IN'"
   ```
   `NXDOMAIN` = réponse négative gardée en cache (la supervision a demandé le nom avant que `commun/` le recrée) : attendre la fin du délai (chiffre de la ligne `SOA`), rien à réparer. `NOERROR` avec les IP de l'ALB = le DNS va bien, le problème est ailleurs.

## Pièges
- **Un seul `apply` à la fois** : se mettre d'accord sur qui fait le matin.
- **Base pas encore `available`** : la production affiche sa page, mais la connexion échoue ; attendre, Swarm relance le back tout seul.
- **Instances démarrées avant la NAT** : images non téléchargées (`Preparing`), `apt` bloqué, `ParameterNotFound`, runner sans job. Respecter l'ordre ; sinon `update --force` des services bloqués.
- **Supervision démarrée avant le DNS** : sondes en code 0 pendant ~15 min (cache négatif du résolveur d'AWS). Hypothèse du 06/11, non prouvée : le `NXDOMAIN` n'a pas pu être vu, il avait déjà expiré.
- **Un nœud rallumé seul** : 1 manager sur 3, pas de quorum, Swarm figé ; au retour des autres, il relance tout d'un coup (`Failed … non-zero exit` vus le 05/11). Toujours les 3 ensemble.
- L'IP publique du bastion change à chaque redémarrage : sans la routine SSH, `ssh bastion` part vers l'ancienne IP (*timeout*).
- `stop-instances` arrête **toutes** les machines du projet, y compris celles d'un collègue qui travaille encore : prévenir avant.
- `Error: … provider not installed` : faire `terraform -chdir=<dossier> init` (rapide avec le cache `plugin_cache_dir` de `~/.terraformrc`).
- Une RDS arrêtée **redémarre toute seule au bout de 7 jours** (règle d'AWS) : pendant une longue pause, vérifier son état et la réarrêter.
- Le soir, l'alerte `InstanceArretee` (et les sondes du site) sonnent sur Discord pendant l'arrêt si la supervision tourne encore : normal.
- La cron de sauvegarde de la production est à 16 h (heure de Paris : le rôle `common` règle les machines sur `Europe/Paris`) : machines éteintes avant 16 h → pas de sauvegarde ce jour-là (en lancer une à la main : `docs/runbooks/5-donnees/sauvegarder_restaurer.md`, partie 4).

## Pistes
- Un script qui enchaîne les étapes 1 à 4 et s'arrête au premier contrôle raté.
- Corriger cAdvisor pour de bon (version plus récente, ou démarrage après que Docker est prêt) au lieu du `restart` du matin.
