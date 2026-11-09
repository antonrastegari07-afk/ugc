# Installation v7 (sur la base de ta version 7.0)

Chaque fichier REMPLACE TOUT le contenu du script indiqué (Ctrl+A dans le script, puis coller).
Clique bien DANS le code avant de coller (sinon Studio dit « Clipboard text isn't JSON »).

| # | Où | Script | Type |
|---|----|--------|------|
| 1 | ServerScriptService | **PLAYER UGC STATS** (à CRÉER) | Script |
| 2 | ServerScriptService | ugc redeems admin log | Script |
| 3 | ServerStorage › AdminClientScripts | Admin client | LocalScript |
| 4 | ServerScriptService | flame arrow obby | Script |
| 5 | StarterPlayer › StarterPlayerScripts | flame arrow obby | LocalScript |
| 6 | ReplicatedStorage › WeaponSystem | WeaponMechanics | ModuleScript |
| 7 | ReplicatedStorage › WeaponSystem | WeaponSharedState | ModuleScript |
| 8 | ServerScriptService | AntiCheat_UGCRestrict | Script |
| 9 | StarterPlayer › StarterPlayerScripts | SettingsUI | LocalScript |
| 10 | ServerScriptService | checkpoints system | Script |
| 11 | ServerScriptService | system ancer reculer level | Script |
| 12 | StarterPlayer › StarterPlayerScripts | system navigation +1 level -1 level | LocalScript |
| 13 | ReplicatedStorage › WeaponSystem | WeaponController | ModuleScript |
| 14 | StarterPlayer › StarterPlayerScripts | WeaponDeathCleanup | LocalScript |
| 15 | ServerScriptService | time | Script |
| 16 | StarterGui › 1v1button › Frame › TextButton | bouton enter 1v1 | LocalScript |
| 17 | ReplicatedStorage › WeaponSystem | CombatSettings | ModuleScript |
| 18 | ServerScriptService | cross-server 1v1 | Script |
| 19 | StarterPlayer › StarterPlayerScripts | 1v1 cross server local | LocalScript |
| 20 | ServerScriptService › CombatSystem | CombatServer | Script |
| 21 | StarterPlayer › StarterPlayerScripts | PVPmapvoting | LocalScript |
| 22 | ServerScriptService | securité suplementaire ban | Script |
| 23 | ServerScriptService | stock restant | Script |

Ensuite : Publish, puis « Shut down all servers ».

Ce que ça change :
- 1, 2, 3 : onglet 📊 STATS ▸ 🎽 Joueurs & UGC (sans UGC, 1/2/3…, VIP / boosts, VIP + x2,
  temps pour avoir une UGC, UGC avant d'arrêter de jouer), 💸 Achats & pubs refait plus visuel,
  dernière connexion (🟢 / 🕒) sur les entrées des joueurs et dans Manage Player.
- 4, 5 : flèches de feu du niveau 93 (arrowzone1) plus lentes (70 → 42). Attribut « ArrowSpeed »
  sur la Part de la zone pour régler en direct.
- 6 : manette : L3 = sprint activé pour de bon, 2e appui = arrêt (GamepadToggle = false pour l'ancien maintien).
- 7 : console (Xbox / PlayStation) : 3e personne avec lock par défaut.
- 8 : anti-cheat : « 🟢 Activer les sanctions » (et toute case qu'on COUPE dans les réglages) ne faisait rien — corrigé.
- 9 (+ 4, 5) : flèches de feu invisibles en mode performance (« particules » coupées) — les effets de gameplay marqués KeepFX ne sont plus jamais coupés.
- 10, 11, 12 : flèche -1 qui refusait de descendre après un join sur un checkpoint > 1 (Stage restait à 1) — corrigé. ET faille fermée : le serveur acceptait n'importe quel numéro de niveau (sauter tout l'obby) ; il part maintenant du checkpoint actuel et refuse tout ce qui dépasse le plus haut checkpoint atteint.
- 9 (mise à jour) : Auto Performance marche dans les deux sens (baisse si FPS < 22, remonte quand les FPS sont bons 60 s, sans va-et-vient).
- 13, 14 : mode lock PvP — plus de vue bloquée avec curseur libre après la mort, perso qui ne tourne plus contre un mur, caméra sans allocation par image, « Mode » → « Views ».
- 7, 13, 15 : la vue PvP (B / VIEW) est mémorisée par appareil ; curseur = ton image partout (1re personne, lock, mobile, manette), rouge sur un ennemi ; ancien viseur en lignes retiré.
- 16, 17 : bouton Exit de l'arène — touche L (PC) / flèche droite (manette) affichée à la place du ✖ et utilisable ; changement de vue manette déplacé sur la flèche gauche.
- 18, 19 : liste des serveurs 1v1 (perf : 3× moins de données envoyées au joueur, aucune reconstruction si rien n'a changé) — les serveurs ajoutés avec « Load More » disparaissaient à chaque actualisation (10 s) ; les nombres de joueurs sont publiés dès qu'ils changent (plus de retard de 10 à 20 s) ; un échec MemoryStore ne fait plus disparaître un serveur ; jusqu'à 200 serveurs listés.
- 20, 21 : écran ROUND WINNER — le perso tient son arme avec la vraie pose de ton système d'armes (les deux bras, mêmes welds qu'en jeu) Animation de victoire : chute sur le podium, arme levée au ciel + poing gauche, puis immobile (réglages : table VICTORY). Caméra : 4 plans qui s'enchaînent en boucle (réglages : table SHOTS).
- 15, 22 : FAUX BANS des nouveaux joueurs — SmartAntiCheat bannissait sur UNE seule analyse (« maximum » minuscule pour un nouveau joueur) et ignorait le mode du panel. Maintenant : 2 analyses séparées obligatoires, tous les gains crédités par le serveur sont déduits ; sanction = mode du panel (shadow : rien · privation d'UGC : privation) ; en mode ban, un joueur de moins de 3 jours est privé d'UGC (réversible) au lieu d'être banni — il reste surveillé et ne peut pas encaisser d'UGC. Cap absolu : même logique, et le bonus d'un code / cadeau reçu pendant le chargement n'est plus effacé.
- Halloween : voir HALLOWEEN_RANGEMENT.md (aucun script à remplacer).
- 23 : shop UGC — faux « out of stock » et « 429 trop de requêtes » : 1 seule requête groupée pour tous les UGC (au lieu de 81), partagée entre les serveurs ; en repli, le dernier stock RÉEL connu est affiché (plus le vieux compteur maison à 0) ; 2 relectures après achat au lieu de 4. Si le relais refuse la lecture groupée, retour automatique à l'ancienne méthode.
- 22 (revue) : cap absolu — un échec de vérification de gamepass ne baisse plus le multiplicateur (pass vu possédé = gardé, vérification sautée si impossible) ; ancien joueur dont la fiche cap est perdue : le temps de jeu réel sert de plancher ; bonus des codes / cadeaux / admin persisté avec relances ; produit AdReward ajouté.
- 23 (mise à jour) : le stock est lu d'abord par le MOTEUR Roblox (GetProductInfo) : aucun relais, aucun 429 de Cloudflare. Le relais HTTP ne sert plus qu'en secours. Test : _G.UGCStock_TestEngine() dans la barre de commande.
- 23 (mise à jour 2) : secours HTTP = ta lecture un par un d'avant (celle qui marchait à ~70 %), mais ÉTALÉE sur toute la période de sondage (1 requête / ~7 s au lieu de 81 en 25 s) ; la lecture groupée POST n'est plus utilisée.
