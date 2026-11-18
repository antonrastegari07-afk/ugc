# Mise à jour du 18/11/2026 — guide d'installation

Tous les scripts sont rangés **exactement comme dans Roblox Studio** (même dossier, même nom).
L'extension indique le type d'objet :

| Extension | Objet Studio |
|---|---|
| `.server.lua` | **Script** |
| `.client.lua` | **LocalScript** |
| `.module.lua` | **ModuleScript** |

« Remplacer » veut dire : ouvrir le script dans Studio, **tout sélectionner (Ctrl+A), supprimer, coller le contenu du fichier**.
Ne change ni le nom ni l'emplacement du script.

> ⚠️ Installe **tout** avant de publier. Plusieurs scripts dépendent des nouveaux modules
> (`PopupControlConfig`, `PopupGate`, `LeaderboardStyle`) : s'ils manquent, ces scripts attendent indéfiniment.

---

## Étape 1 — Créer les 5 nouveaux objets

| Où dans Studio | Créer | Nom exact | Fichier |
|---|---|---|---|
| ReplicatedStorage | ModuleScript | `PopupControlConfig` | `ReplicatedStorage/PopupControlConfig.module.lua` |
| ReplicatedStorage | ModuleScript | `PopupGate` | `ReplicatedStorage/PopupGate.module.lua` |
| ReplicatedStorage | ModuleScript | `LeaderboardStyle` | `ReplicatedStorage/LeaderboardStyle.module.lua` |
| ServerScriptService | Script | `PopupControl_Server` | `ServerScriptService/PopupControl_Server.server.lua` |
| StarterPlayer ▸ StarterPlayerScripts | LocalScript | `ArenaViewKeeper` | `StarterPlayer/StarterPlayerScripts/ArenaViewKeeper.client.lua` |

## Étape 2 — Remplacer le code de ces 27 scripts

