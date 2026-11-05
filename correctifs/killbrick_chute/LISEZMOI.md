# 🛟 Morts « sans raison » après une grande chute (niveau 112 → 113, et d'autres niveaux)

## La cause

- Le portail du niveau 112 envoie le joueur en haut de la tour (y = 1328). Il tombe environ **215 studs** jusqu'au sol du checkpoint 113.
- Juste sous ce sol, il y a un **kill brick invisible** : `Workspace.Part`, 528 × 1 × 300, transparence 1. C'est le « Undermapkill » du coin, à seulement **7 studs** sous le sol.
- À l'arrivée, le joueur tombe à environ **290 studs/s**. Le sol ne fait que 1,3 stud d'épaisseur : avec un petit PC ou du lag, le personnage **traverse le sol en une seule image** et touche le kill brick invisible juste dessous. Il meurt alors qu'il a bien atterri, d'où le « pas de kill part visible ».
- C'est pour ça que ça n'arrive qu'à **certaines personnes** : surtout celles qui ont peu d'images par seconde.

Autres checkpoints où un kill brick invisible est très proche sous le sol (moins de 15 studs) : **1, 2, 3, 4, 6, 100, 101, 102, 111**. Le plus dangereux reste le **113** (7 studs, et une très longue chute).

## Le correctif (aucun changement de gameplay)

Dans le gestionnaire des scripts du Workspace :
- si un joueur touche un kill brick **invisible** en tombant **très vite** (plus de 110 studs/s) **et** qu'un sol se trouve juste au-dessus de lui (celui qu'il vient de traverser), il est **reposé sur ce sol** au lieu de mourir ;
- une chute normale dans le vide n'est pas concernée : en tombant d'un bord, on n'atteint jamais cette vitesse avant le kill brick, et il n'y a pas de sol au-dessus ;
- les kill bricks **visibles** (les blocs rouges, les obstacles) ne changent **pas du tout** ;
- l'anti-cheat est prévenu, pour ne pas prendre ce petit déplacement pour une téléportation.

## Installation

| Où | Fichier |
|---|---|
| ServerScriptService ▸ **WorkspaceScriptsManager** | `WorkspaceScriptsManager_COMPLET.lua` (remplacer tout) |

Ensuite, publie puis fais **Shut down all servers**.

## Optionnel, dans Studio (encore plus sûr)

Descends le kill brick invisible sous le niveau 113 d'environ 40 studs :
- `Workspace.Part` à la position **(3830, 1105, 857)**, taille 528 × 1 × 300, transparence 1 ;
- mets sa position Y à **1065**.

Le vide reste mortel, mais il y a alors beaucoup plus de marge sous le sol.
