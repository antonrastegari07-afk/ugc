# 🔫 PvP : tir à travers les murs, contours rouges, cercle dans la vue du tueur

| # | Où | Fichier (remplacer tout) |
|---|---|---|
| 1 | ReplicatedStorage ▸ WeaponSystem ▸ **WeaponController** (ModuleScript) | `WeaponController_COMPLET.lua` |
| 2 | StarterPlayer ▸ StarterPlayerScripts ▸ **WeaponAnimationSharingClient** | `WeaponAnimationSharingClient_COMPLET.lua` |
| 3 | StarterPlayer ▸ StarterPlayerScripts ▸ **DeathCam** | `DeathCam_COMPLET.lua` |
| 4 | Page du jeu | Publier, puis **Shut down all servers** |

- **Murs (3e personne)** :
  - avant, le tir partait du bout du canon, qui ressort derrière le mur quand on rentre l'arme dedans ;
  - maintenant, un rayon part de ta poitrine jusqu'au canon : s'il touche un mur, la balle (ou la roquette du RPG) s'arrête sur ce mur ;
  - en 1re personne, rien ne change (l'arme se relève déjà contre le mur).
- **Contours rouges** :
  - Roblox n'affiche que 31 contours à la fois ;
  - il y avait 1 contour par corps, plus 2 par ennemi armé (un sur chaque bras) : la limite était vite dépassée, et des ennemis perdaient leur contour au hasard ;
  - maintenant, les corps passent en priorité, et les bras seulement pour les ennemis les plus proches, sous la limite.
- **Vue du tueur** : le rond autour du viseur du tueur n'est plus affiché. En jeu, il était déjà caché.
