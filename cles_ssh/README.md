# Clés SSH de l'équipe

Un fichier `.pub` par personne : la clé **publique**, sur une seule ligne. Terraform (`commun/`, `staging/`, `production/`) lit tous les `.pub` de ce dossier et les pose sur chaque instance au premier démarrage (cloud-init, utilisateur `ubuntu`).

## Ajouter une personne
1. Sur son poste : `ssh-keygen -t ed25519 -C "<prenom>-taiga" -f ~/.ssh/taiga_bastion` (avec une phrase de passe).
2. Copier **seulement** `~/.ssh/taiga_bastion.pub` ici, sous le nom `<prenom>.pub`.
3. Vérifier : `ssh-keygen -lf cles_ssh/<prenom>.pub` → une empreinte `SHA256:…`.
4. MR, fusion. La clé arrive sur les instances **créées après** ; pour une instance existante : la recréer, ou l'ajouter avec Ansible.

## Retirer une personne
Supprimer son fichier, puis recréer les instances (ou retirer la clé avec Ansible).

## Pièges
- Jamais de clé privée ici (elle commence par `-----BEGIN OPENSSH PRIVATE KEY-----`). Si ça arrive : la clé n'est plus secrète, il faut la remplacer.
- Un chemin faux ne donne pas d'erreur, seulement une liste vide : vérifier avec `echo 'local.cles_equipe' | terraform console` dans un dossier Terraform.
