# Mise à jour du 18/11/2026 — installation + ce qui change

## ⚡ INSTALLATION RAPIDE (recommandée, environ 2 minutes)

1. **Fais une copie de ton jeu** : *Fichier ▸ Enregistrer sous* (sécurité en plus).
2. Dans Studio, fais un clic droit sur **Workspace** ▸ **Insert from File…**, puis choisis
   `INSTALLATION_RAPIDE/UPDATE_2026_11_18.rbxmx`.
   Un dossier `UPDATE_2026_11_18` apparaît dans le Workspace. Les scripts dedans sont désactivés et ne font rien.
3. Ouvre la barre de commande : *Affichage (View) ▸ Barre de commande (Command Bar)*. Colle cette ligne et appuie sur Entrée :
   ```lua
   require(workspace.UPDATE_2026_11_18.INSTALL)()
   ```
4. La fenêtre **Output** affiche le résultat : « ✅ INSTALLATION TERMINÉE : 28 scripts remplacés, 5 créés… ».
   S'il y a une ligne « ⚠️ À VÉRIFIER », lis-la : ce script-là est à faire à la main (voir plus bas).

**Ce que fait l'installateur :**
- Il range une **copie de chaque ancien script** dans `ServerStorage ▸ BACKUP_avant_maj_2026_11_18`. Pour revenir en arrière sur un script, tu recopies son code depuis là.
- Il remplace le code des 28 scripts **sans changer leur nom, leur place, ni s'ils sont activés**.
- Il crée les 5 nouveaux scripts.
- Il retire le LocalScript `daily notification` en le déplaçant dans la copie de secours, sans le détruire.
- Il supprime le dossier d'installation du Workspace.
- **Ctrl+Z annule toute l'installation d'un coup.**
- Il refuse de tourner une 2e fois, pour ne pas écraser la copie de secours.
- Il ne publie rien : teste, puis publie toi-même.

---

## 🖐️ INSTALLATION MANUELLE (si tu préfères, ou pour un script signalé ⚠️)
« Remplacer » = ouvrir le script, **Ctrl+A**, supprimer, coller le contenu du fichier. Ne change ni le nom ni la place.
Extension des fichiers : `.server.lua` = Script · `.client.lua` = LocalScript · `.module.lua` = ModuleScript.

**A. Créer 5 objets**

| Où | Type | Nom exact | Fichier |
|---|---|---|---|
| ReplicatedStorage | ModuleScript | `PopupControlConfig` | `ReplicatedStorage/PopupControlConfig.module.lua` |
| ReplicatedStorage | ModuleScript | `PopupGate` | `ReplicatedStorage/PopupGate.module.lua` |
| ReplicatedStorage | ModuleScript | `LeaderboardStyle` | `ReplicatedStorage/LeaderboardStyle.module.lua` |
| ServerScriptService | Script | `PopupControl_Server` | `ServerScriptService/PopupControl_Server.server.lua` |
| StarterPlayer ▸ StarterPlayerScripts | LocalScript | `ArenaViewKeeper` | `StarterPlayer/StarterPlayerScripts/ArenaViewKeeper.client.lua` |

**B. Remplacer le code de 28 scripts** (le fichier a le même nom, dans le même dossier)

| Dans Studio | Scripts |
|---|---|
| ServerScriptService | `checkpoints system` · `anti fly/tp server` (fichier : `anti fly-tp server`) · `PLAYER UGC STATS` · `new donation board server` · `notif chat ` (espace à la fin) · `DAILY TOOLs` · `10 died = offer 2500 points` · `time` · `STATS` · `ask favorite game` · `datastore alr ask favorite game` · `leave popup` · `server referal friend invite` |
| ServerStorage ▸ `AdminClientScripts.` | `Admin client` |
| ReplicatedStorage | `LeaderboardCore` · `WeaponSystem` ▸ `WeaponController` |
| StarterGui | `ShiftLockButton` ▸ `ImageButton` ▸ `ShiftGUI` · `VIP offer` ▸ `make pop th add` · `UGCshop` ▸ `ShopFrame` ▸ ` UGC SHOP GENERATOR` (espace au début) |
| StarterPlayer ▸ StarterPlayerScripts | `offers on screen` · `script proposer achat skip obby` · `EngageTrack` · `rebirth offer notify event` · `fenetre dachat gravity coil` · `Fenetre dachat fusion coil` · `Fenetre achat speedcoil` · `achat x2coin` |
| StarterPlayer ▸ StarterCharacterScripts | `ask favorite game` |

**C. Supprimer** : StarterPlayer ▸ StarterPlayerScripts ▸ `daily notification`.

---

