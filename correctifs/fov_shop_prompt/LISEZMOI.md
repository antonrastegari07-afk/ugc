# FOV : prompt d'achat pendant le shop

## Le problème

Pendant un prompt d'achat ouvert depuis le shop, **deux scripts écrivaient le FOV en même temps** :

- **UIFocus ▸ SceneEffects** écrit le FOV du shop à chaque image ;
- **RobuxPromptFX ▸ UIZoomController** zoome par-dessus avec un Tween, en partant du FOV **normal** (70) et non de celui du shop.

À la fermeture du prompt, qu'il y ait achat ou refus, UIZoomController remettait 70 alors que le shop était encore ouvert. Le FOV changeait d'un coup, puis UIFocus le reprenait : c'est le flick, avec un FOV pas normal.

## La correction : un seul script écrit le FOV à la fois

- **Menu UIFocus ouvert** (shop…) : UIFocus écrit le FOV et **ajoute lui-même** le zoom du prompt. Pendant ce temps, UIZoomController n'écrit plus rien (`SetExternal`).
  - Prompt fermé : le FOV revient **en douceur au FOV du shop**.
  - Shop fermé : retour au FOV normal (70).
- **Aucun menu ouvert** : UIZoomController fonctionne comme avant.
- **Passage de l'un à l'autre** (shop fermé pendant le prompt, shop ouvert pendant le prompt) : le script qui reprend la main **repart de la valeur affichée**, donc pas de saut.

Valeurs avec la config actuelle :

| Situation | FOV |
|---|---|
| Normal | 70 |
| Shop ouvert | 60 |
| Shop + prompt | 52 |
| Prompt seul | 62 |

## Installation (2 scripts, remplacer TOUT le contenu)

1. **StarterGui ▸ UIFocusSystem ▸ SceneEffects** : remplace tout par `SceneEffects_COMPLET.lua` (ce dossier).
2. **ReplicatedStorage ▸ RobuxPromptFX ▸ UIZoomController** : remplace tout par `UIZoomController_COMPLET.lua` (ce dossier).

Ces 2 fichiers remplacent ceux de `fov_doublons/`, dont tous les correctifs sont conservés :

- FOV normal fixe à 70 ;
- filet de sécurité ;
- attribut `UIZoomActive` ;
- base = FOV normal.

**Il faut mettre les deux.** Si un seul des deux scripts est mis à jour, rien ne casse et on retrouve l'ancien comportement : SceneEffects ne se branche au prompt que si UIZoomController a les nouvelles fonctions.

## Vérifié par simulation (image par image, 60 FPS)

Scénarios testés, avec le FOV attendu à chaque étape et aucun saut de plus d'une image normale d'animation :

1. Shop → achat → refus → fermeture du shop : 52 → 60 → 70.
2. Shop → achat → **shop fermé pendant le prompt** → fin du prompt : 52 → 62 → 70.
3. Prompt sans menu → shop ouvert pendant le prompt : 62 → 52 → 60 → 70.
4. Clics très rapides (ouvrir / fermer / acheter en moins de 0,5 s) : 70 à la fin.
5. Plusieurs achats enchaînés dans le shop : 60 puis 70.
6. Caméra remplacée pendant shop + prompt : valeurs justes.
7. Shop fermé puis rouvert pendant le zoom : valeurs justes.
8. 1 200 séquences aléatoires, plus 400 avec des changements de caméra : 100 % OK.

Sur les mêmes tests, l'ancienne version n'en réussissait que 189 sur 400.

## À tester en Play

1. Ouvre le shop, lance un achat, **refuse** : retour au FOV du shop, puis 70 en fermant le shop.
2. Pareil en **achetant** (en Studio, l'achat de test suffit).
3. Lance un achat puis ferme le shop avant de répondre au prompt : 62, puis 70.
4. Achat hors menu : zoom, puis 70.
