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
| 8 | ServerScriptService | AntiCheat_UGCRestrict | Script |
| 9 | StarterPlayer › StarterPlayerScripts | SettingsUI | LocalScript |
| 10 | ServerScriptService | checkpoints system | Script |
| 11 | ServerScriptService | system ancer reculer level | Script |
| 12 | StarterPlayer › StarterPlayerScripts | system navigation +1 level -1 level | LocalScript |
| 13 | ReplicatedStorage › WeaponSystem | WeaponController | ModuleScript |
| 14 | StarterPlayer › StarterPlayerScripts | WeaponDeathCleanup | LocalScript |
| 15 | ServerScriptService | time | Script |

Ensuite : Publish, puis « Shut down all servers ».

Ce que ça change :
- 1, 2, 3 : onglet 📊 STATS ▸ 🎽 Joueurs & UGC (sans UGC, 1/2/3…, VIP / boosts, VIP + x2,
  temps pour avoir une UGC, UGC avant d'arrêter de jouer), 💸 Achats & pubs refait plus visuel,
  dernière connexion (🟢 / 🕒) sur les entrées des joueurs et dans Manage Player.
- 4, 5 : flèches de feu du niveau 93 (arrowzone1) plus lentes (70 → 42). Attribut « ArrowSpeed »
  sur la Part de la zone pour régler en direct.
- 6 : manette : L3 = sprint activé pour de bon, 2e appui = arrêt (GamepadToggle = false pour l'ancien maintien).
- 7 : console (Xbox / PlayStation) : 3e personne avec lock par défaut.
- 8 : anti-cheat : « 🟢 Activer les sanctions » (et toute case qu'on COUPE dans les réglages) ne faisait rien — corrigé.
- 9 (+ 4, 5) : flèches de feu invisibles en mode performance (« particules » coupées) — les effets de gameplay marqués KeepFX ne sont plus jamais coupés.
- 10, 11, 12 : flèche -1 qui refusait de descendre après un join sur un checkpoint > 1 (Stage restait à 1) — corrigé. ET faille fermée : le serveur acceptait n'importe quel numéro de niveau (sauter tout l'obby) ; il part maintenant du checkpoint actuel et refuse tout ce qui dépasse le plus haut checkpoint atteint.
- 9 (mise à jour) : Auto Performance marche dans les deux sens (baisse si FPS < 22, remonte quand les FPS sont bons 60 s, sans va-et-vient).
- 13, 14 : mode lock PvP — plus de vue bloquée avec curseur libre après la mort, perso qui ne tourne plus contre un mur, caméra sans allocation par image, « Mode » → « Views ».
- 7, 13, 15 : la vue PvP (B / VIEW) est mémorisée par appareil ; curseur = ton image partout (1re personne, lock, mobile, manette), rouge sur un ennemi ; ancien viseur en lignes retiré.
