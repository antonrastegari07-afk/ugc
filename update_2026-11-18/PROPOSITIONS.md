# Propositions (rien n'est codé) — à choisir

## A. Réorganiser l'admin panel — SANS RIEN RETIRER

Règle : **toutes les sections et tous les boutons d'aujourd'hui restent**, avec les mêmes fonctions.
On change seulement **où** ils se trouvent et **comment on y arrive**.

### A1. Accueil en 5 onglets (au lieu d'une grille d'environ 30 boutons à plat)
Chaque bouton actuel est rangé dans un onglet. Aucun ne disparaît :

| Onglet | Boutons actuels qui y vont |
|---|---|
| 👥 **Joueurs** | 🔨 BAN · ✅ UNBAN · 👟 KICK · 🧊 FREEZE · 🚀 GO TO · 🧲 BRING · 🔄 RESET · 👁️ SPECTATE · ✈️ FLY · 🎁 GIVE · 📍 TP CP · 👤 PROFILE · 🚫 BANS · 👑 VIP |
| 🎽 **UGC & boutique** | 🎽 UGC LOG · 🔐 ESCROW (avec 📦 Réglages du stock et ↕️ Ordre du shop, comme aujourd'hui) · 🛑 VENTES UGC · 🎁 GIFT LOG · 🛑 GIFT KILL SWITCH |
| 🛡️ **Sécurité** | 🚨 A-CHEAT (l'écran unique actuel, qui contient déjà 🚫 UGC BAN et ⚙️ MODES & MSG) |
| 🎉 **Jeu & events** | 🔔 WHAT'S NEW · 🎪 Admin Abuse · 🔔 POPUPS · 🏆 BOARDS · 💬 FEEDBACK |
| 📊 **Chiffres** | 📊 STATS · 💸 REVENUS · 🎽 UGC STATS |

### A2. Raccourcis en plus (ils ne remplacent rien)
- **Fiche joueur :** sur 👤 PROFILE et MANAGE PLAYER, des boutons ouvrent directement les sections existantes **pour ce joueur** : ban, kick, freeze, give, VIP, boost, privation UGC, ses gifts, ses UGC, son dossier anti-cheat. Les boutons de l'accueil restent aussi.
- **Page 🚨 URGENCES :** une page avec des **liens** vers les interrupteurs d'arrêt existants (couper les cadeaux, geler les ventes UGC, cacher une UGC, couper les popups, arrêter un Admin Abuse). Les interrupteurs restent aussi à leur place actuelle.
- **Recherche sur l'accueil :** taper « vip » ou « stock » ouvre la bonne section.
- **Favoris :** épingler tes sections les plus utilisées en haut de l'accueil.
- **Pastilles :** nombre de feedbacks non lus, escrow en attente, nouveaux signalements anti-cheat.

### A3. Technique (invisible pour toi)
Découper le gros script (25 000 lignes, à la limite des 200 variables de Luau) en ModuleScripts, un par section, sans rien changer à l'écran. Ça évite des bugs à chaque ajout.

👉 Recommandation : **A1 + les raccourcis « fiche joueur » et « URGENCES »**. Dis-moi si tu veux déplacer un bouton dans un autre onglet.

---

## B. Shop UGC — bouton de TRI / FILTRE

**C'est possible, entièrement côté joueur.** Pas de changement serveur, pas de DataStore. Trier ou filtrer environ 80 UGC est instantané. Toutes les infos existent déjà : prix, stock en direct, NEW, likes, ordre de l'admin, points du joueur.

### Le bouton
- Placé **à droite de « NEW FREE UGC Weekly! »**, en haut à droite de la grille.
- Même style que la fenêtre : fond noir, bord bleu clair arrondi, texte blanc Fredoka.
- Texte : **« ⏷ FILTER »**. Avec des filtres actifs : **« ⏷ FILTER (3) »**, bord jaune.
- Un clic déroule un **petit panneau** sous le bouton. Il ne cache pas toute la fenêtre.

### Le panneau
- Des sections avec **cases à cocher** pour les filtres et **un seul choix** pour le tri.
- En bas, trois boutons : **APPLY** (vert) · **CANCEL** (gris, ferme sans changer) · **RESET** (rouge, tout effacer).

### Voir clairement les filtres actifs
- Une **ligne de pastilles** apparaît sous l'en-tête, par exemple : `Available ✕` `Can buy now ✕` `Price ↑ ✕` … puis `RESET ALL`.
- Chaque ✕ retire **un seul** filtre. `RESET ALL` remet tout comme à l'ouverture.
- Si plus rien ne correspond : « No UGC match your filters » + un bouton RESET.

### Options de FILTRE possibles (choisis celles que tu veux)
| Groupe | Options |
|---|---|
| 📦 **Disponibilité** | Available (en stock) · Sold out · Low stock (≤ X restants, X réglable) · Coming soon |
| 🪙 **Mes points** | Je peux l'acheter maintenant · Presque (≥ 75 % du prix) · Trop cher pour l'instant |
| 💰 **Prix** | Moins de 500k · 500k – 2M · 2M – 5M · Plus de 5M (tranches modifiables) |
| 🆕 **Nouveauté** | NEW seulement |
| ❤️ **Social** | Mes likes · Les plus aimés (top 10) |
| 🎒 **À moi** | Pas encore dans mon inventaire Roblox · Déjà dans mon inventaire |
| 👒 **Type d'accessoire** | Chapeau · Cheveux · Visage · Cou · Épaules · Devant · Dos · Taille (lu sur Roblox une fois par item, gardé en mémoire) |

### Options de TRI possibles (une seule à la fois)
- Ordre du shop (celui de l'admin, par défaut)
- Prix croissant · Prix décroissant
- Le plus proche de mes points (ce qui me manque le moins d'abord)
- Stock restant croissant (les plus rares d'abord) · décroissant
- Les plus aimés
- Les plus récents (NEW d'abord)
- Nom A → Z

### Petits plus possibles
- Le choix reste **pendant toute la session** (fermer et rouvrir le shop le garde).
- Le compteur « X UGC shown » à côté des pastilles.
- Sur mobile, le panneau prend la largeur de la grille, avec de grosses cases.

👉 Dis-moi quelles options garder, et je le code.
