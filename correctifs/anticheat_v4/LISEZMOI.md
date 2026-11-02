# 🛡️ Anti-cheat V4 : fly, téléport, vitesse et privation d'UGC

Fait à partir de ta version **actual_version_1.0**.

---

## 1. Ce qui a changé (et pourquoi)

### A. Faux positifs trouvés en lisant TOUS les scripts du jeu

J'ai passé en revue les 724 scripts qui bougent un joueur, soit 224 scripts différents une fois les copies regroupées. Voici les cas qui pouvaient donner un warning à un joueur honnête, et ce qui a été corrigé.

| Où dans le jeu | Problème | Correction |
|---|---|---|
| **Tapis roulant « Hard obby part »** (WorkspaceScriptsManager, 50 studs/s) | Un joueur qui marche dessus va à environ 66 studs/s pendant plusieurs secondes. Le maximum autorisé était de 37 → **warning VITESSE**. | La vitesse de la pièce sous les pieds est ajoutée au maximum. Elle reste en mémoire 1,5 s après avoir quitté le tapis. Ça couvre aussi les plateformes mobiles. |
| **Météo Admin Abuse** (gravité jusqu'à 5, saut jusqu'à 500, vitesse jusqu'à 400) | Le script appelait `_G.AntiFlyTP.SetTestMode(true)` pour mettre l'anti-cheat en pause, mais cette fonction ne faisait plus rien. Avec une gravité très basse, un simple saut reste « immobile en l'air » plus de 2,5 s → **warning VOL**. | Nouvelle fonction `PausePhysics(true/false)` : pause pendant la météo, plus 6 s après, et 15 min au maximum. AdminAbuse_Server l'appelle (4 mots à changer). En plus, la limite de vol stationnaire grandit quand la gravité baisse. `SetTestMode` reste sans effet, pour que le vieux bouton « Toggled global test mode » ne mette jamais l'anti-cheat en pause. |
| **Téléportations faites par le serveur sans prévenir l'anti-cheat** (« Tp finish obby shop », « system ancer reculer level », portails…) | Le joueur est déplacé loin d'un coup. Le seul filet était la liste des « destinations sûres », qui ne couvre pas tout → **warning TÉLÉPORT**. | Détection automatique : quand un script **serveur** écrit la position, l'anti-cheat le voit et ne compte pas ce saut. Le joueur, lui, ne peut pas déclencher ce signal. Le vol et la vitesse restent mesurés juste après. |
| **Tyrolienne** | L'attribut `Ziplining` désactivait toute l'analyse. Un tricheur pouvait s'accrocher, ne jamais envoyer « Stop » et voler partout : **faille**. | L'exemption ne vaut plus que si le joueur est à moins de 18 studs d'une corde « Tirolienne ». |

Ce qui était déjà bien géré et reste couvert :
- les coils (Gravity, Speed, Fusion), le Jetpack (normal, Admin Abuse et Noob Quest) et la Scythe (dash de 0,2 s, trop court pour déclencher) ;
- les blocs de projection et les jump pads ;
- la gifle (ragdoll) et le ragdoll du PvP ;
- l'arène 1v1 et le mouvement PvP (slide, double saut, gravité) ;
- les checkpoints et le skip obby (SafeTeleport) ;
- la cachette (Hideout), le rebirth, le rechargement AFK, le fly admin (`AdminFly`) et les commandes admin (GO TO / BRING).

### B. Discrétion : le joueur ne sait rien

- Plus aucune **carte orange** (détection) ni **carte rouge** (warning).
- Plus de **retour en arrière** : il trahissait la détection.
- Plus de **kick d'avertissement** (en mode ban).
- Le bouton **Buy** n'est plus grisé pour un joueur restreint : il trahissait la sanction.

### C. Sanction après X warnings (1 par défaut)

Rappel de l'échelle : 3 détections retenues et rapprochées font 1 warning. Avec 1 warning, la privation peut donc tomber dès qu'un comportement anormal se répète.

Le dernier verrou reste en place : la sanction automatique ne tombe que si la **certitude du dossier** est d'au moins **85 %**. Si le dossier est trop faible, le warning est noté, la sanction attend, et le dossier reste visible dans le panel.

### D. Chaque warning disparaît tout seul (30 jours par défaut)

Chaque warning a sa propre date : il s'efface 30 jours après avoir été reçu.

Avant, tout s'effaçait d'un coup seulement si le dernier warning datait de plus de 7 jours. Un joueur qui prenait un faux warning par semaine les gardait donc à vie.

### E. Quand le joueur l'apprend

1. **Une fois**, au moment de la sanction : le panneau « UGC désactivées » s'affiche. S'il n'était pas en jeu à ce moment-là (sanction manuelle, déconnexion), il le voit à sa connexion suivante. Ensuite, il ne le revoit plus en se connectant.
2. **Ensuite, seulement quand il essaie d'acheter une UGC qu'il pourrait se payer.**
   - S'il n'a pas assez de points, il voit le message normal « Not enough points ». On ne lui propose **pas** d'acheter des points en Robux pour une UGC qu'il ne pourra pas avoir.
   - S'il a assez de points, il voit le panneau de sanction et l'achat est refusé. Aucun point n'est retiré.

### F. Panel admin

- Nouvel onglet **🚫 Restreints** (écran 🚨 ANTI-CHEAT) :
  - tous les joueurs privés d'UGC (jusqu'à 300) ;
  - une recherche par pseudo, UserId, admin ou mot de la raison (« vol », « téléport »…) ;
  - pour chaque joueur : la **raison exacte** (type, mesure, position, outil en main, certitude), les derniers signaux retenus, la date, qui a sanctionné, les achats bloqués et si le joueur a déjà vu le panneau ;
  - les boutons **🔍 Dossier** et **✅ Lever** (appuyer deux fois pour confirmer).
