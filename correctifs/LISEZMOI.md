# Correctifs chargement / GPU

Ce dossier ne modifie pas ton jeu : ce sont des scripts à installer dans Studio.
Fais une copie de ton jeu avant, et teste dans Studio (Play), puis avec 2 joueurs (Test ▸ Clients and Servers).

## 1. Écran de chargement dans ReplicatedFirst

Fichier : `LoadingScreen_ReplicatedFirst.lua`

1. Crée un **LocalScript** dans **ReplicatedFirst** et colle le contenu du fichier.
2. **Supprime** l'ancien `Screen LOADER` de StarterPlayer ▸ StarterPlayerScripts, sinon il y aura deux écrans.
3. Ne touche pas à `LoaderStreamFocus` (ServerScriptService) : il reste utile.

Pourquoi la caméra partait sur le perso dans ReplicatedFirst, et ce qui est corrigé :

- Dans ReplicatedFirst, le script démarre avant que le décor arrive. `WaitForChild("CameraPartModel", 5)` abandonnait au bout de 5 s : la caméra n'était jamais forcée, donc elle suivait le perso. Maintenant, la CameraPart est attendue en arrière-plan (jusqu'à 60 s) sans bloquer l'écran.
- Pendant le chargement, Roblox remplace `workspace.CurrentCamera`, et l'ancien script gardait une référence vers l'ancienne caméra. Maintenant la caméra est relue à chaque image.
- La caméra est forcée avec `BindToRenderStep` en priorité Camera + 1, c'est-à-dire après le script caméra de Roblox. Elle ne repart plus sur le perso quand il apparaît.
- Le fond noir reste en place tant que la vue sur l'île n'est pas prête.
- La barre monte jusqu'à 30 % pendant le vrai chargement du jeu.
- Le bouton SKIP n'apparaît qu'une fois le jeu entièrement chargé.

## 2. Glows (même rendu, beaucoup moins de GPU)

Fichiers dans `glow/`

1. Crée un **ModuleScript** nommé **GlowEngine** dans **ReplicatedStorage** et colle `glow/GlowEngine.lua`. Aucune image à uploader.
2. Colle `glow/CONVERTIR_LES_GLOWS_barre_de_commande.lua` dans la **barre de commande** de Studio (Affichage ▸ Barre de commande), puis appuie sur Entrée.
   - Les 27 scripts glow sont convertis, avec la même CONFIG (couleurs, palette, tailles, vitesse, étincelles).
   - L'ancien code est sauvegardé dans ServerStorage ▸ GlowBackup (jamais envoyé aux joueurs).
   - Si tu as déjà fait la conversion, il suffit de remplacer le contenu de `GlowEngine` : les scripts convertis restent bons.

**Même glow qu'avant** : même forme, mêmes couleurs, même taille, même LED (les mêmes 24 blocs de couleur par côté, qui tournent à la même vitesse), même shimmer, mêmes étincelles. Les côtés sont recréés exactement comme dans ton script. Seuls les **coins** changent de technique : 12 bandes par coin au lieu de centaines de Frames « pixels ». Chaque bande porte un dégradé qui reprend la même formule d'opacité et de couleur que ton script, placé au pixel près (pas de ligne aux jonctions).

| | Avant | Après |
|---|---|---|
| Objets créés au démarrage (27 glows, PC 1080p) | **≈ 36 000** | **≈ 7 300** |
| Coins d'un glow | 450 à 2 900 Frames « pixels » | 100 objets (4 × 12 bandes + leurs dégradés) |
| CanvasGroup (texture cachée redessinée 30×/s) | 18 | 0 |
| LED rotatif | Toujours actif, même shop fermé (≈ 270 000 changements de couleur/s) | Seulement quand le glow est à l'écran |
| Étincelles | Objets créés et détruits en boucle | Mêmes objets réutilisés |

## 3. Outils admin seulement pour les admins

Fichier : `admin/AdminToolsGiver.lua`

