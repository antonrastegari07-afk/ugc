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
