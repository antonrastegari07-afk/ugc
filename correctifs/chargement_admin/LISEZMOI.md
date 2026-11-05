# ⏳ Le bouton SKIP du chargement arrive tard (admins)

## La cause

- `ADMIN_TOOLS_GIVER` envoie le panel admin (`Admin client`) à un admin **dès qu'il arrive** sur le serveur.
- Ce LocalScript pèse environ **1 Mo** (25 000 lignes) : 915 Ko en v2, 1 015 Ko en v5.
- Ton jeu doit le télécharger et le démarrer **pendant** l'écran de chargement. Le reste du chargement (map, données, personnage) passe après, donc le bouton SKIP arrive plus tard.
- Les joueurs normaux ne reçoivent pas ce script : ils ne devraient pas être touchés. Vérifie avec un compte non admin.
- L'écran de chargement lui-même n'a pas changé entre ta 4.0 et ta 5.0.

## Le correctif

Le panel admin est envoyé **après** le chargement :
- il attend que tes données soient chargées et que ton personnage soit apparu (25 s au maximum) ;
- puis encore 4 s, le temps que l'écran de chargement se ferme ;
- le panel arrive donc quelques secondes après ton entrée en jeu.

Rien d'autre ne change.

Réglages en haut du script : `ADMIN_WAIT_MAX = 25` et `ADMIN_EXTRA_DELAY = 4`.

## Installation

| Où | Fichier |
|---|---|
| ServerScriptService ▸ **ADMIN_TOOLS_GIVER** | `ADMIN_TOOLS_GIVER_COMPLET.lua` (remplacer tout) |

Ensuite, publie puis fais **Shut down all servers**.