- Un joueur restreint **sort** des onglets 📡 Récent, 🎯 Risque et 🏆 Classements.
- La fiche 🔍 Dossier affiche aussi la raison exacte.
- Nouvelle carte **🤫 DISCRÉTION ET DURÉE DES WARNINGS** dans ⚙️ Réglages → Modes.

---

## 2. Installation (7 étapes)

> Les fichiers « COMPLET » sont faits à partir de ta version actual_version_1.0. Si tu as modifié l'un de ces scripts depuis, utilise plutôt les fichiers « REMPLACEMENTS ».

1. **ServerScriptService ▸ anti fly/tp server** : remplace tout par `AntiFlyTP_SERVEUR.lua`.
2. **ServerScriptService ▸ AntiCheat_UGCRestrict** : remplace tout par `AntiCheat_UGCRestrict_SERVEUR.lua`.
3. **StarterPlayerScripts ▸ UGCRestrictNotify** : remplace tout par `UGCRestrictNotify_CLIENT.lua`.
4. **ServerScriptService ▸ time** : remplace tout par `time_COMPLET.lua`, ou fais les 5 petits remplacements de `time_REMPLACEMENTS.md`.
5. **ServerScriptService ▸ Admin server** : remplace tout par `Admin_server_COMPLET.lua`, ou fais ces 2 remplacements :
   - `getACBoard.OnServerInvoke = function(player, boardId, n)` devient la fonction `acFilterRestricted` suivie de `local function getACBoardRaw(player, boardId, n)` ;
   - juste avant `getGameBoard.OnServerInvoke = function(player, boardId, n)`, ajoute le nouveau `getACBoard.OnServerInvoke` qui appelle `acFilterRestricted(getACBoardRaw(...))`.

   Le texte exact est dans `Admin_server_COMPLET.lua`, autour de la ligne 266.
6. **ServerScriptService ▸ AdminAbuse_Server**, fonction `setPhysicsGrace` : remplace les 4 `SetTestMode` par `PausePhysics`.
7. **ServerStorage ▸ AdminClientScripts ▸ Admin_client** : remplace tout par `Admin_client_COMPLET.lua`, ou fais les 12 remplacements de `Admin_client_REMPLACEMENTS.md`.

