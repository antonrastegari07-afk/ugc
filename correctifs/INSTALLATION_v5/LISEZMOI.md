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

**Même format partout** (📡 Fil, 🏠 Accueil, 👥 Joueurs, 🚫 Restreints, 🔍 Fiche) :

- **L'entrée reste petite.** On y voit :
  - l'en-tête du joueur ;
  - **une seule ligne de stats** : détections, warnings, certitude max, warnings actifs, UGC finançables ;
  - les boutons **🔎 Tout voir · 🔍 Fiche · 🚫 Restreindre / ✅ Lever · 🧹 Warnings à 0**.
- **« 🔎 Tout voir »** ouvre **par-dessus le panel**, sans quitter l'écran, tout le dossier du joueur :
  - 📊 en bref (warnings, certitude moyenne et max, types, dates, points) ;
  - 🚫 sa sanction, avec la raison complète ;
  - ⚠️ ses warnings actifs ;
  - 📰 **tous ses événements**, chacun en détail ;
  - 🎯 ce que la machine a vu sur ce serveur, signaux écartés compris.
- **Chaque événement a les 5 mêmes rubriques** (détection, warning, sanction, action d'un admin) :
  1. 🏷️ l'événement ;
  2. 📝 ce qu'il a fait ;
  3. 📍 où et avec quoi ;
  4. 🎯 la certitude, avec **chaque « + » et « − »**, le total, le lot de détections d'un warning et les seuils ;
  5. 🗂️ son dossier à ce moment-là.
- **🔍 Fiche** : une ligne par événement, avec son bouton « 🔎 Détails », plus « 🔎 Tout voir en détail ».
- La fenêtre se ferme avec ✕, « Fermer » ou en touchant à côté.
- **Erreurs « TooManyRequests »** :
  - le serveur garde toujours une réserve de lectures DataStore pour le jeu (chargement et sauvegarde des joueurs) ;
  - le panel lit les fiches plus doucement et redemande plus tard ce qui n'est pas passé ;
  - il arrête de lire quand tu fermes le panel.

Les événements enregistrés **avant** cette mise à jour n'ont que les 5 principaux « + / − », et pas de position pour les warnings. C'est indiqué dans la fenêtre.
