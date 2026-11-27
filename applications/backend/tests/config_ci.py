# Réglages des tests pour la CI GitLab : reprend tests/config.py, ne change que l'hôte de la base
import os

from tests.config import *  # noqa

# Dans GitLab, PostgreSQL est un service joignable par son nom, pas par localhost
DATABASES["default"]["HOST"] = os.getenv("POSTGRES_HOST", "localhost")