## 📋 CE QUI CHANGE, CONCRÈTEMENT

### 1. Reload AFK
- **Avant :**
  - un joueur sans checkpoint sauvegardé revenait au **spawn** après le reload ;
  - un joueur AFK en l'air, sur une plateforme mobile ou dans la cachette était replacé tel quel (dans le vide, etc.).
- **Maintenant :**
  - il revient **exactement à sa place**, checkpoint ou pas ;
  - s'il n'était pas posé sur un décor fixe, il revient sur son checkpoint.
- **Anticheat :** le reload était déjà protégé contre les faux « TP ». Si un signal arrivait quand même juste après, la fiche admin affiche « 💤 Arrivé par reload AFK il y a X s ».

### 2. Fiche joueur dans l'admin
- **Badges :** 🛡️ ADMIN · 👑 VIP · ⚡ x2 / x5 / x10 PERM (acheté **ou** offert), ou « Aucun VIP / boost perm ».
- **Dernière connexion :** « il y a 3 j 5 h », « il y a 4 h 12 min ». Plus jamais une date.
- **Cause corrigée :** pour les anciens joueurs ajoutés par le rattrapage, un drapeau restait collé pour toujours et forçait l'affichage d'une date.

### 3. Dons
- **Avant :** l'effet et le son du board ne jouaient que sur le serveur du don. Les autres boards se mettaient à jour toutes les 10 min.
- **Maintenant :** effet + son sur **tous les serveurs**, et classement à jour **tout de suite** partout.

### 4. Curseur PvP mobile
- Minimum **40 px** sur téléphone (avant 26 px). Tablette, PC et console : pareil qu'avant.

### 5. Ton bouton lock (mobile)
- **Avant :** il se désactivait à chaque mort.
- **Maintenant :** il **reste activé** toute la session. En arène, il laisse la place à la vue PvP (point 11) puis revient à la sortie.

### 6. Chat des achats de points
- « Pseudo bought 100,000 Points! », **sans** le prix en Robux.

### 7. Popups
- **Notif de récompense quotidienne : retirée.**
- **Demande de favori :**
  - 1re fois quand le joueur atteint le checkpoint 4 (ou plus loin) ;
  - s'il refuse, plus rien pendant sa session. Redemandée dans une prochaine session, 2 jours après au minimum, puis 4 j, puis 8 j ;
  - seulement après 10 min de jeu, juste après une progression, jamais en arène, 4 fois maximum ;
  - s'il accepte : plus jamais.
- **Admin ▸ 🔔 POPUPS (nouvelle section)**, pour chaque popup automatique :
  - popups concernés : VIP · Pass Skip Obby · carrousel d'offres · offre après des morts · points manquants pour une UGC · pads d'achat · rappel d'event · favori ;
  - ON/OFF et fréquence ;
  - mode « seulement si le joueur est inactif depuis X min » ;
  - pause minimum entre deux popups ;
  - bouton « Remettre les réglages d'origine ».
  - Par défaut, tout marche **exactement comme avant**. Les changements s'appliquent à tous les serveurs en quelques secondes.
