# 🌀 Mort juste après le portail (niveau 112, et d'autres niveaux)

## Ce que montre la vidéo

- Le joueur passe le portail du niveau 112 et apparaît en haut de la tour.
- **0,5 s plus tard**, il disparaît en plein air : c'est une mort (ton script « dead pas son » rend le corps invisible), puis il réapparaît au checkpoint 112.
- Dans cette zone, il n'y a **aucun** kill brick (vérifié en tenant compte de l'orientation des pièces), ni flèche, missile, cylindre ou script qui tue.

## La cause (la plus probable)

- Juste **devant** le portail d'entrée, il y a les **blocs rouges qui tuent** (`Part9`, à 12 studs du portail).
- Le portail téléporte le joueur côté **serveur**. Pendant une fraction de seconde, le jeu du joueur continue d'envoyer ses **anciennes positions**, celles d'avant le portail, surtout avec du lag.
- Pour le serveur, le joueur « revient » donc un instant à côté des blocs rouges. Le kill brick le tue, alors que sur son écran il est déjà en haut de la tour.
- D'où « pas de kill part visible », et « seulement certaines personnes » : celles qui ont du lag.

Un seul autre portail du jeu a aussi des kill bricks visibles tout près de son entrée, à 11 studs ; ça peut être ton « autre niveau ».

## Le correctif

Dans `WorkspaceScriptsManager`, un kill brick (ou un bloc de dégâts) **ne tue plus** :
- pendant **2 s après un portail**, s'il est loin de l'arrivée du portail (c'est forcément un contact d'avant la téléportation) ;
- si le joueur est **déjà loin du bloc** au moment où le contact arrive au serveur (contact en retard).

Un contact normal tue toujours, exactement comme avant : testé sur le bloc rouge, le grand kill brick sous la map, et le retour sur le bloc 5 s après.

Le fichier garde aussi la protection précédente (joueur qui traverse un sol en tombant très vite). Elle ne joue pas ici, mais elle reste utile.

## Installation

| Où | Fichier |
|---|---|
| ServerScriptService ▸ **WorkspaceScriptsManager** | `WorkspaceScriptsManager_COMPLET.lua` (remplacer tout) |

Ensuite, publie puis fais **Shut down all servers**.

Pour les autres scripts qui téléportent un joueur, ils peuvent appeler `_G.WSM_MarkTeleport(player, positionArrivée)` pour profiter de la même protection.
