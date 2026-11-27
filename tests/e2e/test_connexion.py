# Test E2E : un utilisateur normal se connecte au staging et arrive sur son tableau de bord
import os

from playwright.sync_api import Page, expect

# Adresse du staging (modifiable par l'environnement) et compte de test non admin
URL = os.environ.get("E2E_URL", "https://staging.taiga-ledevagilles.fr")
UTILISATEUR = "e2e-test"
# Le mot de passe vient de Parameter Store, par une variable d'environnement : jamais écrit ici
MOT_DE_PASSE = os.environ["E2E_PASSWORD"]

# Le parcours : page de connexion → formulaire → accueil
def test_connexion(page: Page):
    page.goto(f"{URL}/login")
    page.locator('input[name="username"]').fill(UTILISATEUR)
    page.locator('input[name="password"]').fill(MOT_DE_PASSE)
    page.locator('form.login-form button[type="submit"]').click()    # Connecté : Taiga renvoie vers l'accueil (le tableau de bord)
    expect(page).to_have_url(f"{URL}/")