- **Admin ▸ 📊 STATS ▸ Popups :** une fiche claire par popup (affichages, joueurs, fenêtres d'achat, achats, %, Robux), avec une phrase qui explique à quoi il sert.
- **6 erreurs de stats corrigées :**
  1. seulement 3 popups sur 9 étaient comptés ;
  2. un clic dans le shop volait l'achat d'un popup automatique ;
  3. les packs du shop étaient comptés comme « offre de morts » ;
  4. le popup VIP était compté 2 fois ;
  5. « joueurs / jour » était sous-estimé ;
  6. les titres avec des fréquences écrites en dur ont été renommés, et l'historique reste regroupé.
- **Sécurité :** un tricheur pouvait vider le budget DataStore du serveur avec le script de favori. C'est bloqué.
- **Bug corrigé :** l'offre après des morts ne comptait jamais les morts de la toute première vie.

### 8. Leaderboards
- **Nouveau look** comme les Paramètres et le CombatHUD : panneau sombre, police BuilderSans, boutons 3D. La couleur de chaque board est gardée.
- **Nouveaux boutons :**
  - **ALL / FRIENDS** : toi et tes amis, avec leur vraie place ;
  - **🔍 FIND ME** : défile jusqu'à toi et te fait clignoter.
- **En bas du board :** ta ligne (« #12 YOU · 1.2M » ou « not in the top 100 yet ») et une barre **NEXT UPDATE**.
- Le bouton DONATE du board de dons marche toujours.
- **Revenir à l'ancien look :** dans `ReplicatedStorage ▸ LeaderboardStyle`, mets `Style = "classic"`.

### 9. Shop UGC : bouton FILTER (nouveau)
- **Bouton FILTER ▼** en haut à droite de la grille, à droite de « NEW FREE UGC Weekly! », dans le style de la fenêtre (fond sombre, bord bleu clair).
- **Le panneau qui s'ouvre**, avec des cases à cocher :
  - **AVAILABILITY :** Available · Sold out · Low stock (30 % du stock ou moins) ;
  - **OWNERSHIP :** Owned · Not owned (vérifié sur l'inventaire Roblox du joueur, une fois) ;
  - **TYPE :** Hat · Hair · Face · Neck · Shoulder · Front · Back · Waist · Clothing · Shoes… (seulement les types présents dans ton shop) ;
  - **OTHER :** NEW only.
- **SORT BY (un seul choix) :** Shop order · Price high→low · Price low→high · Total stock most→least · Total stock least→most.
- **Boutons :** **APPLY** applique · **CANCEL** ferme sans rien changer · **RESET** efface tout.
- **Filtres actifs bien visibles :**
  - le bouton devient **FILTER (3)** avec un bord jaune ;
  - une rangée de pastilles apparaît au-dessus de la grille. Chaque **X** retire un filtre, **RESET ALL** efface tout.
- Si rien ne correspond : « No UGC match your filters » + bouton **RESET FILTERS**.
- Dans un même groupe, les cases s'additionnent (Hat **ou** Hair). Les groupes se combinent (Available **et** Hat).
- **Performance :** tout se fait chez le joueur. Aucun appel au serveur du jeu, aucun DataStore.

### 10. Invitations d'amis
- **Avant :**
  - deux amis pouvaient s'inviter l'un l'autre à des jours différents (12 000 pts pour les mêmes amis) ;
  - on pouvait « inviter » quelqu'un qui jouait déjà.
- **Maintenant :** ça ne paie que si l'invité **découvre le jeu** (moins de 10 min de jeu, 1re arrivée il y a moins de 30 min). Sinon personne n'est payé, et le parrain voit « Friend Already Played ».

### 11. Vue PvP sans arme (nouveau script `ArenaViewKeeper`)
- **Avant :** en arène, en vue lock, ranger son arme rendait la caméra libre, et B ne faisait rien sans arme.
- **Maintenant, sans arme en arène :**
  - la vue reste **la même qu'avec une arme**. En lock : caméra derrière l'épaule, souris bloquée au centre, perso tourné vers la caméra. En 1re personne : reste en 1re personne ;
  - **B** (manette : croix ←) **change la vue** ;
  - le **panneau des contrôles** reste affiché au même endroit que celui des armes : **B Views** · **H Hide Controls**. H cache ou réaffiche les contrôles.
- **En ressortant une arme :** elle reprend la caméra exactement où tu regardais, sans saut.
- **Hors arène :** rien ne change.
- **Revenir à avant :** dans `ArenaViewKeeper`, mets `ENABLED = false` (ligne 21), ou supprime le script.

---

## ✅ Vérifié de mon côté
- Les 34 fichiers (33 scripts + l'installateur) passent un analyseur de syntaxe Luau. Ce même analyseur valide les 669 scripts d'origine sans erreur.
- Aucune fonction ni variable de niveau principal n'a disparu par erreur (comparaison avec les originaux).
- Recherche de variables non déclarées.
- `time` reste à 199 variables locales de niveau principal (limite 200).
- Le modèle `.rbxmx` contient exactement le même code que les fichiers (vérifié octet par octet).
- Les 28 scripts à remplacer existent bien dans ton jeu, chacun sous un nom unique (vérifié sur ton fichier .rbxl).

## 🧪 À tester dans Studio avant de publier (je ne peux pas lancer le jeu)
1. **Leaderboards :** rendu, ALL / FRIENDS / FIND ME, bouton DONATE.
2. **Shop UGC :** FILTER, cocher, APPLY, pastilles, X, RESET ALL, et « aucun résultat ». Teste aussi en émulation mobile.
3. **Arène :** sans arme, B change la vue et le panneau B/H est visible. Ressors une arme : aucun saut. Sors de l'arène : caméra normale.
4. **Admin :** section 🔔 POPUPS (change un réglage, rouvre le panel) et fiche joueur (badges, « il y a X j Y h »).
5. **Mobile :** le lock reste activé après la mort, et le curseur PvP est plus gros.
6. **Sur un vrai serveur publié** (impossible à tester en Studio) :
   - un don → effet sur un 2e serveur ;
   - un reload AFK → retour à la bonne place ;
   - un réglage popup → appliqué sur les autres serveurs.
