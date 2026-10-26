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

Le rendu reste le même : même dégradé (formule identique), mêmes couleurs, même LED qui tourne, même shimmer, mêmes étincelles. Une seule différence : les couleurs du LED glissent en continu au lieu de 24 petits blocs par côté.

| | Avant | Après |
|---|---|---|
| Objets par gros glow | ~550 Frames + 1 CanvasGroup | 8 images |
| Objets par petit glow (UGCshop, Daily, Rebirth) | 2 000 à 4 000 Frames de 1 px | 4 Frames + 4 images |
| LED rotatif | ~18 000 changements de couleur/s par glow | 8 dégradés à 30 images/s |
| Étincelles | Objets créés et détruits en boucle | Mêmes objets réutilisés |
| Shop fermé | **Tout continuait de tourner** (ils ne s'arrêtaient que si l'ImageLabel lui-même devenait invisible) | Tout s'arrête dès que le glow n'est plus à l'écran |

## 3. Outils admin seulement pour les admins

Fichier : `admin/AdminToolsGiver.lua`

1. Crée un dossier **AdminClientScripts** dans **ServerStorage**.
2. Glisse dedans, depuis StarterPlayerScripts :
   - `Admin client`
   - `WEAPON ANIM STUDIO`
   - `admin panel points`
3. Crée un **Script** dans **ServerScriptService** et colle le fichier.

`GiftingClient` reste dans StarterPlayerScripts : il est pour tout le monde.
`GIFT local` est désactivé, et c'est une copie exacte de `GiftingClient` : tu peux le supprimer.
