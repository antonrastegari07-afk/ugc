# Mise à jour du 18/11/2026 (v6) — installation + ce qui change

## ⚡ INSTALLATION RAPIDE (environ 2 minutes)

> Marche **par-dessus la v2 à v5** que tu as déjà installée, et aussi sur un jeu jamais mis à jour.

1. **Fais une copie de ton jeu** : *Fichier ▸ Enregistrer sous*.
2. Dans le Workspace, **supprime tout ancien dossier** `UPDATE_2026_11_18…` (v1 à v5).
3. Clic droit sur **Workspace** ▸ **Insert from File…**, puis choisis
   `INSTALLATION_RAPIDE/UPDATE_2026_11_18_v6.rbxmx`.
4. Dans la barre de commande (*Affichage ▸ Barre de commande*), colle cette ligne et appuie sur Entrée :
   ```lua
   require(workspace.UPDATE_2026_11_18_v6.INSTALL)()
   ```
5. Dans l'Output :
   - la 1re ligne doit être **« 🚀 Installateur v6… »** ;
   - puis **« ✅ INSTALLATION TERMINÉE : … scripts remplacés, … créés »**.

**Ce que fait l'installateur :**
- Chaque script est **échangé entier** : même nom, même place, même état activé/désactivé, mêmes attributs, et ses objets enfants suivent.
  (Il ne copie pas le code, car Studio refuse d'écrire plus de 200 000 caractères dans un script par programme.)
- Les versions remplacées vont dans **`ServerStorage ▸ BACKUP_avant_maj_v6`** (donc tes versions précédentes).
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
- **ServerScriptService :** `CombatSystem ▸ CombatServer` · `checkpoints system` · `anti fly/tp server` · `PLAYER UGC STATS` · `new donation board server` · `notif chat ` · `DAILY TOOLs` · `10 died = offer 2500 points` · `time` · `STATS` · `ask favorite game` · `datastore alr ask favorite game` · `leave popup` · `server referal friend invite`
- **ServerStorage ▸ AdminClientScripts. :** `Admin client`
- **ReplicatedStorage :** `LeaderboardCore` · `WeaponSystem ▸ WeaponController` · `WeaponSystem ▸ WeaponServer` · `WeaponSystem ▸ CombatSettings`
- **StarterGui :** `ShiftLockButton ▸ ImageButton ▸ ShiftGUI` · `VIP offer ▸ make pop th add` · `UGCshop ▸ ShopFrame ▸  UGC SHOP GENERATOR`
- **StarterPlayerScripts :** `DeathCam` · `PlayerProfileHover` · `offers on screen` · `script proposer achat skip obby` · `EngageTrack` · `rebirth offer notify event` · `fenetre dachat gravity coil` · `Fenetre dachat fusion coil` · `Fenetre achat speedcoil` · `achat x2coin` · ` ADMIN ABUSE — DÉGRADÉ SUR LE BOOST DU BILLBOARD`
- **StarterCharacterScripts :** `ask favorite game`

**Supprimer :** StarterPlayerScripts ▸ `daily notification`
</details>

---

## 🆕 NOUVEAU DANS LA v6 (tes derniers retours)

| Ton retour | Ce qui est fait |
|---|---|
| Pas besoin de CANCEL, FILTER sert à refermer | **CANCEL est retiré.** Un 2e appui sur FILTER rembobine le panneau sans rien changer. Il reste **RESET** et **APPLY**, qui glissent de dessous le panneau. |
| La disposition d'avant, avec des boutons qui ne s'enfoncent pas | Retour de **SHOW · TYPE · SORT BY**, en boutons 3D (dégradé + socle) **fixes** : plus aucun effet d'enfoncement. Couleurs dans le bleu du bouton : bleu = choisi, ardoise = pas choisi, grisé = contraire. |
| Pas de X rouge, on doit voir que ça vient du bouton | **Pas de X.** Le panneau **sort du bouton FILTER** : une petite pointe le relie au bouton, il se déroule vers le bas et remonte dedans quand on referme. La flèche du bouton passe ▼ / ▲. |
| Contraires impossibles ensemble | 1re ligne de SHOW : Available / Low stock / Sold out (un seul). 2e ligne : New + Owned / Not owned (un seul des deux). Un seul tri. Les contraires sont grisés. |
| Least / Most | **Most left / Least left** = tri sur le stock **restant**. |
| Tous les appareils | Le panneau suit la taille de la fenêtre, avec un minimum pour le doigt (mobile) et pour la télé (console). Sur un petit écran, il défile au lieu de dépasser. |
| Console, dans tout le shop | <ul><li>La **touche Y** (icône officielle Xbox / PlayStation) est affichée à côté de FILTER.</li><li>**Y** ouvre et ferme le filtre.</li><li>**B** ferme le filtre, puis le shop.</li><li>**A** choisit.</li><li>À l'ouverture du shop, la **1re carte est sélectionnée**. La sélection ne sort pas du shop, ni du filtre quand il est ouvert. La grille défile toute seule.</li><li>Un **cadre jaune** montre le bouton sélectionné.</li></ul> |
| « FIND ME » sous la loupe | La loupe a **« FIND ME » écrit en petit dessous**. Toute la zone est cliquable. |

> 🩹 **Correction importante :** le script du shop UGC de la **v5** dépassait la limite de Luau (200 variables locales actives dans un script). Si tu as installé la v5, le shop UGC ne marchait sans doute plus du tout. En v6, le filtre est dans sa propre fonction : 145 au maximum. J'ai ajouté ce contrôle à mes vérifications, et tous les scripts de la mise à jour sont en dessous de 200.

## NOUVEAU DANS LA v5

### ⚡ Le lag en PvP : la cause

C'est la **vue du tueur** (la caméra que voit la victime après sa mort).
1. Quand tu tues quelqu'un en arène, **ton** jeu envoie ce que tu vois pendant environ 6,5 secondes, pendant que tu continues à te battre.
2. Avant la v5, il envoyait :
   - ta caméra et ton arme **30 fois par seconde** ;
   - **chaque effet en entier**, jusqu'à 60 fois par seconde, sur le canal « fiable » (celui qui attend que tout arrive dans l'ordre). Un effet, c'est un flash, une traçante avec tout son style (une vingtaine de réglages et de couleurs), une douille, un son, un hitmarker avec sa config complète ;
   - la liste complète des pièces de ton arme (jusqu'à 250) **à chaque kill**.
3. Résultat : la connexion **du joueur qui fait des kills** est saturée, surtout sur mobile.
   - Les positions de son perso partent en retard et par paquets : **chez les autres, il « se TP »**.
   - Ses tirs et ses dégâts arrivent plus tard : **plus de délai**.
   - Plus un joueur tue, plus il envoie : ce sont les meilleurs joueurs qui laggent le plus, et **seulement en PvP**.

En plus, chaque balle partait en 2 messages (le son, puis le flash).

### ✅ Ce qui est corrigé
| Avant | Maintenant |
|---|---|
| 30 images/s pendant la vue du tueur | **20 images/s** (10 si ton ping dépasse 180 ms). La victime voit toujours une vue fluide : elle glisse entre deux images (tampon 0,15 s). |
| Effets envoyés à chaque image, jusqu'à 60 envois/s | **Regroupés : 15 envois/s.** |
| Styles et configs recopiés en entier à chaque balle | Envoyés **une fois**, puis un simple numéro (rappel toutes les 3 s). La victime voit exactement les mêmes effets. |
| Toutes les douilles envoyées | 2 au maximum par envoi (effet purement visuel). |
| Liste des pièces de l'arme renvoyée à chaque kill | Envoyée **une fois par arme**. Le serveur la garde et la donne lui-même aux victimes suivantes. |
| 2 messages par balle (son + flash) | **1 seul.** Le serveur joue le son en recevant le flash. Les anciennes armes qui envoient encore le son à part marchent toujours. |

**Rien ne change dans le gameplay :** mêmes dégâts, même validation des tirs, mêmes effets chez la victime.
Tous les réglages sont dans `ReplicatedStorage ▸ WeaponSystem ▸ CombatSettings ▸ Death` : `StreamRate`, `StreamRateHighPing`, `HighPing`, `EventRate`, `MaxShellsPerPacket`.

### Tes autres retours
| Ton retour | Ce qui est fait |
|---|---|
| Vue PvP sans arme : rotation moins fluide, curseur qui réapparaît en tournant vite | **Trouvé :** la « garde souris » de `DeathCam` libérait la souris à chaque image, parce que tu n'avais pas d'outil en main. Elle reconnaît maintenant la vue sans arme. Le perso tourne aussi avec la même règle que les armes (0,5° au lieu de 2°). |
| Loupe trop petite | **Plus grosse** (84 % de la hauteur de l'en-tête au lieu de 60 %). |
| Loupe quand tu n'es pas dans le top | Un message s'affiche : « You're not in the top 100 yet — your score is at the bottom ». **Ta ligne « -- » est ajoutée sous le dernier**, avec ton score lu dans le même classement, et la liste descend jusqu'à elle. Tu vois l'écart avec le dernier. La ligne reste jusqu'à ce que tu changes d'onglet. |
| Filtre : une seule liste (*remplacé en v6 par la disposition SHOW / TYPE / SORT BY*) | **Une seule liste de rangées pleine largeur**, les plus utiles en premier : Available · Not owned · New · Price ↑ / ↓ · Stock left ↑ / ↓ · Type · Low stock · Sold out · Owned. On n'en voit qu'une partie (5 rangées et demie), le reste en faisant défiler. |
| Type : une autre liste qui se déroule au bon endroit | Clic sur **Type ▶** : sa sous-liste se déroule **juste en dessous**, et la liste défile toute seule pour la montrer. Re-clic : elle se rembobine. Plusieurs types possibles. |
| Trier par stock restant (Least / Most) | **« Stock left: Least » et « Stock left: Most »** trient sur le stock **restant**. Épuisé = 0. Le stock total n'est plus utilisé. |
| Boutons sous la liste, qui glissent derrière | CANCEL · RESET · APPLY sont **sous** la liste. Ils **glissent de derrière elle** quand elle se déroule et repartent derrière quand elle se rembobine. |
| Couleurs | **Le bleu du bouton, en sobre :** fond bleu nuit, cases et accents bleus, APPLY bleu, CANCEL / RESET bleu foncé. Les choix contraires sont **grisés**, et en prendre un retire l'autre. |

## NOUVEAU DANS LA v4

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
- **Vue PvP sans arme :** `ArenaViewKeeper`, mets `ENABLED = false` (ligne 26).
- **Vue du tueur :** `CombatSettings ▸ Death`, remets `StreamRate = 30` et `EventRate = 60` si tu veux l'ancien rythme (déconseillé).
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
9. **Shop UGC :** bouton FILTER plat, panneau SHOW / TYPE / SORT BY qui se déroule du bouton, tri par stock restant, navigation manette complète (voir plus haut).
10. **Parrainage :** paie seulement si l'invité découvre le jeu. Ça ferme la faille des amis qui s'invitent entre eux et celle des joueurs qui jouaient déjà.
11. **Arène sans arme :** même vue qu'avec une arme, B change la vue, panneau des contrôles (voir plus haut).
12. **Admin :** accueil en onglets + recherche (voir plus haut).
13. **Arc-en-ciel du boost :** pour tout boost temporaire.
14. **Profils :** 🟢 Online / ⚫ Offline, même sur un autre serveur.
15. **Lag PvP :** vue du tueur beaucoup plus légère, 1 message par balle au lieu de 2 (voir plus haut).

---

## ✅ Vérifié de mon côté (sans pouvoir lancer le jeu)
- Les 42 fichiers (41 scripts + l'installateur) — **nouveau contrôle v6 : aucun script ne dépasse 200 variables locales actives** passent l'analyseur de syntaxe Luau. Ce même analyseur valide les 669 scripts d'origine sans erreur.
- **Nouveau contrôle :** « utilisé avant d'être créé » (l'erreur de `ArenaViewKeeper`) sur tous les scripts → **0**. J'ai vérifié qu'il détecte bien l'erreur d'origine.
- Aucune fonction ni variable de niveau principal perdue (comparaison avec les originaux).
- `time` reste à 199 variables locales (limite 200). Le panel admin n'a aucune variable locale en plus (162).
- Le modèle `.rbxmx` contient exactement le même code que les fichiers (vérifié octet par octet).

## 🧪 À tester dans Studio avant de publier
0. **Lag PvP (à 2 joueurs minimum, idéalement sur un vrai serveur) :**
   - tue l'autre joueur : sa vue du tueur doit être fluide, avec tes traçantes, flashs, hitmarkers et sons ;
   - enchaîne 2 kills avec la même arme : la 2e victime voit aussi ton arme ;
   - le son de tir s'entend chez l'autre joueur ;
   - *(Studio : onglet Test ▸ « Clients et serveurs », 2 joueurs, puis Démarrer)*.
1. **Arène :**
   - sans arme, tourne la caméra très vite : **aucun curseur** ne doit apparaître ;
   - range et ressors ton arme plusieurs fois : la vue doit rester **identique**, sans saut ni relais ;
   - sans arme : pas de viseur, panneau Shift / C / B / H, B change la vue, H cache le panneau ;
   - teste aussi au doigt (émulateur mobile) et à la manette si tu peux ;
   - aucune erreur rouge dans l'Output.
2. **Shop UGC :**
   - FILTER déroule le panneau depuis le bouton, un 2e appui le rembobine, et RESET / APPLY glissent de dessous ;
   - « Most left / Least left » trie bien sur le stock restant ;
   - **manette** (branche-en une sur PC ; Studio n'en simule pas) : Y, B, A, la sélection et le cadre jaune ;
   - les choix contraires s'excluent ;
   - APPLY, pastilles, RESET fonctionnent ;
   - teste aussi en mobile (émulateur).
3. **Leaderboards :**
   - ALL / FRIENDS / 🔍 ;
   - 🔍 sur un board où tu n'es pas : message, puis ta ligne « -- » en bas avec ton score (vrai serveur publié) ;
   - en FRIENDS : un ami hors top affiche « -- ». Son score met environ une seconde à apparaître ; il est lu sur le serveur, donc à vérifier sur un **vrai serveur publié**.
4. **Admin :** les onglets et la recherche, puis la fiche d'un joueur (badges dans le coin, rien qui déborde).
5. **Boost :** achète ou donne-toi un boost temporaire → arc-en-ciel sur ton billboard.
6. **Profils :** clique sur un joueur du serveur (🟢 Online), puis ouvre depuis un leaderboard la fiche de quelqu'un qui n'est pas là (🟢 Online sur un autre serveur, ou ⚫ Offline). Le statut d'un autre serveur ne marche que sur un **vrai serveur publié** : MemoryStore n'est pas partagé entre serveurs en Studio.
