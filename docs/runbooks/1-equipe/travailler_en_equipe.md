# Routine d'équipe – Git, MR, Terraform et playbooks

**Pourquoi** : les mêmes gestes pour tout le monde, à chaque fois, pour ne jamais effacer le travail d'un collègue ni casser `staging`. Toutes les commandes se lancent **dans sa VM, à la racine de `taiga-infrastructure`**.

## Le cycle en un coup d'œil
```
1. partir de staging à jour → 2. créer sa branche → 3. travailler et commiter
→ 4. récupérer staging dans sa branche → 5. pousser → 6. ouvrir la MR et la relire
→ 7. fusionner sur GitLab → 8. appliquer (si besoin) et prévenir → 9. ranger
```
Le seul `git merge` qu'on tape soi-même, c'est celui de l'étape 4 (staging → sa branche). La fusion de sa branche dans `staging` se fait **sur GitLab** (étape 7), jamais en local.

## 1. Partir de `staging` à jour
```bash
git switch staging
git pull
```
Attendu : `Déjà à jour` ou `Avance rapide`. Un message `divergentes` ou `en avance de N commits` : quelqu'un a commité directement sur `staging` en local → **on s'arrête** (section « En cas de souci »).

## 2. Créer sa branche
```bash
git switch -c ci-PFD-<ticket>-<sujet>
```
Attendu : `Basculement sur la nouvelle branche 'ci-PFD-…'`. Un sujet = une branche, créée **avant** la première modification (`git status` : la 1re ligne dit sur quelle branche on est).

📘 Le préfixe **`ci-`** : les branches `ci-*` sont **protégées** dans GitLab (motif créé le 04/11), et le runner privé `taiga-ci` n'exécute que les branches protégées (il détient la clé SSH de la production). Sans `ci-`, un job qui a besoin du runner privé reste en *pending*. Supprimer une branche `ci-…` : depuis GitLab (*Code → Branches*), rôle Maintainer.

