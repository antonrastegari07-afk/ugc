# Mise à jour du 18/11/2026 (v18) — installation + ce qui change

## ⚡ INSTALLATION RAPIDE (environ 2 minutes)

> Marche **par-dessus la v2 à v17** que tu as déjà installée, et aussi sur un jeu jamais mis à jour.

1. **Fais une copie de ton jeu** : *Fichier ▸ Enregistrer sous*.
2. Dans le Workspace, **supprime tout ancien dossier** `UPDATE_2026_11_18…` (v1 à v17).
3. Clic droit sur **Workspace** ▸ **Insert from File…**, puis choisis
   `INSTALLATION_RAPIDE/UPDATE_2026_11_18_v18.rbxmx`.
4. Dans la barre de commande (*Affichage ▸ Barre de commande*), colle cette ligne et appuie sur Entrée :
   ```lua
   require(workspace.UPDATE_2026_11_18_v18.INSTALL)()
   ```
5. Dans l'Output :
   - la 1re ligne doit être **« 🚀 Installateur v18… »** ;
   - puis **« ✅ INSTALLATION TERMINÉE : … scripts remplacés, … créés »**.

**Ce que fait l'installateur :**
- Chaque script est **échangé entier** : même nom, même place, même état activé/désactivé, mêmes attributs, et ses objets enfants suivent.
  (Il ne copie pas le code, car Studio refuse d'écrire plus de 200 000 caractères dans un script par programme.)
- Les versions remplacées vont dans **`ServerStorage ▸ BACKUP_avant_maj_v18`** (donc tes versions précédentes).
  Les copies de secours précédentes ne sont pas touchées. Celle de la v2 (`BACKUP_avant_maj_2026_11_18`) contient les scripts d'**origine**.
- Il crée les nouveaux scripts et retire `daily notification` (déplacé dans la copie de secours, pas détruit).
- **Ctrl+Z annule toute l'installation d'un coup.** Rien n'est publié.

<details><summary>🖐️ Installation manuelle (si tu préfères)</summary>

Extension des fichiers : `.server.lua` = Script · `.client.lua` = LocalScript · `.module.lua` = ModuleScript.
Remplacer = ouvrir le script, Ctrl+A, coller. Ne change ni le nom ni la place.

**Créer :**
- ReplicatedStorage : `PopupControlConfig`, `PopupGate`, `LeaderboardStyle` (ModuleScripts)
- ServerScriptService : `PopupControl_Server`, `FriendsBoard_Server`, `Presence_Server` (Scripts)
- StarterPlayerScripts : `ArenaViewKeeper`, `ScrollTapGuard`, `HudLayoutClient`, `EmptyArenaPrompt` (LocalScripts)
- ReplicatedStorage : `HudLayout` (ModuleScript)

**Remplacer :**
- **ServerScriptService :** `CombatSystem ▸ CombatServer` · `checkpoints system` · `anti fly/tp server` · `PLAYER UGC STATS` · `new donation board server` · `notif chat ` · `DAILY TOOLs` · `10 died = offer 2500 points` · `time` · `STATS` · `ask favorite game` · `datastore alr ask favorite game` · `leave popup` · `server referal friend invite`
- **ServerStorage ▸ AdminClientScripts. :** `Admin client`
- **ReplicatedStorage :** `LeaderboardCore` · `WeaponSystem ▸ WeaponController` · `WeaponSystem ▸ WeaponServer` · `WeaponSystem ▸ CombatSettings`
- **StarterGui :** les 6 `animation …` des boutons de gauche + `Bouton hide ▸ Frame ▸ TextButton ▸ gestion hide` · `ShiftLockButton ▸ ImageButton ▸ ShiftGUI` · `VIP offer ▸ make pop th add` · `UGCshop ▸ ShopFrame ▸  UGC SHOP GENERATOR`
- **StarterPlayerScripts :** `DeathCam` · `PlayerProfileHover` · `offers on screen` · `script proposer achat skip obby` · `EngageTrack` · `rebirth offer notify event` · `fenetre dachat gravity coil` · `Fenetre dachat fusion coil` · `Fenetre achat speedcoil` · `achat x2coin` · ` ADMIN ABUSE — DÉGRADÉ SUR LE BOOST DU BILLBOARD`
- **StarterCharacterScripts :** `ask favorite game`

**Supprimer :** StarterPlayerScripts ▸ `daily notification`, et dans `UGCshop ▸ ShopFrame` : `Selected ▸` Korblox Dominus, Cyber Raven Wings, Korblox Sword, Demon Sword, Magic Dominus, Fluffy Messy Boy Hair, puis `ScrollingFrame ▸` CyberWingsButton, KorbloxDominusButton, KorbloxSwordButton, DemonSwordButton, FluffyHairButton (garde **MagicDominusButton** et **NoUGCSelected**)
</details>

---

## 🆕 NOUVEAU DANS LA v18 — correctif : le bloc du haut ne dépasse plus
- En v17, le trio et la roulette **sortaient par le haut de l'écran**.
- **La cause :** Roblox donne **toutes** les positions (`AbsolutePosition`) à partir du **dessous** de sa barre du haut, même pour une interface qui couvre cette barre. La v17 mesurait les boutons How To Play / ⚙️ environ 58 px trop haut et alignait le bloc dessus.
- **La correction :** une seule règle, valable partout : position à l'écran = `AbsolutePosition` + `GetGuiInset()`. Les deux erreurs vues sur tes captures (v16 trop bas, v17 trop haut) viennent toutes les deux de ce point. Elles sont corrigées ensemble.
- Résultat attendu : le titre « Current Stage » est **à la même hauteur que ⚙️ / How To Play**, et tout le bloc est visible.

## NOUVEAU DANS LA v17 — trio + roulette tout en haut
- Skip Obby · Current Stage · Skip Level · la roulette sont maintenant **collés tout en haut de l'écran**, à la **même hauteur que ⚙️ / How To Play / série de jours**. Le titre « Current Stage » qui dépasse du cadre est compté, donc il n'est jamais coupé.
- **Pourquoi ils restaient plus bas :** Roblox mesure les positions de certains ScreenGui **sous** sa barre du haut. Le calcul les plaçait donc trop bas de la hauteur de cette barre. Le bloc du haut convertit maintenant correctement selon chaque ScreenGui.
- Ils évitent toujours les boutons du haut. Sur PC ils restent centrés. Sur mobile (boutons du haut à droite), ils se décalent juste assez. S'il n'y a vraiment pas la place, ils passent juste en dessous.
- **Le bloc de gauche ne bouge pas** (même place qu'en v16).
- Pour revenir à la hauteur de ta disposition Studio : `HudLayout ▸ Groups ▸ top ▸ stickToTop = false`.

## NOUVEAU DANS LA v16 — placement des boutons FIABLE + 1er UGC déjà choisi

### Ce qui n'allait pas (ta capture)
- **Le trio du haut et la roulette** étaient réduits au minimum et coincés entre How To Play et la série de jours. Cause : pour éviter les icônes de Roblox, la v15 lisait une zone fournie par Roblox (`GuiService.TopbarInset`) qui ne donne pas ce qui était attendu. Elle « bloquait » presque toute la largeur, et le bloc rétrécissait jusqu'au minimum.
- **Le bouton Invite** se retrouvait derrière UGC Shop. La v15 relisait la place de chaque bouton en jeu, ce qui la rend dépendante de l'état de l'interface au moment de la lecture.

### Ce qui change (`HudLayout` v2)
- **Ta disposition est écrite dans le module**, calculée depuis tes valeurs Studio en 16:9. Le script ne relit plus rien en jeu : aucun autre script, aucun chargement, aucun état caché ne peut fausser le calcul. Tu déplaces un bouton dans Studio ? Mets sa nouvelle place dans `HudLayout ▸ Groups`.
- **Plus de `TopbarInset`.** Seuls les **vrais boutons mesurés** du haut sont évités, plus une marge fixe pour les icônes Roblox : ⚙️, cloche, How To Play, série de jours. Les grands cadres (fonds, voiles, panneaux) sont ignorés.
- **Jamais plus petit que 75 %.** S'il manque de la place, le bloc du haut passe **juste en dessous** des boutons du haut au lieu de rétrécir.
- **Garde-fou :** si un autre script déplace un de ces boutons, il est remis à sa place, sauf pendant l'animation de survol. S'il insiste, le module le laisse faire et l'écrit dans l'Output.
- **`HudLayout ▸ Debug = true`** écrit dans l'Output la place calculée (écran, place disponible, échelle). Utile si tu veux me renvoyer un résultat.
- Simulé sur **ton écran exact (2000×887)** : le trio et la roulette restent à pleine taille, centrés, sans rien toucher. Le résultat est le même sur PC 1280×720, sur téléphone et sur tablette (boutons du haut à droite).

### ⭐ Shop UGC : le 1er UGC est déjà sélectionné (moins de friction)
- À l'ouverture du shop, le **1er UGC de la grille** est choisi tout seul : sa fiche et son bouton Buy sont affichés, et sa carte est en **vert**. Le 1er encore en vente passe avant un épuisé.
- Si le joueur avait déjà choisi un UGC encore visible, son choix est gardé.

## NOUVEAU DANS LA v15 (tes derniers retours)

### 📐 Haut de l'écran : trio + roulette, sans jamais toucher les boutons du haut
- La **roulette** fait maintenant partie du bloc du haut (Skip Obby · Current Stage · Skip Level · roulette) : mêmes écarts sur tous les écrans. Son ancien script la déplaçait à 25 % de la largeur sur mobile ; il est remplacé (même animation, sans déplacement).
- Le bloc **mesure en direct** la place des boutons du haut : ceux de Roblox, et tes boutons How To Play et série de jours (**à gauche sur PC, à droite sur mobile**). Il reste centré quand c'est possible, sinon il se décale juste assez, et en dernier recours il rétrécit. Il ne les chevauche jamais, sur aucun appareil.
- Simulé avec les vraies valeurs de ton jeu :
  - PC : rien ne bouge par rapport à avant.
  - Tablette : le bloc se décale de quelques dizaines de pixels pour ne pas toucher How To Play et la série.
  - Téléphone : tout tient sans rétrécir.
- **Bouton Invite :** il fait partie du bloc de gauche (mêmes écarts partout). Aucun autre script ne le déplace. Tes `StyleLink` sont vides (aucune feuille de style), ils n'y sont pour rien.

### ⚔️ Nouveau : « ARENA IS EMPTY » (`StarterPlayerScripts ▸ EmptyArenaPrompt`)
- Tu entres en PvP et **personne d'autre n'y est** sur ce serveur : **7 secondes plus tard**, si c'est toujours vide **et** qu'un autre serveur a des joueurs en PvP, une fenêtre s'affiche.
  - Elle te dit combien de joueurs ce serveur a en PvP.
  - **FIND SERVERS** ouvre le panneau des serveurs (le même que « 1v1 Servers » du lobby).
  - **STAY HERE** ferme la fenêtre.
- **Pourquoi pas tout de suite à l'entrée :**
  - d'autres joueurs arrivent souvent juste après toi ;
  - l'arrivée a déjà son bouclier, sa caméra et la map qui charge ;
  - on revérifie juste avant d'afficher, donc la fenêtre n'apparaît pas pour rien.
- **Jamais envahissante :**
  - une fois par entrée en arène, au plus 3 fois par session, 2 min 30 minimum entre deux fenêtres ;
  - jamais dans les 90 s après un changement de serveur ;
  - elle se ferme toute seule si quelqu'un entre en PvP, si tu sors, si tu meurs, ou au bout de 25 s.
- **Style de tes Paramètres et du HUD d'arène :** bandeau bleu brillant, panneau bleu nuit, boutons 3D vert et gris, texte Fredoka contourné.
  - La souris est libérée même avec une arme en main.
  - À la manette, FIND SERVERS est sélectionné et B ferme.
- `1v1 cross server local` reçoit un petit ajout : un `BindableEvent` « Open » pour ouvrir le panneau depuis un autre script. Rien d'autre ne change.
- **Tester dans Studio :** il n'y a pas de vrais serveurs en Studio. Mets `StudioTest = true` en haut de `EmptyArenaPrompt` pour voir la fenêtre, puis remets `false` avant de publier.

## NOUVEAU DANS LA v14 — correctif
- **Les 3 boutons du haut (Skip Obby · Current Stage · Skip Level) avaient disparu en v13.**
  - La cause : `ArenaHUD` cache l'ancienne case kills (`# Stage ▸ Frame2`) en l'envoyant hors de l'écran. `HudLayout` la comptait dans le bloc du haut : le bloc paraissait immense et tout rétrécissait jusqu'à disparaître.
  - La correction : cette case est retirée du bloc, et tout cadre placé hors de l'écran par un autre script est désormais ignoré.
  - Vérifié par simulation avec les vraies valeurs de ton jeu : en 16:9, les boutons sont exactement à leur place d'origine, et les écarts restent identiques en 21:9, 4:3 et sur téléphone.

## NOUVEAU DANS LA v13 (tes derniers retours)

### 📐 Les boutons de l'écran ne se décollent plus
- **La cause :** la position de chaque bouton était en % de la **largeur** de l'écran, mais sa taille (bloquée par `UIAspectRatioConstraint`) suivait la **hauteur**. En plus, les animations de survol re-forçaient la position (une valeur PC, une autre mobile). Quand le format de l'écran changeait, les écarts grandissaient ou se resserraient.
- **La correction :**
  - Nouveau module `ReplicatedStorage ▸ HudLayout` et script `StarterPlayerScripts ▸ HudLayoutClient`. Ta disposition actuelle (celle d'un écran 16:9) est relue au démarrage, puis **tailles ET écarts suivent la hauteur de l'écran** : le bloc reste identique partout.
  - Le bloc de gauche (Hide Gui, UGC Shop, Shop, Points, Rebirth, Quests, Rewards, Invite) reste **collé au bord gauche**. Le trio du haut (Skip Obby · Current Stage · Skip Level) reste **centré**.
  - Si un bloc ne tient plus en largeur, il **rétrécit en entier**, sans jamais se chevaucher.
  - Recalcul seulement quand la taille de l'écran change : aucun coût en jeu.
- **Les 6 scripts d'animation de survol** (`animation ugc`, `animation shop`, `animation Points`, `animation rebirth`, `animation quest`, `animation daily`) et **`gestion hide`** sont remplacés. Même effet de survol qu'avant, mais à partir de la bonne place. `gestion hide` garde toute sa logique pour cacher et afficher l'interface.
- ↩️ **Revenir à avant :** `HudLayout ▸ Enabled = false`.
- Les places horizontales « PC » de tes anciens scripts sont gardées dans `HudLayout ▸ Groups`. Tu peux les ajuster là, ou y ajouter des boutons (le côté droit par exemple).

### 🔎 Filtre du shop UGC
- **Taille sur tous les appareils :** le bouton FILTER et son panneau suivent maintenant la **taille de la fenêtre du shop**, et plus le type d'appareil. Avant, un minimum « mobile » les rendait trop gros sur téléphone. Le panneau ne dépasse jamais 45 % de la largeur de la fenêtre, et sa pointe reste sous le centre du bouton.
- **Les options les plus importantes en premier :** **SORT BY** passe tout en haut : **Least left** (où il en reste le moins), **Price: Low**, Price: High, Most left, Default. Puis SHOW (Available, Not owned, New, Low stock, Sold out, Owned), puis TYPE.
- **Least left** met les UGC épuisés **à la fin** : en premier, ceux qui sont **encore achetables** mais où il en reste le moins.

## NOUVEAU DANS LA v12 — vérification sécurité avant publication

| Point d'entrée | Risque trouvé | Correction |
|---|---|---|
| `FriendsBoard_Server` (scores des amis hors top) | Il acceptait **n'importe quel UserId**, 50 toutes les 3 s : un tricheur pouvait faire lire des milliers de scores au hasard et **user le budget de lectures DataStore** du serveur (sauvegardes et classements ralentis). | Seulement les **vrais amis** du joueur (liste demandée à Roblox par le serveur, gardée 10 min) + lui-même, et **300 lectures max par joueur / 10 min**. Le classement FRIENDS et la loupe marchent pareil. |
| `Presence_Server` (en ligne / hors ligne) | 2 questions/s par joueur : un tricheur entamait le **quota MemoryStore** du jeu. | **1 question / 1,5 s** ; `PlayerProfileHover` attend en conséquence (rien de visible pour un vrai joueur). |

Tout le reste a été relu (popups admin, stats, favori, popup de départ, retour d'AFK, vue du tueur, son des tirs, dons, parrainage) : voir le récapitulatif de la réponse.

## NOUVEAU DANS LA v11 (tes derniers retours)

| Ton retour | Ce qui est fait |
|---|---|
| Erreurs dans l'Output (« UGC ID … non trouvé », « UGC … introuvable! ») | Elles venaient des **6 anciens panneaux** et **5 anciennes cartes** du shop UGC, que le générateur remplace depuis longtemps. Il les détruisait au lancement, mais leurs vieux scripts avaient le temps de démarrer avant. L'installateur les **range dans la copie de secours**, sans rien détruire. Le générateur garde ses 2 modèles, `MagicDominusButton` et `NoUGCSelected`. Il n'y avait pas de risque de confusion de nom : le générateur détruisait déjà ces anciens panneaux. |
| Quêtes sur mobile : en glissant pour défiler, on déclenche un bouton (notif « completed »…) | Nouveau script **`ScrollTapGuard`** (StarterPlayerScripts). Dès qu'une liste défile vraiment sous le doigt (plus de 6 px), ses boutons ignorent le relâché, puis redeviennent normaux 0,1 s après. Un simple tap reste un clic. Ça vaut pour **toutes** les listes du jeu (quêtes, shop UGC, boutiques…), sans modifier leurs scripts. Les curseurs ne sont pas touchés, et rien ne change sur PC ni à la manette. |

## NOUVEAU DANS LA v10
- Le bouton FILTER revient au bleu d'avant, et un bouclier invisible empêche de cliquer à travers le panneau du filtre.

## NOUVEAU DANS LA v9 (tes derniers retours)

| Ton retour | Ce qui est fait |
|---|---|
| Pas de boutons gris pour les choix contraires | Les choix gardent leur **couleur normale**. Prendre l'un retire toujours l'autre (Available / Low stock / Sold out, Owned / Not owned, un seul tri), mais rien n'est grisé. |
| Couleur du bouton FILTER | *(Le bleu ciel 95, 216, 253 était trop clair : on est revenu au bleu d'avant, 55, 150, 240.)* |
| (v18) On pouvait cliquer sur ce qui est derrière le panneau | Un **bouclier invisible** couvre le panneau quand il est ouvert : un clic dessus ne touche plus jamais les cartes ou boutons du shop derrière. |
| La notification du leaderboard est horrible, et le contour du texte pire | Refaite : une **petite bande sombre, discrète**, au texte blanc **sans aucun contour**. Elle apparaît et s'efface en fondu après 3 secondes. Le texte est plus court : « Not in the top 100 yet · your score is below ». |

## NOUVEAU DANS LA v8

| Ton retour | La cause | Ce qui est fait |
|---|---|---|
| Le vert de la carte UGC sélectionnée part tout seul après un moment | À chaque mise à jour du stock envoyée par le serveur, le script remettait la couleur d'origine sur la carte, **même si elle était sélectionnée**. | **Une seule fonction** décide la couleur de toutes les cartes : **sélectionnée = vert**, épuisée = gris, sinon la couleur d'origine. La mise à jour du stock ne peut plus enlever le vert. |
| Le vert ne se remet pas toujours sur l'ancienne carte | L'ancienne carte était remise selon un test d'épuisement qui ne correspondait pas toujours à ce qui était affiché. | À chaque nouvelle sélection, **toutes les cartes sont repeintes** : l'ancienne perd toujours son vert. Il y a peu de cartes, donc ça ne coûte rien. |
| On ne voit plus la loupe, juste « FIND ME » | Je lui avais donné une **largeur 0**. La contrainte de proportion la faisait tenir dans une boîte de largeur 0, donc un carré de 0 px. | La loupe prend toute la largeur disponible, et la contrainte en fait un **rond bien visible** au-dessus de « FIND ME ». |

## NOUVEAU DANS LA v7

| Ton retour | Ce qui est fait |
|---|---|
| Léger contour noir sur le panneau | Contour **noir léger** (1,5 px, semi-transparent) autour du panneau et de sa pointe, raccordés sans trait entre les deux. |
| APPLY à gauche, RESET à droite, dans le panneau | **APPLY (vert) à gauche, RESET (rouge) à droite**, en bas **du panneau**, sous un fin trait. Ils restent fixes, hors de la partie qui défile. |
| Ne pas les confondre avec les choix | Les choix sont en **bleu** (choisi) ou en **ardoise** (pas choisi). APPLY est **vert** et RESET **rouge** : impossible de les confondre. |

Le panneau se déroule et se rembobine toujours depuis le bouton FILTER. Il n'y a plus de boutons qui glissent : ils font partie du panneau.

## NOUVEAU DANS LA v6

| Ton retour | Ce qui est fait |
|---|---|
| Pas besoin de CANCEL, FILTER sert à refermer | **CANCEL est retiré.** Un 2e appui sur FILTER rembobine le panneau sans rien changer. Il reste **RESET** et **APPLY**, qui glissent de dessous le panneau. |
| La disposition d'avant, avec des boutons qui ne s'enfoncent pas | Retour de **SHOW · TYPE · SORT BY**, en boutons 3D (dégradé + socle) **fixes** : plus aucun effet d'enfoncement. Couleurs dans le bleu du bouton : bleu = choisi, ardoise = pas choisi, grisé = contraire. |
| Pas de X rouge, on doit voir que ça vient du bouton | **Pas de X.** Le panneau **sort du bouton FILTER** : une petite pointe le relie au bouton, il se déroule vers le bas et remonte dedans quand on referme. La flèche du bouton passe ▼ / ▲. |
| Contraires impossibles ensemble | 1re ligne de SHOW : Available / Low stock / Sold out (un seul). 2e ligne : New + Owned / Not owned (un seul des deux). Un seul tri. *(v9 : plus de grisé.)* |
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
00. **Boutons de l'écran :** dans Studio, essaie plusieurs formats (Test ▸ émulateur d'appareil : téléphone, tablette, et redimensionne la fenêtre). Les 8 boutons de gauche et le trio du haut doivent garder les mêmes écarts. Survole-les : l'animation doit repartir de la bonne place.
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
   - FILTER déroule le panneau depuis le bouton (léger contour noir), un 2e appui le rembobine ;
   - APPLY (vert, à gauche) et RESET (rouge, à droite) sont en bas du panneau ;
   - « Most left / Least left » trie bien sur le stock restant ;
   - plus d'erreur « UGC ID … non trouvé » dans l'Output ;
   - **manette** (branche-en une sur PC ; Studio n'en simule pas) : Y, B, A, la sélection et le cadre jaune ;
   - les choix contraires s'excluent ;
   - APPLY, pastilles, RESET fonctionnent ;
   - teste aussi en mobile (émulateur).
3. **Leaderboards :**
   - ALL / FRIENDS / 🔍 ;
   - 🔍 sur un board où tu n'es pas : message, puis ta ligne « -- » en bas avec ton score (vrai serveur publié) ;
   - en FRIENDS : un ami hors top affiche « -- ». Son score met environ une seconde à apparaître ; il est lu sur le serveur, donc à vérifier sur un **vrai serveur publié**.
4. **Admin :** les onglets et la recherche, puis la fiche d'un joueur (badges dans le coin, rien qui déborde).
5. **Mobile (émulateur ou téléphone) :** fais défiler les quêtes en posant le doigt sur un bouton : aucune notif ne doit apparaître. Un simple tap doit toujours marcher.
6. **Boost :** achète ou donne-toi un boost temporaire → arc-en-ciel sur ton billboard.
7. **Profils :** clique sur un joueur du serveur (🟢 Online), puis ouvre depuis un leaderboard la fiche de quelqu'un qui n'est pas là (🟢 Online sur un autre serveur, ou ⚫ Offline). Le statut d'un autre serveur ne marche que sur un **vrai serveur publié** : MemoryStore n'est pas partagé entre serveurs en Studio.
