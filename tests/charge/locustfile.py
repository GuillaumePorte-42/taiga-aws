# Test de charge : des utilisateurs virtuels se connectent à l'API du staging, puis lisent leur profil et leurs projets
import os

from locust import HttpUser, between, task

# Compte de test non admin ; le mot de passe vient de Parameter Store, par l'environnement
UTILISATEUR = "e2e-test"
MOT_DE_PASSE = os.environ["E2E_PASSWORD"]

# Un utilisateur virtuel de Taiga, qui fait une pause de 1 à 3 secondes entre deux actions, comme un humain
class UtilisateurTaiga(HttpUser):
    wait_time = between(1, 3)

    # À son arrivée : connexion à l'API, puis le jeton reçu est joint à toutes ses requêtes suivantes
    def on_start(self):
        reponse = self.client.post("/api/v1/auth", json={"type": "normal", "username": UTILISATEUR, "password": MOT_DE_PASSE})
        jeton = reponse.json()["auth_token"]
        self.client.headers["Authorization"] = f"Bearer {jeton}"

    # Lire son profil
    @task
    def profil(self):
        self.client.get("/api/v1/users/me")

    # Lire ses projets, 3 fois plus souvent que le profil
    @task(3)
    def projets(self):
        self.client.get("/api/v1/projects")