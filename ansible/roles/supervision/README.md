# Rôle `supervision`

La supervision du projet, en conteneurs (Docker Compose) sur l'instance `taiga-monitoring`, dans `/opt/supervision`. Lancé par `playbooks/supervision.yml` (après le rôle `docker`).

## Les conteneurs
| Conteneur | Rôle | Écoute |
|---|---|---|
| **Prometheus** | collecte toutes les 30 s, garde 7 jours, évalue les règles d'alerte | `127.0.0.1:9090` |
| **Grafana** | tableaux de bord ; page d'accueil « Taiga · vue d'ensemble » ; inscriptions fermées | `127.0.0.1:3000` |
| **Alertmanager** | regroupe les alertes et les envoie sur le canal Discord de l'équipe (webhook) | `127.0.0.1:9093` |
| **postgres_exporter** | statistiques de la base RDS, avec l'utilisateur `monitoring` (lecture seule) | réseau du Compose seulement |
| **blackbox_exporter** | **sonde le site de l'extérieur**, comme un visiteur (HTTPS, réponse 2xx attendue) | réseau du Compose seulement |

Rien n'est exposé sur le réseau : on y accède par **tunnel SSH** (`docs/runbooks/4-verifier/ouvrir_grafana.md`).

## Ce que Prometheus collecte (`templates/prometheus.yml.j2`)
| Job | Cibles |
|---|---|
| `machines` | node_exporter (9100) de **toutes** les machines de l'inventaire |
| `cadvisor` | conteneurs (8080) des nœuds de production et du staging |
| `base` | postgres_exporter (RDS de production) |
| `site` | blackbox → `https://<domaine>/` (l'interface), prod et staging |
| `api` | blackbox → `https://<domaine>/api/v1/` (l'API : passerelle, back, base), prod et staging |

## Les alertes (`files/alertes.yml`)
| Alerte | Quand |
|---|---|
| `InstanceArretee` | node_exporter ne répond plus depuis 1 min (sonne aussi le soir, à l'arrêt des machines : normal) |
| `DisquePresquePlein` | moins de 15 % libre sur `/` |
| `ConteneurQuiRedemarre` | au moins 3 redémarrages en 15 min |
| `BaseIndisponible` | postgres_exporter ne joint plus RDS |
| `SiteWebInjoignable` | `probe_success{job="site"} == 0` depuis 1 min |
| `ApiInjoignable` | `probe_success{job="api"} == 0` depuis 1 min (l'incident du 04/11 : interface OK, API en `502`) |
| `ServiceTaigaIncomplet` | un service de la stack de production a moins de copies que prévu (3 pour gateway, front, back, protected ; au moins 1 pour les autres) depuis 5 min |
| `CadvisorAveugle` | cAdvisor répond mais ne voit aucun conteneur depuis 5 min (bug du démarrage : `ansible/roles/cadvisor/README.md`) |
| `SauvegardeTropVieille` | aucune sauvegarde réussie depuis plus de 26 h (métrique écrite par le script de sauvegarde) |

📘 `probe_success` est le **résultat de la sonde** (1 = réponse 2xx). `up` dirait seulement que blackbox lui-même répond : il ne convient pas pour savoir si le site répond.

## Variables (`defaults/main.yml`)
| Variable | Défaut | Rôle |
|---|---|---|
| `supervision_prometheus_image`, `supervision_grafana_image` | `prom/prometheus:v3.1.0`, `grafana/grafana:11.4.0` | versions fixées |
| `supervision_alertmanager_image`, `supervision_blackbox_image`, `supervision_postgres_exporter_image` | `v0.27.0`, `v0.25.0`, `v0.15.0` | versions fixées (« à vérifier » dans le fichier) |
| `supervision_prometheus_retention` | `7d` | durée de conservation |
| `supervision_grafana_admin_password_ssm` | `/taiga/admin/grafana_admin_password` | mot de passe de `admin` |
| `supervision_alerte_webhook_ssm` | `/taiga/admin/alert_webhook_url` | adresse du webhook Discord (**doit exister**, sinon le playbook échoue) |
| `supervision_db_monitoring_password_ssm` | `/taiga/production/postgres_monitoring_password` | utilisateur `monitoring` de RDS |

## L'utiliser
```bash
ansible-playbook -i inventories/tous/aws_ec2.yml playbooks/supervision.yml
```
**Toujours avec l'inventaire `tous`, toutes les machines allumées** : la liste des cibles est construite à partir de l'inventaire. À relancer après la création ou la recréation d'une machine. La RDS doit être `available` (création de l'utilisateur `monitoring`).

## Pièges
- `docker-compose.yml` (mot de passe de Grafana) et `alertmanager.yml` (webhook) : `0600`, `no_log`, ne jamais les copier ailleurs.
- Une machine arrêtée au moment du playbook n'est pas dans la configuration de Prometheus.
- La sonde du **staging** sort par la NAT : elle passe grâce à la règle 11 de l'ALB (IP de la NAT). Le soir, NAT détruite : sondes en échec, normal.
- **Sondes en code `0` le matin, alors que le site répond depuis la VM** (06/11) : la supervision ne résolvait plus nos noms (`Could not resolve host`), alors que `amazon.com` passait. Réparé seul en quelques minutes. Hypothèse (non prouvée) : réponse « ce nom n'existe pas » gardée en cache, la supervision ayant interrogé avant que `commun/` recrée les enregistrements DNS. Contrôle : `dig taiga-ledevagilles.fr @169.254.169.253` depuis la supervision (`docs/runbooks/2-chaque-jour/arreter_demarrer.md`).
- blackbox n'est joignable que sur le réseau du Compose (aucun port publié) : pour lancer une sonde à la main, passer par le conteneur de Prometheus : `sudo docker exec supervision-prometheus-1 wget -qO- 'http://blackbox-exporter:9115/probe?target=https://taiga-ledevagilles.fr/&module=http_2xx&debug=true'`.
- Tunnel refusé (`administratively prohibited`) : `common_ssh_tcp_forwarding: "local"` dans `playbooks/group_vars/role_monitoring.yml` (en place).