1. Mets les LocalScripts admin dans **ServerStorage** (directement ou dans n'importe quel dossier : le script les retrouve par leur nom).
2. Ce sont ceux-ci, à retirer de StarterPlayerScripts :
   - `Admin client`
   - `WEAPON ANIM STUDIO`
   - `admin panel points`
3. Crée un **Script** dans **ServerScriptService** et colle le fichier.

`GiftingClient` reste dans StarterPlayerScripts : il est pour tout le monde.
`GIFT local` est désactivé, et c'est une copie exacte de `GiftingClient` : tu peux le supprimer.

## 5. Les 1 177 scripts copiés-collés du Workspace → 1 script serveur + 1 script joueur

Dossier : `workspace_scripts/`. **Fais une copie du jeu avant.**

Ce qui est converti (même fonctionnement, code recopié de tes scripts d'origine) :

| Famille | Scripts | Réglages repris script par script |
|---|---|---|
| Drop parts | 400 | Délai avant disparition (0,05 / 0,25 / 0,5 / 1 s) |
| Kill bricks (Undermapkill, Part9) | 416 | — |
| Blocs de dégâts | 99 | Dégâts (10 à 49), temps d'attente (0,04 à 1 s) |
| Achats au toucher (coils) | 60 | ID du pass, nom du RemoteEvent |
| Achat au toucher x2 coins | 20 | ID du pass |
| Projection blocs / BouncePad | 47 | Force avant, force haut, cooldown |
| Fondu au toucher | 43 | — |
| Spots qui clignotent | 32 | → tourne **chez le joueur** (plus rien envoyé par le réseau) |
| Flashing Brick (transparence seulement) | 4 | → tourne **chez le joueur**, la collision ne change pas |
| Son de bouton | 19 | — |
| Tapis roulants (Hard obby) | 13 | — |
| Danseurs | 13 | Leur animation |
| Portails | 11 | — |

Seule différence : les lignes `print("… est assez proche pour acheter le pass.")` de 2 coils ne s'affichent plus dans l'Output du serveur.

Les ≈ 90 scripts uniques (boutons parcours, timers, etc.) ne sont pas touchés. Un script dont le code diffère, même d'un caractère, de sa famille n'est pas touché non plus.

### Installation
1. **ModuleScript** `WorkspaceScriptsConverter` dans **ServerStorage** ← `workspace_scripts/WorkspaceScriptsConverter.lua`
2. **Script** `WorkspaceScriptsManager` dans **ServerScriptService** ← `workspace_scripts/WorkspaceScriptsManager.lua`
3. **LocalScript** `VisualEffects` dans **StarterPlayer ▸ StarterPlayerScripts** ← `workspace_scripts/VisualEffectsClient.lua`
4. **Barre de commande, test** (ne change rien) :
   ```lua
   require(game.ServerStorage.WorkspaceScriptsConverter).Run()
   ```
   L'Output doit afficher **TOTAL 1177**, avec le détail par famille.
5. **Barre de commande, conversion** :
   ```lua
   require(game.ServerStorage.WorkspaceScriptsConverter).Run(true)
   ```
   Les anciens scripts sont **déplacés** (pas supprimés) dans `ServerStorage ▸ WorkspaceScriptsBackup`.
6. Teste en Play : drop parts, kill bricks, dégâts, coils, projections, bounce pads, portails, danseurs, spots, Flashing Brick.
7. Pour tout remettre comme avant :
   ```lua
   require(game.ServerStorage.WorkspaceScriptsConverter).Restore()
   ```
   Ctrl+Z marche aussi juste après la conversion.

Le convertisseur enregistre aussi éteintes les particules de `DonationEffect2`. Tes scripts de dons les éteignaient déjà 5 s après le démarrage du serveur, et les rallument pendant un don comme avant.

### Vérifications faites (sur ta version « final copy after glow and other fixes »)
- **879 réglages** comparés un par un avec le code d'origine (délais, dégâts, forces dont −170, ID de pass, RemoteEvents) : **0 différence**.
- Chaque famille est reconnue **en entier**, et aucun script reconnu n'est écarté.
- **Aucun autre script du jeu** n'accède à ces scripts par leur nom, ne les désactive, ne clone ou ne déplace leurs parts. Les plateformes mobiles qui portent des kill bricks ne font que les déplacer.
- **Comportement testé** dans un environnement Roblox simulé : 19 vérifications OK.
- **Restent sur le serveur, volontairement :**
  - les hélices et les spin kill bricks (ils contiennent des kill bricks) ;
  - les cylindres, flèches et missiles (ils tuent) ;
  - tous les systèmes de données, d'économie et d'anti-triche.

  Les passer côté joueur changerait le gameplay.
