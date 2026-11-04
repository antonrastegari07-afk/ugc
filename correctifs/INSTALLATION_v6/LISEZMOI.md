# 🧭 v6 : détecteur de bugs (« zones suspectes »)

## Le principe

L'anti-cheat retient **où** chaque détection a lieu, qu'elle soit retenue ou écartée. La map est découpée en cases de 24 studs, et le compte se fait sur tous les serveurs.

Quand **plusieurs joueurs différents** déclenchent l'anti-cheat **au même endroit**, c'est presque toujours un **bug de la map** (launcher, plateforme qui bouge, tapis, porte, tyrolienne…), pas des tricheurs.

## Dans le panel : 🛡️ ANTI-CHEAT ▸ 🧭 Zones

- **Chaque zone** :
  - sa position et un verdict :
    - 🐞 **BUG PROBABLE** : 3 joueurs différents ou plus ;
    - ⚠️ **À SURVEILLER** : 2 joueurs différents ;
    - 👤 **UN SEUL JOUEUR** : plutôt lui qu'un bug ;
  - une ligne de stats : joueurs, détections, certitude moyenne, dernière fois ;
  - les types de triche et les outils tenus en main.
- **Tris** : bugs probables d'abord, le plus de détections, les plus récentes. Filtre « seulement les bugs probables ».
- **🔎 Tout voir** ouvre par-dessus le panel :
  - les chiffres de la zone ;
  - la liste des joueurs touchés (🔍 ouvre leur fiche) ;
  - « 🛠️ Que faire ? ».
- **🚀 Y aller** : tu es téléporté sur la zone pour voir le problème. L'anti-cheat sait que c'est voulu.
- **🛡️ Ignorer** (avec confirmation) :
  - les détections **dans** la zone (rayon 24 studs) sont écartées : plus aucun warning ni sanction à cause du bug, sur tous les serveurs ;
  - elles restent visibles dans l'onglet, pour voir si le bug est réglé ;
  - « ✅ Ne plus ignorer » annule.

La vraie correction reste d'ajouter l'élément du jeu dans `ANTICHEAT_CONFIG` ▸ ⑩. Ignorer une zone, c'est le pansement en attendant.

## Installation (remplacer tout le contenu)

Ces fichiers contiennent aussi tout le v5 (détails, dossier réorganisé, correctif TooManyRequests).

| # | Où | Fichier |
|---|---|---|
| 1 | ServerScriptService ▸ **anti fly/tp server** | `AntiFlyTP_SERVEUR.lua` |
| 2 | ServerScriptService ▸ **AntiCheat_UGCRestrict** | `AntiCheat_UGCRestrict_SERVEUR.lua` |
| 3 | ServerStorage ▸ AdminClientScripts ▸ **Admin_client** | `Admin_client_COMPLET.lua` |
| 4 | Page du jeu | Publier, puis **Shut down all servers** |

Réglages en haut du bloc « 🧭 ZONES » dans Admin_client :
- `ZONE_BUG_PLAYERS = 3` : nombre de joueurs différents à partir duquel une zone est un bug probable ;
- `ZONE_RADIUS = 24` : rayon d'une zone ignorée, en studs.
