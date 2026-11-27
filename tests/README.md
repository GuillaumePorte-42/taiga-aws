# Tests du staging déployé (PFD-67)

Deux tests qui vérifient **notre déploiement** (DNS, HTTPS, ALB, gateway, front, back, base), pas le code de Taiga (ça, ce sont les tests unitaires Karma du front) :

| Dossier | Outil | Ce qu'il prouve |
|---|---|---|
| `e2e/` | Playwright 1.64.1 + pytest | un utilisateur se connecte dans un vrai navigateur (Chromium *headless*) et arrive sur son tableau de bord |
| `charge/` | Locust 2.47.0 | des utilisateurs virtuels se connectent à l'API puis lisent leur profil et leurs projets ; on lit les erreurs et le temps de réponse |

## Dans la CI (depuis le 03/11/2026)
Sur `staging`, le pipeline lance les deux tests sur le runner privé, après le déploiement (détail : `docs/runbooks/3-deployer/comprendre_le_pipeline.md`) :

| Job | Quand | Résultat |
|---|---|---|
| `tests-e2e` | quand le staging ou les tests changent, ou *Run pipeline* | longueur du mot de passe (44), puis `1 passed` ; captures d'écran en artefact si échec |
| `tests-charge` | automatique si l'image ou le rôle `taiga` change ; sinon bouton ▶ | 20 utilisateurs, 1 min ; `rapport-locust.html` en artefact (30 jours) ; `LOCUST_UTILISATEURS=50` au lancement manuel |

La charge attend l'E2E : pas de test de charge sur une application cassée. Le runner joint le staging grâce à la règle 11 de l'ALB (IP de la NAT).

On peut toujours les lancer **à la main depuis sa VM** (son IP doit être autorisée sur la règle staging de l'ALB) : ci-dessous.

## Le compte de test
- `e2e-test`, utilisateur **normal** du staging (ni staff ni superuser) ;
- mot de passe **aléatoire, connu de personne** : `/taiga/staging/e2e_password` (`SecureString`). Il n'est jamais écrit dans le code : les tests le lisent dans la variable `E2E_PASSWORD`.

Recréer le mot de passe (sans jamais l'afficher) :
```bash
aws ssm put-parameter --name /taiga/staging/e2e_password --type SecureString --overwrite --value "$(openssl rand -base64 32)" --region eu-west-3
aws ssm get-parameter --name /taiga/staging/e2e_password --with-decryption --region eu-west-3 --query Parameter.Value --output text | ssh staging 'sudo docker exec -i taiga-taiga-back-1 python manage.py shell -c "import sys; from django.contrib.auth import get_user_model; u = get_user_model().objects.get(username=\"e2e-test\"); u.set_password(sys.stdin.read().strip()); u.save(); print(\"mot de passe pose\")"'
```

## Installer (une fois, depuis la racine du dépôt)
Chaque outil a son environnement Python (`.venv/`, ignoré par Git) et ses versions figées (`requirements.txt`).
```bash
python3 -m venv tests/e2e/.venv
tests/e2e/.venv/bin/pip install -r tests/e2e/requirements.txt
tests/e2e/.venv/bin/playwright install --with-deps chromium

python3 -m venv tests/charge/.venv
tests/charge/.venv/bin/pip install -r tests/charge/requirements.txt
```
Sur Debian, si `ensurepip is not available` : `sudo apt install python3.11-venv`.

## Lancer
D'abord le mot de passe, dans le terminal seulement (l'historique garde la commande, pas la valeur) :
```bash
export E2E_PASSWORD="$(aws ssm get-parameter --name /taiga/staging/e2e_password --with-decryption --region eu-west-3 --query Parameter.Value --output text)"
```

**E2E** :
```bash
tests/e2e/.venv/bin/pytest tests/e2e -v
```
Attendu : `1 passed`. Pour vérifier que le test sait échouer : `E2E_PASSWORD=mauvais tests/e2e/.venv/bin/pytest tests/e2e -v` → `1 failed` sur `to_have_url`.

**Charge** (10 utilisateurs, +2 par seconde, 1 minute, rapport HTML) :
```bash
tests/charge/.venv/bin/locust -f tests/charge/locustfile.py --host https://staging.taiga-ledevagilles.fr --headless -u 10 -r 2 -t 1m --html tests/charge/rapport.html
```
Le rapport (`rapport*.html`, ignoré par Git) s'ouvre depuis Windows en le copiant dans le dossier partagé : `cp tests/charge/rapport.html ~/projects/transfert/rapports/`.

## Lire le rapport Locust
- **# Fails** : doit rester à 0 ;
- **95%ile** (p95) : 95 % des requêtes ont répondu plus vite que cette valeur ; plus parlant que la moyenne ;
- **RPS** : requêtes par seconde.

Références du 02/11/2026 :

| Utilisateurs | Requêtes | Échecs | Débit | Médiane | p95 (projets / profil) | Connexion (moyenne) |
|---|---|---|---|---|---|---|
| 10 (`-u 10 -r 2 -t 1m`) | 299 | 0 | ~5 req/s | ~48 ms | 69 / 83 ms | ~400 ms |
| 50 (`-u 50 -r 5 -t 2m`) | 2828 | 0 | ~24 req/s | ~55 ms | 160 / 220 ms (~100-130 ms une fois tout le monde arrivé) | ~840 ms |

La connexion (`POST /api/v1/auth`) est lente : normal, le mot de passe est vérifié par un hachage volontairement coûteux ; elle n'a lieu qu'une fois par utilisateur. À 50, les connexions simultanées occupent le processeur au démarrage et les lectures attendent derrière : c'est ce qui tire le p95 du tableau.

## Pièges
- **Ne pas reprendre les E2E du dépôt front** (`frontend/e2e/`) : Protractor et Selenium abandonnés, écrits pour un Taiga local (`localhost:9001`, compte `admin`/`123123`), hors de la CI officielle, et en retard sur leur propre code (le bouton `.submit-button` n'existe plus).
- Sélecteurs : lire le gabarit actuel du front (`app/partials/includes/modules/login-form.jade`), pas un vieux test. Le bouton de connexion : `form.login-form button[type="submit"]`.
- Le test E2E échoue avec un `Timeout` dès le premier `fill` : la page n'est pas servie (IP non autorisée → 403, ou staging éteint).
- `e2e-test` n'a aucun projet : `/api/v1/projects` renvoie `[]`, la base travaille peu (piste : lui donner un projet avec des cartes).
- Avertissement `PytestRemovedIn10Warning` (fixture `base_url`) : vient du greffon pytest-playwright, sans effet avec les versions figées ; à revoir avant pytest 10.
- Ne pas viser la production sans prévenir l'équipe : un test de charge, c'est du vrai trafic.
