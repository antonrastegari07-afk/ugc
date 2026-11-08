# Installation v7 (sur la base de ta version 7.0)

Chaque fichier REMPLACE TOUT le contenu du script indiqué (Ctrl+A dans le script, puis coller).
Clique bien DANS le code avant de coller (sinon Studio dit « Clipboard text isn't JSON »).

| # | Où | Script | Type |
|---|----|--------|------|
| 1 | ServerScriptService | **PLAYER UGC STATS** (à CRÉER) | Script |
| 2 | ServerScriptService | ugc redeems admin log | Script |
| 3 | ServerStorage › AdminClientScripts | Admin client | LocalScript |
| 4 | ServerScriptService | flame arrow obby | Script |
| 5 | StarterPlayer › StarterPlayerScripts | flame arrow obby | LocalScript |
| 6 | ReplicatedStorage › WeaponSystem | WeaponMechanics | ModuleScript |
| 7 | ReplicatedStorage › WeaponSystem | WeaponSharedState | ModuleScript |

Ensuite : Publish, puis « Shut down all servers ».

Ce que ça change :
- 1, 2, 3 : onglet 📊 STATS ▸ 🎽 Joueurs & UGC (sans UGC, 1/2/3…, VIP / boosts, VIP + x2,
  temps pour avoir une UGC, UGC avant d'arrêter de jouer), 💸 Achats & pubs refait plus visuel,
  dernière connexion (🟢 / 🕒) sur les entrées des joueurs et dans Manage Player.
- 4, 5 : flèches de feu du niveau 93 (arrowzone1) plus lentes (70 → 42). Attribut « ArrowSpeed »
  sur la Part de la zone pour régler en direct.
- 6 : manette : L3 = sprint activé pour de bon, 2e appui = arrêt (GamepadToggle = false pour l'ancien maintien).
- 7 : console (Xbox / PlayStation) : 3e personne avec lock par défaut.
