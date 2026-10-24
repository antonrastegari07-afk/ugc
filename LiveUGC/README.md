# 📡 LIVE UGC REDEEMS — Installation

Board qui affiche en direct les derniers UGC récupérés :
**qui** (avatar + nom, VIP doré, clic → fiche profil) et **quel UGC** (nom + la même image que dans le UGC shop).
Aucune heure ni temps de récupération n'est affiché.
Le titre **● LIVE UGC REDEEMS** flotte au-dessus du panneau (BillboardGui), dans le même style que le « LIVE NOW! » du shop d'Halloween : texte épais et penché, dégradé lavande → mauve, contour sombre, et un point rouge qui clignote à côté de « LIVE ».
Tout le board suit un seul thème mauve. Ce n'est pas un classement : pas de rang, et les redeems plus anciens deviennent de plus en plus discrets.
L'image de l'UGC est posée sur une case mauve moyen, lisible pour les UGC noirs comme pour les clairs. Le nom de l'UGC est du même mauve que `[UGC REDEEM]` dans le chat.

À chaque nouveau redeem :
- une place s'ouvre en haut de la liste et les autres descendent,
- la carte glisse, l'image de l'UGC apparaît en grossissant légèrement et un léger flash mauve s'efface,
- une onde part du point rouge du titre.

Ça marche entre tous les serveurs : le redeem s'affiche partout en ~1 s (MessagingService).

---

## 1. UGC REDEEM LOG (script serveur existant) — 1 ligne

Dans `_G.UGCRedeem_Log`, juste **après** la table `local entry = { ... }` :

```lua
	-- 📡 Board public « LIVE UGC REDEEMS » (UGCLiveFeedServer)
	if _G.UGCLiveFeed_Push then task.spawn(_G.UGCLiveFeed_Push, entry) end
```

(C'est déjà fait dans le fichier `Scripts` du dépôt.)

## 2. LeaderboardCore (ModuleScript existant) — 1 ligne, optionnelle

Juste après `function Core.refreshVip() ... end` :

```lua
Core.registerAnim = registerAnim
```

Les animations du board passent alors par la même boucle Heartbeat que tes autres leaderboards.
Sans cette ligne, le board marche quand même, avec sa propre boucle.

## 3. Nouveau script serveur

`ServerScriptService` → **Script** nommé `UGCLiveFeedServer` → colle `UGCLiveFeedServer.lua`.

## 4. Nouveau script client

`StarterPlayer > StarterPlayerScripts` → **LocalScript** nommé `UGCLiveFeedClient` → colle `UGCLiveFeedClient.lua`.

## 5. Le panneau dans la map

Fais exactement comme pour tes autres leaderboards :

1. Crée une **Part** dans le Workspace, nommée **`UGCLiveBoard`** (ou `UGCLiveBoard2` pour un 2e panneau).
2. Mets-lui une **SurfaceGui** vide, avec la bonne `Face` (celle qui regarde les joueurs).
   Tu peux copier la SurfaceGui d'un leaderboard existant.

Le client remplace tout seul le contenu de la SurfaceGui, et la rend cliquable de la même manière que le Core.
Le titre flottant est créé automatiquement au-dessus de la Part, sans rien à placer à la main. Il peut faire jusqu'à 210 % de la largeur du panneau.

## 6. Tester

- **Game Settings > Security > Enable Studio Access to API Services** doit être activé (DataStore).
- En Play Solo, dans la **command bar côté serveur** :
  ```lua
  _G.UGCLiveFeed_Test()              -- UGC au hasard de UGC_CONFIG, pour toi
  _G.UGCLiveFeed_Test(123456, 9876)  -- userId, assetId précis
  ```
  Les tests n'écrivent rien dans le DataStore et ne s'affichent que sur ce serveur.
- Pour vider le board : `_G.UGCLiveFeed_Clear()`.
- Pour retirer un redeem : `_G.UGCLiveFeed_Remove("<id>")`.

---

## Réglages

**`UGCLiveFeedServer`**

| Réglage | Défaut | Rôle |
|---|---|---|
| `MAX_FEED` | 25 | nombre de redeems gardés |
| `HIDDEN_SOURCES` | `exploit`, `external` | voies jamais affichées (ajoute `admin` ou `free` si tu veux les cacher aussi) |
| `RESYNC_INTERVAL` | 180 | relecture du DataStore, au cas où un message live se perdrait |

**`UGCLiveFeedClient`** (table `CFG`)

| Réglage | Rôle |
|---|---|
| `title`, `verb`, `emptyText` | les textes |
| `billboard` | le titre flottant : taille (`widthScale`, `heightRatio`), hauteur au-dessus du panneau (`gap`), police (`font`), vitesse du point rouge (`blinkSpeed`), dégradé, contour |
| `boardNames` | les noms des Parts |
| `maxShown` | nombre de lignes affichées |
| `entryHeight` | hauteur d'une ligne |
| `palette` | le thème mauve (`card` = cartes, `tileTop`/`tileBottom` = case de l'UGC, `ugcName` = nom de l'UGC, `self` = ta ligne) |

## Coût

Par redeem : **1 `UpdateAsync` + 1 `PublishAsync`**.
Chaque serveur fait 1 `GetAsync` toutes les 3 min.
Les clients lisent le cache du serveur, donc aucun accès DataStore de leur côté.
