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

1. Upload `glow/glow_texture.png` dans Roblox (Asset Manager ▸ Import), puis copie son ID.
2. Crée un **ModuleScript** nommé **GlowEngine** dans **ReplicatedStorage** et colle `glow/GlowEngine.lua`. Mets l'ID à la ligne `local TEXTURE_ID = "rbxassetid://..."`.
3. Colle `glow/CONVERTIR_LES_GLOWS_barre_de_commande.lua` dans la **barre de commande** de Studio (Affichage ▸ Barre de commande), puis appuie sur Entrée.
   - Les 27 scripts glow sont convertis, avec la même CONFIG (couleurs, palette, tailles, vitesse, étincelles).
   - L'ancien code est sauvegardé dans ServerStorage ▸ GlowBackup (jamais envoyé aux joueurs).

**Même glow qu'avant** : même forme, mêmes couleurs, même taille, même LED (les mêmes 24 blocs de couleur par côté, qui tournent à la même vitesse), même shimmer, mêmes étincelles. Les côtés sont recréés exactement comme dans ton script. Seuls les **coins** changent de technique : 1 image par coin au lieu de centaines de Frames « pixels », avec la même formule de dégradé.

| | Avant | Après |
|---|---|---|
| Objets créés au démarrage (27 glows, PC 1080p) | **≈ 36 000** | **≈ 4 750** |
| Coins d'un petit glow (UGCshop, Daily, Rebirth) | ≈ 2 900 Frames de 1 px | 4 images |
| Coins d'un gros glow | ≈ 450 Frames | 4 images |
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