### Recommandé

- **Désactive ServerScriptService ▸ « Tp finish obby shop »** (coche *Disabled*). Aucun script du jeu n'envoie son remote `tpfinishobby`. Il ne sert donc qu'aux tricheurs, pour se téléporter gratuitement à la fin de l'obby. Le vrai « skip obby » passe par `skipobby_receip_dev_product`, qui reste intact.
- Après publication, fais **Shut down all servers** pour qu'aucun ancien serveur ne réécrive l'ancienne config.

### Ce qui se passe au premier démarrage

Ta config enregistrée est **migrée une seule fois** :
- discret : OUI ;
- 1 warning avant la sanction ;
- rappel à chaque connexion : NON ;
- panneau seulement à l'achat : OUI ;
- expiration des warnings : 30 j ;
- **anti-cheat ACTIVÉ** : shadow coupé, mode privation d'UGC.

Ensuite, c'est le panel qui décide. Si tu préfères observer d'abord, mets `ACTIVATE_ON_INSTALL = false` en haut de `AntiCheat_UGCRestrict_SERVEUR.lua` avant d'installer, ou recoche « Mode test (shadow) » dans le panel.

---

## 3. Configurer (panel → 🚫 UGC BAN → ⚙️ Réglages → Modes)

| Réglage | Défaut | Ce que ça fait |
|---|---|---|
| 🚫 Privation d'UGC / 🔨 Ban classique | Privation | Le type de sanction. La privation est réversible : le joueur garde ses points. |
| 🧪 Mode test (shadow) | coupé | Coché : rien n'est appliqué, tout est observé. |
| **Warnings avant la privation** | **1** | Le X que tu voulais. |
| Durée de la privation | définitif | 0 = jusqu'à ce que tu la lèves. |
| Afficher le panneau au moment de la privation | oui | L'affichage unique à la sanction. |
| Rappeler à chaque connexion | **non** | Laisse-le coupé pour respecter « seulement à l'achat ». |
| Kicker au moment de la privation | non | |
| Bloquer les dons / le rebirth | oui / non | |
| **🤫 Le joueur ne voit rien de ses warnings** | **oui** | Aucune carte, aucun retour en arrière, aucun kick d'avertissement. |
| **⏳ Un warning disparaît après** | **30 j** | Durée de vie de chaque warning (0 = jamais). |
| **🛒 Ne montrer la sanction qu'à l'achat** | **oui** | Panneau seulement s'il a assez de points pour l'UGC. |
| Compter / Avertir / Sanctionner à partir de | 55 / 70 / 85 % | Niveau de preuve exigé. Ne baisse pas « Sanctionner ». |
| Analyser les admins | oui | Toi aussi tu es mesuré : c'est ton meilleur test de faux positifs. |

Clique **ENREGISTRER** : c'est appliqué sur tous tes serveurs.

---

## 4. Gérer au quotidien (écran 🚨 ANTI-CHEAT)

- **📡 Récent** : qui a été détecté récemment (les restreints n'y sont plus).
- **🎯 Risque** : les suspects qui ont assez de points pour acheter des UGC.
- **🏆 Classements** : signaux et warnings (les restreints n'y sont plus).
- **🚫 Restreints** : tous les sanctionnés, avec recherche et raison exacte.
  - **✅ Lever** : rend l'accès aux UGC (appuie deux fois pour confirmer).
  - **🔍 Dossier** : l'historique détaillé et le bouton **🧹 Remettre ses compteurs à zéro**. Fais-le après avoir levé une sanction injuste, sinon ses anciens signaux pèsent encore.

Console serveur (F9, onglet Server) :
- `_G.AntiFlyTP.TestConfidence(userId)` : le détail de chaque signal d'un joueur ;
- `_G.UGCRestrict_List()` : la liste des restreints.
