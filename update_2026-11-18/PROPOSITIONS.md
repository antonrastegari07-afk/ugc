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
✅ **Codé** avec les options choisies : Available · Sold out · Low stock · Owned / Not owned · Type d'accessoire · NEW · prix ↑ / ↓ · stock total ↑ / ↓. Voir le README, point 9.