## 3. Travailler et commiter
Après chaque petit morceau qui marche :
```bash
git status
```
Attendu : la liste des fichiers modifiés : seulement ceux qu'on a voulu toucher.
```bash
git diff
```
Attendu : seulement ses propres changements. Une ligne rouge qu'on n'a pas voulue → la remettre avant de commiter.
```bash
git add <fichier1> <fichier2>
git commit -m "PFD-<ticket> : <ce qui change, en une phrase>"
```
- Ajouter les fichiers **par leur nom** (pas `git add .`) : on évite d'embarquer un `__pycache__/`, un rapport, un fichier de test.
- Terraform : `terraform fmt -recursive terraform/` avant de commiter ; pour tester, `plan` seulement.
- **Jamais d'`apply` depuis sa branche.** Exception (tester une ressource pour de vrai) : **prévenir avant** (« j'applique `<dossier>` depuis ma branche, personne n'applique ce dossier avant ma fusion »).
- **Ansible : tester sa branche sur le staging depuis sa VM, avant la MR** : `--check --diff`, puis **le vrai lancement** (prévenir : « le staging tourne ma branche ») et `verifier_taiga.yml`. `--check` montre ce qui change, pas si ça marche (le 04/11 : variable oubliée, 502, 404, rien ne se voyait en simulation). Le pipeline, après la fusion, sert à **prouver** (déploiement en `changed=0`, tests verts), pas à découvrir. Ne pas laisser le staging sur sa branche : fusionner, ou *Run pipeline* sur `staging` pour revenir à la référence. **Jamais pour la production.**
- Chemins : les commandes Ansible se lancent depuis `ansible/`, les commandes Git et Terraform depuis la racine (un `git archive` lancé dans `ansible/` n'exporte que `ansible/`).

## 4. Récupérer `staging` dans sa branche (avant chaque MR)
Pendant qu'on travaillait, les collègues ont pu fusionner. Il faut **leur travail + le sien** dans sa branche, sinon la MR peut effacer le leur.

D'abord, tout doit être commité :
```bash
git status
```
Attendu : `rien à valider, la copie de travail est propre`. Sinon, revenir à l'étape 3.
```bash
git fetch
git merge origin/staging
```
Attendu, l'un des trois :
- `Déjà à jour` : personne n'a rien fusionné, passer à l'étape 5 ;
- `Merge made by the 'ort' strategy` (un éditeur peut s'ouvrir pour le message : enregistrer et fermer) : Git a créé **tout seul** un commit de fusion, **rien à recommiter** ; passer à l'étape 5 ;
- `CONFLIT (contenu) : Conflit de fusion dans <fichier>` : section ci-dessous.

### En cas de conflit
Git s'arrête : le même endroit a été modifié des deux côtés.
```bash
git status
```
Attendu : les fichiers en conflit sous `Chemins non fusionnés`. Dans chacun, Git a mis les deux versions :
```
<<<<<<< HEAD
ma version
=======
la version de staging
>>>>>>> origin/staging
```
Garder **les deux** quand les deux ajouts sont utiles (le cas le plus fréquent), supprimer les trois lignes de marqueurs, puis :
```bash
git add <fichier>
git commit
```
Attendu : le commit de fusion est créé. **Dans le doute, ne pas deviner** : `git merge --abort` (tout revient comme avant l'étape 4) et regarder à deux.

## 5. Pousser sa branche
```bash
git push -u origin PFD-<ticket>-<sujet>
```
(`git push` tout court les fois suivantes.) Attendu : GitLab affiche un lien `Create merge request`.

## 6. Ouvrir la MR et la relire
- Vers `staging`, en *Draft* tant que ce n'est pas fini.
- Description : ce qui change, comment on l'a testé (preuve), ce que l'équipe doit faire après (`apply`, playbook).
- Onglet **Changes** : lire les **lignes rouges** (supprimées). Une ligne rouge dans un fichier qu'on n'a pas voulu toucher = on efface le travail d'un collègue → **ne pas fusionner**, revenir à l'étape 4.
- Le **style** (lint, espaces, majuscules) dans une MR à part : sinon, 4 lignes perdues se cachent dans 1 000 lignes de style.
- Pipeline vert obligatoire, relecture par un collègue.

## 7. Fusionner, sur GitLab
Bouton **Merge** de la MR, **sans squash**. Cocher « Delete source branch ».

**Promotion `staging` → `production`** (mettre en production) : une MR de `staging` vers `production`, **squash décoché** (les deux branches doivent garder exactement les mêmes commits, sinon la MR suivante réafficherait d'anciens changements ou créerait des conflits) et **« Delete source branch » décoché** (la source, c'est `staging`). Puis le bouton du déploiement : `docs/runbooks/3-deployer/deployer_production.md`.

## 8. Après la fusion : celui qui a fusionné
```bash
git switch staging
git pull
```
Attendu : `Avance rapide`, avec son commit.
- Si l'infra change : **lui seul** fait l'`apply`, depuis `staging` à jour, après avoir lu le `plan` (`docs/runbooks/…` du sujet).
- Si un playbook doit être relancé : **lui seul**, en prévenant (« je lance `<playbook>` sur `<env>` »).
- Message à l'équipe : « MR fusionnée : <ce qui change> ; `apply` / playbook fait (ou rien à faire) ; pensez à récupérer `staging` dans vos branches ».

## 9. Ranger
```bash
git fetch --prune
git branch -d PFD-<ticket>-<sujet>
```
Attendu : `Branche … supprimée`. Refusé (`pas totalement fusionnée`) : vérifier que son travail est bien dans `staging` (`git diff staging PFD-…` vide) avant `git branch -D`.

## Les autres, après une fusion d'un collègue
```bash
git switch staging
git pull
```
Branche en cours : `git switch <sa-branche>`, puis l'étape 4. Si `commun/` a changé : `terraform -chdir=terraform/commun output -raw ssh_config > ~/.ssh/taiga_config`.

## Règles d'or
1. On ne travaille **jamais** directement sur `staging`, et on ne **pousse jamais** depuis `staging` : un Maintainer peut pousser sur une branche protégée, ce qui contournerait la MR, la relecture… et déclencherait le déploiement.
2. Avant chaque MR : `git fetch` + `git merge origin/staging` (étape 4).
3. On lit les lignes rouges avant de fusionner.
4. `apply` uniquement depuis `staging` à jour, après la fusion, **une personne à la fois**. Un `plan` avec un `destroy` inattendu : **on s'arrête et on prévient**.
5. **Un seul playbook à la fois sur les mêmes machines**, comme pour l'`apply` : on prévient avant. Deux playbooks croisés peuvent échouer, ou redémarrer deux nœuds Swarm ensemble.
6. En production, quand on redémarre quelque chose (Docker, `drain`) : **une machine à la fois**, et on attend `docker service ls` tout en `3/3` / `1/1` avant la suivante.
7. Rien de secret dans Git (clés privées, `.tfvars`, `.tfstate`) ; les secrets vivent dans Parameter Store.
8. Le soir : on arrête ou on détruit ce qui coûte : `docs/runbooks/2-chaque-jour/arreter_demarrer.md`.

## En cas de souci
| Problème | Réflexe |
|---|---|
| `git pull` sur `staging` : « branches divergentes » / « en avance de N commits » | un commit a été fait sur `staging` en local. Le mettre de côté : `git branch sauvegarde-<date> staging`, vérifier qu'il est déjà sur GitLab (`git diff staging origin/staging` vide) ou le reprendre sur une branche, puis `git reset --hard origin/staging` |
| j'ai commité sur `staging` en local au lieu d'une branche (**pas encore poussé**) | `git switch -c ci-PFD-<ticket>-<sujet>` (la branche garde le commit), puis `git branch -f staging origin/staging` (remet `staging` au niveau de GitLab), puis `git log --oneline -3` : son commit au-dessus de `origin/staging` |
| `git pull` refusé (fichier local) | lire le chemin cité ; un `.terraform.lock.hcl` local : `rm` (non suivi) ou `git restore` (modifié) |
| conflit au `merge` | étape 4, « En cas de conflit » ; dans le doute `git merge --abort` et on regarde à deux |
| des lignes d'un collègue ont disparu après une fusion | les remettre par une petite MR ; vérifier sur les machines si elles étaient déjà appliquées |
| verrou du state (`.tflock`) | vérifier avec l'équipe que personne n'applique, puis `terraform force-unlock <ID>` |
| `AuthFailure` | `sudo timedatectl set-ntp true` |
