# Propositions (rien n'est codé) — à choisir

## A. Réorganiser l'admin panel

**Ce que j'ai constaté** dans `Admin client` :
- 25 472 lignes, et une trentaine de boutons à plat sur l'accueil. Les 17 boutons de base (BAN, KICK, GO TO…) sont mélangés aux 13 sections ajoutées ensuite (BANS, GIFT LOG, VENTES UGC, VIP, STATS, REVENUS…).
- Plusieurs sections font la même chose sous un autre nom : `🚫 BAN` vs `🚫 BANS`, `🎽 UGC STATS` vs `📊 STATS` vs `💸 REVENUS`.
- Chaque bloc a recopié ses propres boutons ON/OFF et « − valeur + » (6 copies différentes). D'où des styles un peu différents d'une page à l'autre.
- Le fichier est à la limite des 200 variables de Luau. Chaque ajout devient délicat.

**Choix possibles (combinables)**

1. **Accueil en 5 onglets** au lieu d'une grille unique :
   - 👥 **Joueurs** : chercher, profil, ban/kick/freeze/give/TP, VIP, boosts.
   - 🎽 **UGC & boutique** : UGC log, escrow, stock, ordre du shop, ventes UGC.
   - 🛡️ **Sécurité** : anti-cheat, bans, gift log.
   - 🎉 **Jeu & events** : What's New, Admin Abuse, popups, boards, feedback.
   - 📊 **Chiffres** : stats, revenus, UGC stats.
2. **Une fiche joueur unique.** On cherche un joueur une fois, puis toutes les actions sont sur sa fiche : ban, kick, freeze, give, VIP, boost, privation UGC, ses gifts, ses UGC, son dossier anti-cheat. Plus besoin de retaper le pseudo dans chaque section.
3. **Page 🚨 URGENCES** qui regroupe tous les interrupteurs d'arrêt : couper les cadeaux, geler les ventes UGC, cacher une UGC, couper tous les popups, arrêter un Admin Abuse.
4. **Barre de recherche + favoris** sur l'accueil : taper « vip » ouvre la bonne page, et tu épingles tes 4 sections les plus utilisées en haut.
5. **Pastilles de notification** sur les boutons : feedbacks non lus, escrow en attente, nouveaux signalements anti-cheat.
6. **Fusionner les stats** en une seule section « 📊 Chiffres » avec 4 onglets : Joueurs · UGC · Achats & popups · Revenus.
7. **Technique (invisible pour toi, mais ça évite les bugs).** Découper le gros script en ModuleScripts : un par section, plus un « kit UI » commun pour les boutons et réglages. Ça règle la limite des 200 variables et donne le même style partout.

👉 Ma recommandation : **1 + 2 + 3**. Ça change le plus le quotidien. Le 7 peut se faire en même temps, sans rien changer à ce que tu vois.

---

## B. Améliorer le shop UGC (d'après ta capture)

**Ce que la capture montre**
- Les 9 cartes ont toutes « NEW » + « LIMITED ». Quand tout est « nouveau », le badge ne veut plus rien dire.
- Aucune carte n'affiche son **prix** ni son **stock**. Il faut cliquer chaque item pour savoir s'il est accessible.
- Le panneau de droite (≈ 40 % de la fenêtre) est vide : « Select a UGC! » + un bouton « ??? pts ».
- « NEW FREE UGC Weekly! » est un petit texte fixe, sans date.

**Choix possibles (combinables)**

1. **Prix + progression sur chaque carte** : « 12 500 pts », une barre « tu as 64 % » et « ≈ 2 h de jeu » (calculé avec ton rythme de points). Le joueur voit tout de suite ce qu'il peut viser.
2. **Plus de panneau vide.** À l'ouverture, l'UGC la plus proche d'être gagnée est déjà sélectionnée. À la place de « ??? pts » : « Il te manque 4 500 pts → GAGNER DES POINTS ». Ce bouton ouvre les quêtes / l'obby.
3. **Badges utiles seulement** :
   - NEW seulement les 7 premiers jours ;
   - LIMITED en petite icône ;
   - nouveau badge « 🔥 ALMOST YOURS » quand le joueur est à plus de 80 % ;
   - « ⚠️ 5 LEFT » quand le stock est bas.
4. **Filtres en haut** : Tout · Je peux l'avoir · Presque · Nouveau · Bientôt épuisé.
5. **Essayage 3D** dans le panneau de droite : ton avatar porte l'item et tourne. Marche avec n'importe quel item du catalogue.
6. **Compte à rebours de la prochaine UGC gratuite** à la place du texte fixe : « Next FREE UGC in 2d 4h ». Ça donne une raison de revenir.
7. **Preuve sociale** : petite ligne qui défile, « Alex claimed Santa Hair 3 min ago » (le flux existe déjà côté serveur).
8. **Mobile** : 2 colonnes et cartes plus grosses ; le panneau de droite devient un volet qui monte du bas.

👉 Ma recommandation : **1 + 2 + 3**, c'est le plus rentable : le joueur comprend en 2 secondes ce qu'il peut gagner et comment. Puis **5** pour l'effet « wow ».
