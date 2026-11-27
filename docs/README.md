# Documentation de `taiga-infrastructure` – par où commencer

Toutes les commandes se lancent **dans sa VM, à la racine du dépôt** (sauf indication). Ici : les **procédures** (runbooks) et les **références**. Le fonctionnement de chaque brique est dans le README de son dossier (voir en bas). Les explications « comment ça marche » et les décisions (ADR) sont dans Confluence.

## Je veux…
| … | Fichier |
|---|---|
| **Arriver sur le projet** | |
| savoir comment on travaille à plusieurs (branches, MR, `apply`) | [runbooks/1-equipe/travailler_en_equipe.md](runbooks/1-equipe/travailler_en_equipe.md) |
| me connecter aux machines (bastion, staging, nœuds), configurer SSH | [runbooks/1-equipe/se_connecter_ssh.md](runbooks/1-equipe/se_connecter_ssh.md) |
| ajouter ou changer mon IP publique | [runbooks/1-equipe/changer_son_ip.md](runbooks/1-equipe/changer_son_ip.md) |
| **Chaque jour** | |
| arrêter le soir, tout relancer le matin **dans l'ordre** (RDS, NAT, ALB, puis machines) et les contrôles du matin | [runbooks/2-chaque-jour/arreter_demarrer.md](runbooks/2-chaque-jour/arreter_demarrer.md) |
| éteindre ou rallumer la NAT | [runbooks/2-chaque-jour/eteindre_rallumer_nat.md](runbooks/2-chaque-jour/eteindre_rallumer_nat.md) |
| **Déployer** | |
| déployer le staging à la main, se connecter en `admin` au staging | [runbooks/3-deployer/deployer_staging.md](runbooks/3-deployer/deployer_staging.md) |
| savoir ce que lance le pipeline (staging, production, minutes, runner protégé) | [runbooks/3-deployer/comprendre_le_pipeline.md](runbooks/3-deployer/comprendre_le_pipeline.md) |
| mettre en production (promotion + bouton), changer sa version, revenir en arrière, administrer les comptes | [runbooks/3-deployer/deployer_production.md](runbooks/3-deployer/deployer_production.md) |
| **Vérifier** | |
| vérifier la production (ALB, security groups, UFW, Swarm, réseau entre nœuds) | [runbooks/4-verifier/verifier_production.md](runbooks/4-verifier/verifier_production.md) |
| prouver que la production survit à la perte d'un nœud | [runbooks/4-verifier/tester_haute_disponibilite.md](runbooks/4-verifier/tester_haute_disponibilite.md) |
| ouvrir Grafana et Prometheus (tunnel SSH) | [runbooks/4-verifier/ouvrir_grafana.md](runbooks/4-verifier/ouvrir_grafana.md) |
| voir les mails du staging (Mailpit), ajouter un destinataire SES, tester SES | [runbooks/4-verifier/verifier_les_mails.md](runbooks/4-verifier/verifier_les_mails.md) |
| lancer les tests du staging (E2E, charge), à la main ou dans la CI | [../tests/README.md](../tests/README.md) |
| **Les données** | |
| sauvegarder la production à la main, voir les sauvegardes, restaurer | [runbooks/5-donnees/sauvegarder_restaurer.md](runbooks/5-donnees/sauvegarder_restaurer.md) |
| **La CI** | |
| vérifier le runner GitLab privé, changer son token | [runbooks/6-ci/gerer_le_runner.md](runbooks/6-ci/gerer_le_runner.md) |
| gérer la clé SSH de la CI | [runbooks/6-ci/gerer_la_cle_ssh_ci.md](runbooks/6-ci/gerer_la_cle_ssh_ci.md) |
| **En cas de gros problème** | |
| Taiga ne répond pas ou répond mal (`502`, `503`, `2/3`…) : trouver où ça coince | [runbooks/7-urgence/diagnostiquer_taiga_en_panne.md](runbooks/7-urgence/diagnostiquer_taiga_en_panne.md) |
| tout détruire et tout reconstruire | [runbooks/7-urgence/reconstruire_tout.md](runbooks/7-urgence/reconstruire_tout.md) |
| tout remonter sur un **nouveau compte AWS** (comptes IAM, bucket du state, DNS chez IONOS, données) | [runbooks/7-urgence/changer_de_compte_aws.md](runbooks/7-urgence/changer_de_compte_aws.md) |

## Références (à consulter, pas à suivre)
| Quoi | Fichier |
|---|---|
| chaque paramètre de Parameter Store : qui l'écrit, qui le lit | [reference/parametres.md](reference/parametres.md) |
| versions des outils (VM, nœuds, pipeline) | [reference/versions_outils.md](reference/versions_outils.md) |
| schéma de la CI/CD (Mermaid et draw.io) | [schemas/cicd.md](schemas/cicd.md), [schemas/taiga-cicd.drawio](schemas/taiga-cicd.drawio) |
| schéma de l'infrastructure (réseau, instances, ports, security groups) | [schemas/infrastructure.png](schemas/infrastructure.png) |
| premières décisions d'architecture (ADR) | [adr/README.md](adr/README.md) |

## Les README des dossiers (le fonctionnement de chaque brique)
- Terraform, ordre des dossiers : `README.md` à la racine, puis `terraform/<dossier>/README.md` ;
- Ansible, ordre des playbooks : `ansible/README.md`, puis `ansible/roles/<rôle>/README.md` ;
- clés SSH de l'équipe : `cles_ssh/README.md` ; tests : `tests/README.md`.

## Ranger une nouvelle doc
- Une **procédure** (des commandes à suivre) → copier [runbooks/MODELE.md](runbooks/MODELE.md) dans `runbooks/<numéro-thème>/`, nom en **verbe + objet** (`restaurer_la_base.md`), unique dans le dépôt, sans date ; puis une ligne dans le tableau ci-dessus. Chaque commande est suivie de son **Attendu**.
- Une **référence** (un tableau à consulter) → `reference/`.
- Le **fonctionnement** d'un rôle ou d'un dossier → son propre `README.md`, à côté du code.
- Les thèmes : 1 équipe, 2 chaque jour, 3 déployer, 4 vérifier, 5 données, 6 CI, 7 urgence. Les numéros donnent l'ordre de lecture d'un nouvel arrivant.
