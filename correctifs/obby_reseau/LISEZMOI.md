# Niveaux de l'obby : ce qui charge le réseau (Recv) et la perf

Analysé sur « final final ready publish ». Chaque objet du Workspace est rattaché au checkpoint le plus proche (Checkpoint1 à Checkpoint125).

## Ce qui envoyait le plus au joueur, en continu

| Où | Cause | Envoyé à chaque joueur | Correctif |
|---|---|---|---|
| **Tableaux de likes (lobby)** | Le serveur crée et anime des bulles toutes les 0,3 à 0,8 s sur 2 tableaux | chaque image de chaque bulle (+ création / destruction) | bulles créées **chez le joueur** |
| **Niveau 84** (sol qui tourne) | `PivotTo` déplace 37 parts une par une, 60 fois/s | ≈ 2 200 positions/s | parts soudées : **1** position/s au lieu de 37 (le sol reste serveur) |
| **Niveaux 10, 36, 60, 77, 78** | barres qui tournent (kill bricks / damage blocks) via le serveur, 20 fois/s | 20 positions/s chacune | tournent **chez le joueur** |
| **Niveau 46** | barre de dégâts qui tourne via le serveur, 60 fois/s | 60/s | tourne **chez le joueur** |
| **Niveau 49** | 2 murs tueurs qui tournent via le serveur, 10 fois/s | 20/s | tournent **chez le joueur** |
| **Niveaux 81-82** | `Magnum44_All` ×2 et `M4A1_All` : 93 MeshParts d'armes **non ancrées**, sans soudure, oubliées dans le Workspace | physique + textures lourdes | à ranger dans ServerStorage |

## Déjà bien faits, laissés tels quels
- Piège à pics (niveaux 96-97) : animé chez le joueur.
- Flèches enflammées : le serveur calcule, le joueur dessine.
- Missiles : chez le joueur.
- Décor de fin (niveau 125) et timer d'event : déjà en `RunContext = Client`.
- **Plateformes mobiles** (16, niveaux 101-104) : elles doivent rester en physique serveur pour **porter** le joueur. Elles sont déjà synchronisées sur l'heure du serveur.
- Cylindres (3 maximum) et boule (1 à la fois) : pièges physiques normaux, faible coût.
- Cordes (niveaux 9, 10, 82) : physique normale.
- Danseurs : ancrés, sans physique.

## Pourquoi « chez le joueur » ne change pas le gameplay
- **Ces barres tuent ou blessent au toucher.** Le toucher entre ton perso et une part est détecté par **ton** client, puis transmis au serveur. Les scripts `killCode` et le gestionnaire des damage blocks restent sur le serveur et réagissent comme avant.
- **C'est même plus juste qu'avant.** Avant, tu voyais la barre avec du retard réseau. Maintenant, la barre que tu vois est celle qui te touche.
- **Les autres scripts ne sont pas touchés.** Aucun autre script ne lit la position de ces barres. Personne ne marche dessus : l'anti-cheat, qui vérifie le sol sous le joueur, n'est donc pas concerné.
- **Le sol du niveau 84 reste sur le serveur**, justement parce que les joueurs marchent dessus et que l'anti-cheat lance un rayon vers le sol. Seule la façon de l'envoyer change : même centre, même vitesse.

## Vérifié
- Chaque « Cherche » existe **une seule fois** dans ton script actuel.
- Syntaxe OK sur les 9 scripts modifiés et sur le nouveau.
