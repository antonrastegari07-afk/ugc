# 🔎 v5 : détails complets de chaque détection et warning, et moins de lectures DataStore

À installer sur ta version actuelle. Remplace tout le contenu de chacun des 3 scripts :

| # | Où | Fichier |
|---|---|---|
| 1 | ServerScriptService ▸ **anti fly/tp server** | `AntiFlyTP_SERVEUR.lua` |
| 2 | ServerScriptService ▸ **AntiCheat_UGCRestrict** | `AntiCheat_UGCRestrict_SERVEUR.lua` |
| 3 | ServerStorage ▸ AdminClientScripts ▸ **Admin_client** | `Admin_client_COMPLET.lua` |
| 4 | Page du jeu | Publier, puis **Shut down all servers** |

Le correctif v4.1 (tp1v1, SessionToolCarry, GamepassTools) reste à installer s'il ne l'est pas déjà.

## Ce qui change

- **Bouton « 🔎 Détails »**
  - Où : sur chaque entrée (Fil, Accueil) et sur chaque ligne de l'historique d'un joueur.
  - Il ouvre une fenêtre **par-dessus le panel**, sans quitter l'écran. On la ferme avec ✕, « Fermer » ou en touchant à côté.
  - Pour chaque événement (détection, warning, sanction, action d'un admin), on voit toujours les **5 mêmes rubriques** :
    1. 🏷️ l'événement : date, serveur, mode réel ou sans sanction, qui l'a fait ;
    2. 📝 ce qu'il a fait : le type, une explication en clair, la mesure ;
    3. 📍 où et avec quoi : position, outil, vitesse, vitesse de marche, arène, contexte ;
    4. 🎯 la certitude :
       - **chaque « + » et chaque « − »** et le total ;
       - pour un warning, les certitudes du lot de détections et leur moyenne ;
       - les seuils ;
    5. 🗂️ son dossier à ce moment-là : warnings, strikes, résultat.
- **🔍 Fiche** : tout l'historique est affiché **en détail**, événement par événement. Il y en a 10, puis « Voir plus » ; « 🔎 En grand » ouvre un événement par-dessus. « Ce que la machine a vu » montre maintenant tous les « + / − », plus seulement 6.
- **Erreurs « TooManyRequests »** :
  - le serveur garde toujours une réserve de lectures DataStore pour le jeu (chargement et sauvegarde des joueurs) ;
  - le panel lit les fiches plus doucement et redemande plus tard ce qui n'est pas passé ;
  - il arrête de lire quand tu fermes le panel.

Les événements enregistrés **avant** cette mise à jour n'ont que les 5 principaux « + / − », et pas de position pour les warnings. C'est indiqué dans la fenêtre.
