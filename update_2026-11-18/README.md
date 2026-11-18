# Mise à jour du 18/11/2026 (v4) — installation + ce qui change

## ⚡ INSTALLATION RAPIDE (environ 2 minutes)

> Marche **par-dessus la v2 ou la v3** que tu as déjà installée, et aussi sur un jeu jamais mis à jour.

1. **Fais une copie de ton jeu** : *Fichier ▸ Enregistrer sous*.
2. Dans le Workspace, **supprime tout ancien dossier** `UPDATE_2026_11_18…` (v1, v2 ou v3).
3. Clic droit sur **Workspace** ▸ **Insert from File…**, puis choisis
   `INSTALLATION_RAPIDE/UPDATE_2026_11_18_v4.rbxmx`.
4. Dans la barre de commande (*Affichage ▸ Barre de commande*), colle cette ligne et appuie sur Entrée :
   ```lua
   require(workspace.UPDATE_2026_11_18_v4.INSTALL)()
   ```
5. Dans l'Output :
   - la 1re ligne doit être **« 🚀 Installateur v4… »** ;
   - puis **« ✅ INSTALLATION TERMINÉE : … scripts remplacés, … créés »**.

**Ce que fait l'installateur :**
- Chaque script est **échangé entier** : même nom, même place, même état activé/désactivé, mêmes attributs, et ses objets enfants suivent.
  (Il ne copie pas le code, car Studio refuse d'écrire plus de 200 000 caractères dans un script par programme.)
- Les versions remplacées vont dans **`ServerStorage ▸ BACKUP_avant_maj_v4`** (donc tes versions v2/v3).
  Les copies de secours précédentes ne sont pas touchées. Celle de la v2 (`BACKUP_avant_maj_2026_11_18`) contient les scripts d'**origine**.
- Il crée les nouveaux scripts et retire `daily notification` (déplacé dans la copie de secours, pas détruit).
- **Ctrl+Z annule toute l'installation d'un coup.** Rien n'est publié.

<details><summary>🖐️ Installation manuelle (si tu préfères)</summary>

Extension des fichiers : `.server.lua` = Script · `.client.lua` = LocalScript · `.module.lua` = ModuleScript.
Remplacer = ouvrir le script, Ctrl+A, coller. Ne change ni le nom ni la place.

**Créer :**
- ReplicatedStorage : `PopupControlConfig`, `PopupGate`, `LeaderboardStyle` (ModuleScripts)
- ServerScriptService : `PopupControl_Server`, `FriendsBoard_Server`, `Presence_Server` (Scripts)
- StarterPlayerScripts : `ArenaViewKeeper` (LocalScript)

**Remplacer :**
- **ServerScriptService :** `checkpoints system` · `anti fly/tp server` · `PLAYER UGC STATS` · `new donation board server` · `notif chat ` · `DAILY TOOLs` · `10 died = offer 2500 points` · `time` · `STATS` · `ask favorite game` · `datastore alr ask favorite game` · `leave popup` · `server referal friend invite`
- **ServerStorage ▸ AdminClientScripts. :** `Admin client`
- **ReplicatedStorage :** `LeaderboardCore` · `WeaponSystem ▸ WeaponController`
- **StarterGui :** `ShiftLockButton ▸ ImageButton ▸ ShiftGUI` · `VIP offer ▸ make pop th add` · `UGCshop ▸ ShopFrame ▸  UGC SHOP GENERATOR`
- **StarterPlayerScripts :** `PlayerProfileHover` · `offers on screen` · `script proposer achat skip obby` · `EngageTrack` · `rebirth offer notify event` · `fenetre dachat gravity coil` · `Fenetre dachat fusion coil` · `Fenetre achat speedcoil` · `achat x2coin` · ` ADMIN ABUSE — DÉGRADÉ SUR LE BOOST DU BILLBOARD`
- **StarterCharacterScripts :** `ask favorite game`

**Supprimer :** StarterPlayerScripts ▸ `daily notification`
</details>

---

## 🆕 NOUVEAU DANS LA v4 (tes derniers retours)

| Ton retour | Ce qui est fait |
|---|---|
| Pas de bouton FIND ME (loupe) | **Corrigé.** Le bouton avait une largeur de 0, donc il était invisible. La loupe 🔍 est maintenant à droite de l'en-tête. |
| Filtres contraires sélectionnables ensemble | **Corrigé.** Un seul choix parmi **Available / Low stock / Sold out**, un seul parmi **Owned / Not owned**, un seul tri. Re-cliquer un choix déjà pris le retire. TYPE reste multiple (Hat **ou** Hair : ce n'est pas contraire). |
| Une liste qui se déroule au lieu d'une fenêtre | Un clic sur FILTER **déroule une liste** sous le bouton (animation) ; un 2e clic la **rembobine**. La liste défile, avec **CANCEL / RESET / APPLY tout en bas**. **Aucun contour.** |
| Bouton FILTER sans épaisseur ni enfoncement | Bouton **plat**, comme les autres boutons de la fenêtre : coins arrondis, texte blanc avec contour sombre. Il passe au jaune quand un filtre est actif. |
| Vue PvP sans arme pas vraiment la même, avec un relais visible | **Refait.** Sans arme, le script reprend **exactement les mêmes calculs que la caméra des armes** : distance, épaule, hauteur, limites, recul devant les murs, roulis du slide, rotation du perso. Il reprend aussi les mêmes réglages de rotation : souris, glisser au doigt, stick, « sensibilité arme en main ». Il prend la caméra **dès l'image suivante**, là où l'arme l'a laissée, donc plus aucun relais. La seule différence : **pas de viseur**. |
| En ligne / hors ligne dans les profils | La fiche profil (visible par tout le monde) affiche **« @pseudo · 🟢 Online »** ou **« ⚫ Offline »**, même si le joueur est sur un **autre serveur**. Nouveau script `Presence_Server` : chaque serveur note ses joueurs en ligne dans une MemoryStore, avec une écriture par joueur et par minute et une expiration automatique (pas de DataStore). |

## NOUVEAU DANS LA v3

| Ton retour | Ce qui est fait |
|---|---|
| Erreur rouge en boucle en PvP (`ArenaViewKeeper:99`) | **Corrigé.** Une fonction était utilisée avant d'être créée. J'ai ajouté un contrôle automatique qui détecte ce type d'erreur et l'ai passé sur **tous** les scripts : plus aucun cas. |
| Sans arme : sprint, slide, cacher le panneau | Le panneau sans arme montre **Shift Sprint · C Slide · B Views · H Hide Controls**. Sprint et slide marchent déjà sans arme en main (il faut une arme dans le sac à dos, ce qui est le cas en arène). **H est maintenant retenu partout** : cacher les contrôles reste valable avec n'importe quelle arme et sans arme. |
| Badges de la fiche admin qui décalent tout | Les badges sont en **petit dans le coin en haut à droite** de la carte. La carte **ne change plus de taille**, rien d'autre ne bouge. |
| Réorganisation de l'admin | L'accueil a des **onglets** : 👥 Joueurs · 🎽 UGC & boutique · 🛡️ Sécurité · 🎉 Jeu & events · 📊 Chiffres · 📋 Tout. Il a aussi une **barre de recherche**. **Aucun bouton retiré** : les 30 sont là, avec les mêmes fonctions, et « 📋 Tout » montre l'ancienne grille complète. |
| Bouton FILTER (*remplacé en v4 par la liste déroulante*) | **Aligné** sur le bord droit de la carte la plus à droite (recalculé si l'écran change). Il est fait comme les **boutons 3D des Paramètres**, avec une taille de texte normale. Le panneau est **beaucoup plus simple** : SHOW (6 choix), TYPE (seulement si ton shop a plusieurs types), SORT BY (5 choix), puis CANCEL / RESET / APPLY. Tout est en anglais. Filtre actif : le bouton devient **jaune « FILTER (2) »**, et des pastilles apparaissent au-dessus de la grille (X = retirer, RESET ALL = tout effacer). |
| Leaderboards | **Apparence d'avant** remise : en-tête, entrées, « Refresh in » ; les ajouts du bas sont retirés. Dans l'en-tête d'avant : **ALL / FRIENDS** à gauche et une **petite loupe 🔍** discrète à droite (FIND ME). **FRIENDS montre TOUS tes amis** : ceux du top avec leur place, les autres en dessous avec **« -- »** et leur score. |
| Arc-en-ciel sur le boost | Le dégradé arc-en-ciel du boost (billboard) s'affiche maintenant pour **tout boost de points temporaire** : Admin Abuse, boosts achetés, gagnés à la roue, offerts… Il disparaît tout seul quand le boost expire. |

**Revenir à avant (pour chaque nouveauté) :**
- **Leaderboards :**
  - `ReplicatedStorage ▸ LeaderboardStyle` : `Tabs = false` → boards exactement d'origine ;
  - `Style = "modern"` → le look moderne de la v2.
- **Vue PvP sans arme :** `ArenaViewKeeper`, mets `ENABLED = false` (ligne 23).
- **Arc-en-ciel :** dans ` ADMIN ABUSE — DÉGRADÉ…`, mets `ANY_TEMP_BOOST = false` → seulement pendant l'Admin Abuse, comme avant.

---

## 📋 TOUT CE QUI CHANGE (rappel complet)

1. **Reload AFK :** le joueur revient exactement à sa place, même sans checkpoint. S'il était en l'air, sur une plateforme mobile ou dans la cachette, il revient sur son checkpoint. La fiche anticheat signale « arrivé par reload AFK » si un signal suit.
2. **Fiche joueur admin :** badges 🛡️ ADMIN · 👑 VIP · ⚡x2/x5/x10, et « il y a 3 j 5 h » au lieu d'une date.
3. **Dons :** effet + son du board sur tous les serveurs, et classement à jour partout tout de suite.
4. **Curseur PvP mobile :** 40 px minimum (avant 26 px).
5. **Ton lock mobile :** reste activé après la mort.
6. **Chat :** « Pseudo bought 100,000 Points! », sans prix en Robux.
7. **Popups :**
   - notif quotidienne retirée ;
   - favori intelligent ;
   - section **Admin ▸ 🔔 POPUPS** : ON/OFF, fréquences, mode « seulement si inactif », pause entre 2 popups ;
   - stats des popups refaites, avec 6 erreurs corrigées ;
   - une faille DataStore bloquée ;
   - les morts de la 1re vie sont maintenant comptées.
8. **Leaderboards :** look d'avant + ALL / FRIENDS / 🔍 (voir plus haut).
9. **Shop UGC :** bouton FILTER plat + liste déroulante, choix contraires exclusifs (voir plus haut).
10. **Parrainage :** paie seulement si l'invité découvre le jeu. Ça ferme la faille des amis qui s'invitent entre eux et celle des joueurs qui jouaient déjà.
11. **Arène sans arme :** même vue qu'avec une arme, B change la vue, panneau des contrôles (voir plus haut).
12. **Admin :** accueil en onglets + recherche (voir plus haut).
13. **Arc-en-ciel du boost :** pour tout boost temporaire.
14. **Profils :** 🟢 Online / ⚫ Offline, même sur un autre serveur.

---

## ✅ Vérifié de mon côté (sans pouvoir lancer le jeu)
- Les 38 fichiers (37 scripts + l'installateur) passent l'analyseur de syntaxe Luau. Ce même analyseur valide les 669 scripts d'origine sans erreur.
- **Nouveau contrôle :** « utilisé avant d'être créé » (l'erreur de `ArenaViewKeeper`) sur tous les scripts → **0**. J'ai vérifié qu'il détecte bien l'erreur d'origine.
- Aucune fonction ni variable de niveau principal perdue (comparaison avec les originaux).
- `time` reste à 199 variables locales (limite 200). Le panel admin n'a aucune variable locale en plus (162).
- Le modèle `.rbxmx` contient exactement le même code que les fichiers (vérifié octet par octet).

## 🧪 À tester dans Studio avant de publier
1. **Arène :**
   - range et ressors ton arme plusieurs fois : la vue doit rester **identique**, sans saut ni relais ;
   - sans arme : pas de viseur, panneau Shift / C / B / H, B change la vue, H cache le panneau ;
   - teste aussi au doigt (émulateur mobile) et à la manette si tu peux ;
   - aucune erreur rouge dans l'Output.
2. **Shop UGC :**
   - FILTER se déroule et se rembobine ;
   - la liste défile jusqu'aux boutons du bas ;
   - les choix contraires s'excluent ;
   - APPLY, pastilles, RESET fonctionnent ;
   - teste aussi en mobile (émulateur).
3. **Leaderboards :**
   - ALL / FRIENDS / 🔍 ;
   - en FRIENDS : un ami hors top affiche « -- ». Son score met environ une seconde à apparaître ; il est lu sur le serveur, donc à vérifier sur un **vrai serveur publié**.
4. **Admin :** les onglets et la recherche, puis la fiche d'un joueur (badges dans le coin, rien qui déborde).
5. **Boost :** achète ou donne-toi un boost temporaire → arc-en-ciel sur ton billboard.
6. **Profils :** clique sur un joueur du serveur (🟢 Online), puis ouvre depuis un leaderboard la fiche de quelqu'un qui n'est pas là (🟢 Online sur un autre serveur, ou ⚫ Offline). Le statut d'un autre serveur ne marche que sur un **vrai serveur publié** : MemoryStore n'est pas partagé entre serveurs en Studio.
