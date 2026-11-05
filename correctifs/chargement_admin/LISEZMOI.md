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

---

# ⏱️ Écran de chargement : SKIP plus rapide + diagnostic

## Ce qui a été vérifié

- Entre ta **4.0** et ta **5.0** : mêmes objets (52 895), même écran de chargement. Seuls 6 scripts serveur et le panel admin ont changé, et aucun ne fait de travail en plus quand un joueur arrive.
- Le bouton SKIP attend 4 choses :
  - le jeu chargé ;
  - ton personnage ;
  - tes **données** (signal `DataLoaded` du script `time`, qui lit le DataStore), avec 8 s d'attente au maximum ;
  - les images.
- Si le DataStore est lent (beaucoup de requêtes, nouvel essai, verrou de session), le bouton attendait jusqu'à **8 s**.

## Le correctif

- Attente maximale des données et des images : **8 s → 4 s**. Au-delà, le bouton apparaît quand même (le jeu et le personnage restent obligatoires, comme avant).
- **Diagnostic dans la console (F9)** : à chaque connexion, tu vois ce qui a pris du temps, par exemple :
  ```
  [Loader] ⏱️ jeu chargé (game:IsLoaded) : 1.8 s
  [Loader] ⏱️ personnage apparu : 2.1 s
  [Loader] ⏱️ images préchargées : 2.4 s
  [Loader] ⏱️ données reçues (DataLoaded) : 6.9 s
  [Loader] ✅ bouton SKIP affiché à 4.0 s  (données pas encore reçues : on n'attend plus)
  ```
- Mets `LOADER_DEBUG = false` dans le script pour couper ces messages.

## Installation

| Où | Fichier |
|---|---|
| ReplicatedFirst ▸ **Loading screen** | `LoadingScreen_ReplicatedFirst_COMPLET.lua` (remplacer tout) |
