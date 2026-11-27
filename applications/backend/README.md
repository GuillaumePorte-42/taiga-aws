# taiga-backend · Le Dev à Gilles

API de Taiga (Django), adaptée pour être testée, analysée et livrée en continu sur l'infrastructure AWS du projet. Ce dossier ne contient que les fichiers ajoutés par l'équipe. Le code du back vient du dépôt d'origine [taigaio/taiga-back](https://github.com/taigaio/taiga-back), à partir du commit `c8264ac6` du 28 septembre 2026, et les commandes ci-dessous se lancent dans une copie de ce dépôt.

## Ce que contient ce dépôt

Le code du back de Taiga, plus ce que le projet y ajoute :

| Élément | Rôle |
| --- | --- |
| `docker/Dockerfile` | Construction de l'image du back (Dockerfile officiel de Taiga, resté dans le dépôt d'origine) |
| `.gitlab-ci.yml` | Pipeline : tests, qualité, construction et publication de l'image |
| `tests/config_ci.py` | Réglages des tests pour la CI (base PostgreSQL du job) |
| `sonar-project.properties` | Configuration de l'analyse SonarCloud |

Les versions des outils et des images sont **figées** : aucune étiquette `latest`.

## La pipeline

| Étape | Job | Quand | Ce qu'il fait |
| --- | --- | --- | --- |
| test | `tests-rapides` | À chaque poussée | `manage.py check`, migrations sur une base PostgreSQL 17 vide, tests unitaires (`pytest tests/unit`) |
| qualite | `sonarcloud` | Sur `staging` | Analyse SonarCloud ; la quality gate bloque si le nouveau code introduit un bogue ou une faille |
| build | `construire-image` | Sur `staging`, si le code change | Construit l'image et la publie dans le registre GitLab, étiquetée `staging-<commit>` |

La suite complète de tests (environ 1 700 tests, 46 minutes) n'est pas lancée à chaque poussée : elle a servi à valider la version de PostgreSQL (PFD-76).

**Points à connaître :**

- Le job `sonarcloud` ne tourne que sur notre runner privé (étiquette `taiga-ci`), qui lui fournit le jeton SonarCloud : aucun secret n'est stocké dans GitLab.
- L'analyse de sécurité du back demande de la mémoire : `SONAR_SCANNER_JAVA_OPTS=-Xmx1536m` règle le moteur d'analyse.
- La couverture de code est exclue de la quality gate (`sonar.coverage.exclusions`) : les tests complets ne tournent pas sur `staging`.

## Lancer les tests en local

Prérequis : Python 3.11 et une base PostgreSQL 17 joignable.

```bash
docker run -d --name pg-test -e POSTGRES_USER=taiga -e POSTGRES_PASSWORD=taiga -e POSTGRES_DB=taiga -p 5432:5432 postgres:17
python3.11 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt -r requirements-devel.txt
export DJANGO_SETTINGS_MODULE=tests.config_ci POSTGRES_HOST=localhost
python manage.py check
python manage.py migrate --noinput
pytest -q tests/unit
```

Les identifiants `taiga` / `taiga` ne servent qu'à cette base jetable de test, jamais en staging ni en production.

## Construire l'image en local

```bash
docker build -t taiga-backend:local -f docker/Dockerfile .
```

## Du commit à la production

Ce dépôt **construit** l'image ; il ne la déploie pas. Le déploiement est géré par l'infrastructure, à la racine de ce dépôt :

1. Une merge request relue est fusionnée dans `staging` : la pipeline publie l'image `staging-<commit>`.
2. L'empreinte de l'image (`sha256:…`) est reportée dans l'infrastructure, qui déploie le staging et lance les tests de bout en bout et de charge.
3. Après validation, la **même image**, désignée par son empreinte, est déployée en production par un bouton manuel.

## Limites connues

- Taiga repose sur Django 3.x, hors support : le risque est compensé par le réseau privé, l'accès uniquement par l'ALB, et Trivy dans la CI de l'infrastructure.
- Pas de mesure de couverture de code dans la pipeline.

## Documentation

- Les décisions d'architecture (ADR-04 PostgreSQL, ADR-11 image du back, ADR-16 tests et qualité) et la page « Qualité du code : SonarCloud » sont dans l'espace Confluence du projet, qui est privé.
- Licence du code de Taiga : MPL 2.0, dans le dépôt d'origine.
