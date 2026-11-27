# taiga-frontend · Le Dev à Gilles

Interface web de Taiga, construite par notre pipeline et servie par nginx, pour l'infrastructure AWS du projet. Ce dossier ne contient que les fichiers ajoutés ou modifiés par l'équipe. Le code du front vient du dépôt d'origine [taigaio/taiga-front](https://github.com/taigaio/taiga-front), copié le 23 octobre 2026 (après la version 6.10.3), et les commandes ci-dessous se lancent dans une copie de ce dépôt.

## Ce que contient ce dépôt

Le code du front de Taiga (CoffeeScript, AngularJS), plus ce que le projet y ajoute :

| Élément | Rôle |
| --- | --- |
| `docker/Dockerfile` | Image nginx qui sert le front déjà compilé publié par Taiga (`taiga-front-dist` 6.10.3) |
| `.gitlab-ci.yml` | Pipeline : vérification de l'image, tests, qualité, construction et publication |
| `sonar-project.properties` | Configuration de l'analyse SonarCloud |

Les versions des outils et des images sont **figées** : aucune étiquette `latest`.

## Le front livré

L'image télécharge le front déjà compilé publié par Taiga (`taiga-front-dist` 6.10.3) et le sert avec nginx. Le code de ce dépôt est compilé par les tests unitaires, mais il n'est pas dans l'image. Construire le front nous-mêmes dans l'image reste une piste d'amélioration.

## La pipeline

| Étape | Job | Quand | Ce qu'il fait |
| --- | --- | --- | --- |
| test | `verifier-image` | Branches de travail | Construit l'image sans la publier, pour vérifier que le Dockerfile fonctionne |
| test | `tests-unitaires` | `staging` et `production` | Compile le front puis lance Karma dans Chromium sans fenêtre (`npm run ci:test`) |
| qualite | `sonarcloud` | Sur `staging`, si `app/` change | Analyse SonarCloud, **informative** (`allow_failure`) |
| build | `construire-image` | Sur `staging` | Construit l'image et la publie dans le registre GitLab, étiquetée `staging-<commit>` |

**Points à connaître :**

- Huit dépendances sont déclarées en SSH vers GitHub : la pipeline les force en HTTPS, comme la CI officielle de Taiga.
- SonarCloud n'analyse pas le CoffeeScript : seuls les quelques fichiers JavaScript le sont. C'est pourquoi la quality gate ne bloque pas la pipeline. La qualité du front repose sur ses tests.
- Les traductions (JSON), le CSS compilé et les dépendances sont exclus de l'analyse.

## Lancer les tests en local

Prérequis : Node 16.20.2 (imposé par les dépendances du front) et Chromium.

```bash
git config --global url."https://github.com/".insteadOf ssh://git@github.com/
npm ci
CHROME_BIN=$(command -v chromium || command -v chromium-browser) npm run ci:test
```

## Construire l'image en local

```bash
docker build -t taiga-frontend:local -f docker/Dockerfile .
```

## Du commit à la production

Ce dépôt **construit** l'image ; il ne la déploie pas. Le déploiement est géré par l'infrastructure, à la racine de ce dépôt :

1. Une merge request relue est fusionnée dans `staging` : la pipeline publie l'image `staging-<commit>`.
2. L'empreinte de l'image (`sha256:…`) est reportée dans l'infrastructure, qui déploie le staging et lance les tests de bout en bout et de charge.
3. Après validation, la **même image**, désignée par son empreinte, est déployée en production par un bouton manuel. Un retour arrière se fait par `git revert` de cette empreinte (testé en 20 minutes).

## Limites connues

- Node 16 est hors support, mais imposé par les dépendances du front de Taiga.
- Le CoffeeScript n'est pas analysé par SonarCloud.

## Documentation

- Les décisions d'architecture (ADR-11 promotion des images, ADR-16 tests et qualité) et la page « Qualité du code : SonarCloud » sont dans l'espace Confluence du projet, qui est privé.
- Licence : celle du projet Taiga d'origine, AGPL v3 (voir [`LICENSE`](LICENSE)), qui s'applique au Dockerfile modifié.
