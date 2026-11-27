# Runbook – <Verbe + objet, ex. « Restaurer la base de production »>

<!-- Modèle : copier ce fichier dans docs/runbooks/<numéro-thème>/<verbe_objet>.md, remplir, supprimer les commentaires, puis ajouter une ligne dans docs/README.md. -->

**Pourquoi** : <dans quelle situation on ouvre ce runbook, en une phrase>. Fonctionnement : `<README du dossier ou du rôle concerné>`.

**Où** : dans sa VM, à la racine de `taiga-infrastructure`, `staging` à jour <+ ce qui doit être chargé : agent SSH, config SSH…>. **Prévenir l'équipe** <si l'opération touche un environnement partagé>.

## Ce qui doit être allumé
<!-- Supprimer la section si rien n'est nécessaire. -->
| Pour… | Il faut |
|---|---|
| <étape> | <machines, NAT, RDS…> |

## 1. <Première étape>
```bash
<commande, une par bloc si elles se lancent une à une>
```
Attendu : <ce qu'on doit voir ; c'est la preuve que l'étape a marché>.

## 2. <Étape suivante>
```bash
<commande>
```
Attendu : <…>.

## Vérifier
```bash
<commande qui prouve que tout est en ordre>
```
Attendu : <…>.

## Dépannage
| Symptôme | Cause probable | Que faire |
|---|---|---|
| <message d'erreur exact> | <pourquoi> | <commande ou renvoi> |
