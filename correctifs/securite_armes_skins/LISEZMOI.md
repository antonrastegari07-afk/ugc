# Sécurité des armes skinnées (faille grave)

## Le problème
Les 11 skins d'armes (obtenus dans les crates et donnés en 1v1) utilisent encore l'**ancien** script serveur, qui fait confiance au client :

- **N'importe qui peut tuer n'importe qui, n'importe où.** Le script accepte du client la cible, les **dégâts** (même énormes ou négatifs) et l'**« attaquant »**. Il ne vérifie pas que le joueur tient l'arme. Dès qu'un joueur a un de ces skins en main, un exploiteur peut utiliser **sa** RemoteEvent pour tuer tout le serveur à distance, ou attribuer les kills à quelqu'un d'autre.
- **Lag du serveur.** `CreateTracer` n'a aucune limite : des milliers de parts peuvent être créées.

Les armes de base (AK47, Deagle, Sniper, ShotGun…) ne sont **pas** concernées : elles passent par `WeaponServer`, qui vérifie déjà tout.

## La correction
Pour chaque skin, le haut du script ne change pas (traceur de la même couleur, de la même durée, même lumière). Seule la partie qui reçoit les messages est remplacée, avec les **mêmes règles que WeaponServer** :
- l'arme doit appartenir à ce joueur (dans son perso ou son sac) ;
- les dégâts et l'attaquant sont décidés **par le serveur** : ce sont les mêmes valeurs que le client envoyait déjà (AK47 27, Deagle 54, ShotGun 15 par balle, Sniper 101) ;
- la cible doit être à portée (1 000 studs, comme le client) ;
- le nombre d'appels par seconde est limité à la cadence de l'arme, +50 % de marge réseau ;
- le traceur doit partir de l'arme, et sa longueur est limitée.

**Pour un vrai joueur, rien ne change** : mêmes dégâts, même cadence, même portée, mêmes sons, flashs et traceurs.

## Installation (11 scripts, dans ServerStorage)
Pour chaque ligne, ouvre le script, **sélectionne tout (Ctrl+A)** et colle le contenu du fichier :

| Script dans ServerStorage | Fichier |
|---|---|
| AK47_Gold Dragon ▸ Server | `AK47_Gold_Dragon__Server.lua` |
| AK47_Purple Skeleton ▸ Server | `AK47_Purple_Skeleton__Server.lua` |
| Deagle_Pirate Gun ▸ Server | `Deagle_Pirate_Gun__Server.lua` |
| Deagle_RayGun ▸ Server | `Deagle_RayGun__Server.lua` |
| ShotGun_FAAAH ▸ Server | `ShotGun_FAAAH__Server.lua` |
| ShotGun_Spas12 ▸ Server | `ShotGun_Spas12__Server.lua` |
| Sniper_Atomic Sniper ▸ Servertest | `Sniper_Atomic_Sniper__Servertest.lua` |
| Sniper_NoScope ▸ Servertest | `Sniper_NoScope__Servertest.lua` |
| Sniper_Sci-Fi Sniper ▸ Servertest | `Sniper_Sci-Fi_Sniper__Servertest.lua` |
| Sniper_Silenced Sniper ▸ Servertest | `Sniper_Silenced_Sniper__Servertest.lua` |
| Sniper_Trash Sniper ▸ Servertest | `Sniper_Trash_Sniper__Servertest.lua` |

Ne touche pas aux scripts `Client` / `Clienttest` ni `WeldArm`.

## Vérifié
- Chaque fichier part de **ton** script actuel (version « final final ready publish »).
- Simulation : 18 vérifications × 11 armes, toutes OK.
  - Un vrai joueur : son, flash, traceur et dégâts normaux.
  - Tentatives de triche toutes bloquées : arme d'un autre joueur, dégâts 1e9, faux attaquant, cible à 3 000 studs, toucher soi-même, 1 000 coups/s, traceurs géants / loin de l'arme / NaN, données invalides.

## Test en Play (2 joueurs)
En 1v1, avec un skin équipé, tire sur l'autre joueur : mêmes dégâts qu'avant, popup de dégâts, kill compté pour le bon joueur.
