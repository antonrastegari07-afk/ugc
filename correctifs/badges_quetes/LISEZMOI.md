# ❗ Points d'exclamation (quêtes + récompenses)

## Installation
1. **StarterPlayer ▸ StarterPlayerScripts** : SUPPRIME les 2 anciens LocalScripts
   - `exclamation quests button`
   - `exclamationpoint pulsion`
2. Même endroit : crée un **LocalScript** nommé `NotifBadges` et colle `NotifBadges_CLIENT.lua`.

Rien d'autre à changer : les scripts Daily / Playtime / shops allument toujours leurs `ExclamationPoint`.

## Ce qui change
- ❗ Quêtes : allumé seulement si une quête affichée dans la liste montre « Claim! ».
- 🎁 Daily : un seul ! même si daily ET playtime sont prêts.
- ⬆️ Les ! des boutons du HUD passent au-dessus de tous les autres boutons.
- 🌊 Même onde qu'avant, mais seulement quand le ! est à l'écran.

---

# ✨ Liste des quêtes (QuestListPolish)

## Installation
**StarterPlayer ▸ StarterPlayerScripts** : crée un **LocalScript** nommé `QuestListPolish` et colle `QuestListPolish_CLIENT.lua`.

## 🔘 Revenir à l'ancien comportement
En haut du script : `local ENABLED = true` → mets `false`. Le script ne fait alors plus rien
et la liste redevient exactement comme avant (aucun autre script n'est modifié).

## Ce qu'il fait
- Quêtes finies : même look gris « Claimed » / « Completed » que « Like the game ».
- Voile noir semi-transparent + check vert + « Completed » en blanc sur les quêtes finies.
- Ordre : Claim! → en cours → cooldown → finies (ordre de la config gardé dans chaque groupe).
- Tri à l'ouverture du menu ; la quête qu'on vient de récupérer glisse doucement à sa place.