### ServerScriptService (Scripts)
| Script dans Studio | Fichier | Point |
|---|---|---|
| `checkpoints system` | `ServerScriptService/checkpoints system.server.lua` | 1 |
| `anti fly/tp server` | `ServerScriptService/anti fly-tp server.server.lua` *(le « / » du nom Studio est remplacé par « - » dans le fichier)* | 1 |
| `PLAYER UGC STATS` | `ServerScriptService/PLAYER UGC STATS.server.lua` | 2 |
| `new donation board server` | `ServerScriptService/new donation board server.server.lua` | 3 |
| `notif chat ` *(avec l'espace à la fin)* | `ServerScriptService/notif chat .server.lua` | 6 |
| `DAILY TOOLs` | `ServerScriptService/DAILY TOOLs.server.lua` | 7 |
| `10 died = offer 2500 points` | `ServerScriptService/10 died = offer 2500 points.server.lua` | 7 |
| `time` | `ServerScriptService/time.server.lua` | 7 |
| `STATS` | `ServerScriptService/STATS.server.lua` | 7 |
| `ask favorite game` *(le Script)* | `ServerScriptService/ask favorite game.server.lua` | 7 |
| `datastore alr ask favorite game` | `ServerScriptService/datastore alr ask favorite game.server.lua` | 7 |
| `leave popup` *(le Script)* | `ServerScriptService/leave popup.server.lua` | 7 |
| `server referal friend invite` | `ServerScriptService/server referal friend invite.server.lua` | 10 |

### ServerStorage
| Script dans Studio | Fichier | Points |
|---|---|---|
| `AdminClientScripts` ▸ `Admin client` (LocalScript) | `ServerStorage/AdminClientScripts/Admin client.client.lua` | 2, 7 |

### ReplicatedStorage (ModuleScripts)
| Script dans Studio | Fichier | Point |
|---|---|---|
| `LeaderboardCore` | `ReplicatedStorage/LeaderboardCore.module.lua` | 8 |
| `WeaponSystem` ▸ `WeaponController` | `ReplicatedStorage/WeaponSystem/WeaponController.module.lua` | 4 |

### StarterGui (LocalScripts)
| Script dans Studio | Fichier | Point |
|---|---|---|
| `ShiftLockButton` ▸ `ImageButton` ▸ `ShiftGUI` | `StarterGui/ShiftLockButton/ImageButton/ShiftGUI.client.lua` | 5, vue PvP |
| `VIP offer` ▸ `make pop th add` | `StarterGui/VIP offer/make pop th add.client.lua` | 7 |

### StarterPlayer ▸ StarterPlayerScripts (LocalScripts)
| Script dans Studio | Fichier | Points |
|---|---|---|
| `offers on screen` | `StarterPlayer/StarterPlayerScripts/offers on screen.client.lua` | 7, 10 |
| `script proposer achat skip obby` | `StarterPlayer/StarterPlayerScripts/script proposer achat skip obby.client.lua` | 7 |
| `EngageTrack` | `StarterPlayer/StarterPlayerScripts/EngageTrack.client.lua` | 7 |
| `rebirth offer notify event` | `StarterPlayer/StarterPlayerScripts/rebirth offer notify event.client.lua` | 7 |
| `fenetre dachat gravity coil` | `StarterPlayer/StarterPlayerScripts/fenetre dachat gravity coil.client.lua` | 7 |
| `Fenetre dachat fusion coil` | `StarterPlayer/StarterPlayerScripts/Fenetre dachat fusion coil.client.lua` | 7 |
| `Fenetre achat speedcoil` | `StarterPlayer/StarterPlayerScripts/Fenetre achat speedcoil.client.lua` | 7 |
| `achat x2coin` | `StarterPlayer/StarterPlayerScripts/achat x2coin.client.lua` | 7 |

### StarterPlayer ▸ StarterCharacterScripts (LocalScript)
| Script dans Studio | Fichier | Point |
|---|---|---|
| `ask favorite game` | `StarterPlayer/StarterCharacterScripts/ask favorite game.client.lua` | 7 |

## Étape 3 — Supprimer 1 script

| Où | Supprimer | Pourquoi |
|---|---|---|
| StarterPlayer ▸ StarterPlayerScripts | LocalScript `daily notification` | La notif de récompense quotidienne est retirée. Le serveur (`DAILY TOOLs`) ne l'envoie plus. |

**Rien d'autre à changer dans Studio.** Pas de propriété à modifier : le bouton lock passe lui-même
son ScreenGui en `ResetOnSpawn = false` au lancement.

---

## Ce que fait chaque point

### 1. Reload AFK → warnings TP
- Le retour d'AFK était déjà protégé contre les faux « TP ».
- **Nouveau :** la position n'est sauvegardée que si le joueur est **posé sur un décor fixe**. Les autres cas sont refusés : en l'air, jetpack, tyrolienne, plateforme mobile, cachette secrète, ragdoll. Le joueur revient alors sur son checkpoint, comme avant.
- **Corrigé :** un joueur **sans checkpoint sauvegardé** revenait au spawn au lieu de sa place.
- **Vérification :** si l'anticheat détectait quoi que ce soit après un reload, la fiche admin affiche « 💤 Arrivé par reload AFK il y a X s ». Elle indique aussi la grâce « afk_reload » (8 s).

### 2. Profil admin
- La fiche **MANAGE PLAYER** affiche des badges : 🛡️ ADMIN · 👑 VIP · ⚡ x2 / x5 / x10 PERM (achetés **ou** offerts), ou « Aucun VIP / boost perm ».
- « En ligne il y a » : **« il y a 3 j 5 h »**, « il y a 4 h 12 min ». Plus jamais une date.
- **Vraie cause corrigée :** les anciens joueurs ajoutés par le « rattrapage » gardaient pour toujours un drapeau qui forçait l'affichage d'une date, même après être revenus jouer.
- Les heures de départ ne sont plus perdues quand un serveur ferme.

### 3. Dons : effet + son sur tous les serveurs
- Chaque don déclenche l'effet et le son du board sur **tous** les serveurs, et met leur classement à jour **tout de suite** (avant : toutes les 10 min).
- Une rafale de dons ne relance pas l'effet plus d'une fois toutes les 3 s.
- Coût : 1 message par don, aucune requête DataStore en plus.

### 4. Curseur PvP mobile
- Minimum **40 px** sur téléphone (avant : 26 px). Tablette, PC et console inchangés.
- Réglable : `WeaponController` ▸ `Cursor.ImageMin`.

### 5. Ton bouton lock (mobile)
- L'état ON/OFF est **gardé après la mort** toute la session.
- En arène PvP, il se met en pause (la caméra des armes gère tout) et revient tout seul à la sortie.

### 6. Achats de points
- Le chat dit **« Pseudo bought 100,000 Points! »**, sans le prix en Robux.

### 7. Popups
- **Notif de récompense quotidienne : retirée.** Bonus : 1 lecture DataStore de moins par joueur.
- **Favori intelligent :**
  - 1re demande quand le joueur **atteint** le checkpoint 4 (ou plus loin).
  - S'il refuse : plus rien pendant la session. Redemandé dans une prochaine session, au moins 2 jours plus tard, puis 4 j, puis 8 j. Seulement après 10 min de jeu, juste après une progression, et jamais en arène. 4 fois maximum.
  - S'il accepte : plus jamais.
  - Tout est réglable dans l'admin.
- **Admin ▸ 🔔 POPUPS (nouveau)** : chaque popup automatique s'active, se désactive et se règle (fréquence, délais, nombre de morts…). Les changements s'appliquent à tous les serveurs en quelques secondes.
  - Popups concernés : VIP · Pass Skip Obby · carrousel d'offres · offre après des morts · points manquants pour une UGC · pads d'achat (coils, x2) · rappel d'event · favori.
  - Mode **« seulement si le joueur est inactif depuis X min »** (5 min par défaut).
  - **Pause minimum** entre deux popups.
  - Bouton « Remettre les réglages d'origine ».
  - Les réglages d'origine reproduisent **exactement** le comportement d'avant.
- **Stats ▸ 💸 Achats & pubs ▸ 🔔 Popups refaites.** Pour chaque popup, en clair : affichages, joueurs, fenêtres d'achat, achats, % et Robux. Une phrase dit à quoi sert chaque popup. La pub et le popup de départ ont leurs propres mesures (pubs regardées, récompenses prises).
- **Erreurs de stats corrigées :**
  1. Seulement 3 popups étaient suivis sur 9.
  2. Un clic dans le shop « volait » l'achat d'un popup automatique ouvert juste après. Maintenant, le plus récent des deux gagne.
  3. Les packs de 1 000 / 2 500 points du **shop** étaient parfois comptés comme « Offre après des morts ».
  4. Le popup VIP était compté deux fois.
  5. « Joueurs / jour » était sous-estimé : les jours d'avant l'installation comptaient comme 0.
  6. Les titres avec des fréquences écrites en dur (« toutes les 13 min ») sont renommés. L'historique déjà enregistré reste regroupé au bon endroit.
- **Sécurité :**
  - Le 2e script de favori (`datastore alr ask favorite game`) faisait une lecture DataStore par appel du client, sans limite : un tricheur pouvait vider le budget DataStore du serveur. Maintenant : 1 lecture max par session.
  - La réponse au favori n'est acceptée que si on vient vraiment de poser la question.
- **Bug corrigé :** l'offre après des morts ne comptait jamais les morts de la toute première vie.

### 8. Leaderboards
- Nouveau look, comme les Paramètres et le CombatHUD : panneau sombre, police BuilderSans, titre blanc, boutons 3D. La couleur de chaque board est gardée.
- Fonctions reprises du jeu de boule :
  - onglets **ALL / FRIENDS** (toi + tes amis, avec leur vraie place) ;
  - **🔍 FIND ME** (défile jusqu'à toi et te fait clignoter) ;
  - **ta ligne en bas** (« #12 YOU · 1.2M » ou « not in the top 100 yet ») ;
  - barre **NEXT UPDATE**.
- Le bouton DONATE du board de dons marche toujours.
- **Revenir à l'apparence d'avant :** dans `ReplicatedStorage ▸ LeaderboardStyle`, mets `Style = "classic"`. C'est exactement l'ancien rendu.

### Vue PvP gardée sans arme (nouveau script `ArenaViewKeeper`)
- **Avant :** en arène, en vue « lock », ranger ton arme rendait la caméra libre de Roblox.
- **Maintenant :** sans arme, la vue reste la même que celle des armes. En mode **lock**, la caméra reste derrière l'épaule, la souris reste bloquée au centre et le perso suit la caméra (même distance, même décalage).
- **En 1re personne :** sur mobile et console, ça reste en 1re personne. Sur PC, l'arme utilise déjà la caméra normale de Roblox, donc rien ne change.
- Quand tu ressors une arme, elle reprend la caméra **exactement là où tu regardais** : aucun saut.
- **Hors arène :** rien ne change, et le script ne tourne même pas.
- **Revenir à avant :** dans `ArenaViewKeeper`, mets `ENABLED = false` à la ligne 18, ou supprime le script.
- Le bouton lock mobile ne s'ajoute pas par-dessus (pas de double décalage).

### 10. Invitations d'amis
- Le parrainage ne paie que si l'invité est un **vrai nouveau joueur** : moins de 10 min de jeu enregistrées avant cette session, et 1re arrivée il y a moins de 30 min. Sinon **personne** n'est payé.
- Ça ferme les deux failles :
  - deux amis qui s'invitent l'un l'autre à des jours différents ;
  - inviter quelqu'un qui joue déjà.
- Le parrain voit « Friend Already Played — invite rewards only count for friends who are NEW to the game ».

---

## Vérifications faites (et ce qui reste à tester dans Studio)
Fait de mon côté, sur tous les fichiers livrés :
- les 32 fichiers passent un analyseur de syntaxe Luau (le même analyseur valide les 669 scripts d'origine sans erreur) ;
- aucune fonction ou variable de niveau principal n'a disparu par erreur (comparaison avec l'original). Ce contrôle a permis de trouver et corriger un bloc mal déplacé dans `new donation board server` ;
- recherche de variables non déclarées ;
- `time` reste à 199 variables locales de niveau principal (limite Luau : 200), aucune ajoutée ;
- le panel admin n'a pas de nouvelle variable de niveau principal (nouvelle section dans un bloc isolé) ;
- chaque valeur venant d'un client est vérifiée côté serveur (réglages popups : admins seulement, bornes min/max ; favori ; dons cross-server : messages serveur uniquement).

**Je n'ai pas pu lancer le jeu.** À tester dans Studio (*Play* ou *Team Test*) avant de publier :
1. **Leaderboards :** regarde le rendu sur chaque board. Clique ALL / FRIENDS / FIND ME. Vérifie que le bouton DONATE est toujours visible.
2. **Admin ▸ 🔔 POPUPS :** change un réglage, puis vérifie qu'il reste après avoir rouvert le panel.
3. **Admin ▸ fiche d'un joueur :** badges + « il y a X j Y h ».
4. **Arène PvP :** en vue lock, range ton arme. La vue doit rester verrouillée. Ressors-la : aucun saut de caméra. Sors de l'arène : la caméra redevient normale.
5. **Mobile** (émulateur Studio) :
   - active le lock, meurs : il doit rester ON ;
   - entre en arène : le lock se met en pause ;
   - curseur plus gros.
6. **Obby :** meurs 10 fois → l'offre de points apparaît (si activée).
7. **À vérifier sur un vrai serveur publié** (MessagingService et TeleportService ne marchent pas en Studio) :
   - un don → effet sur un 2e serveur ;
   - un reload AFK → retour à la bonne place ;
   - un réglage popup → appliqué sur les autres serveurs.
