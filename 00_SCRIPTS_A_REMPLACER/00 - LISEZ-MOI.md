# Scripts à remplacer (versions finales)

Chaque fichier de ce dossier est la **bonne version** à coller dans Roblox Studio.
Entre crochets : où le mettre. Remplace-les **tous en même temps** (certains se parlent entre eux).

| # | Script | Où dans Roblox | Ce qui a été corrigé |
|---|---|---|---|
| 01 | checkpoints system | ServerScriptService | Prévient les quêtes Halloween à chaque checkpoint (touché / skip / rebirth), anti-exploit |
| 02 | HalloweenEvent_Server | ServerScriptService | Quêtes checkpoints + playtime, rebirth, weekly renouvelées chaque samedi à minuit pour tous, sauvegardes retentées, moins de réseau (vues des quêtes regroupées) |
| 03 | HalloweenEvent_Client | même place que ton client Halloween | Compteur weekly ; coins loin de toi rangés (plus affichés ni animés, rien dans le vide) |
| 04 | JackScytheService | ServerScriptService ▸ JackScythe | Faux jamais perdue, rendue après le PvP, faux DEV pour tous les admins, lame sans collision, anti-boucle si un autre script la retire |
| 05 | JackScythe_Client | StarterPlayer ▸ StarterPlayerScripts | Sortie instantanée, plus de rebond au dash, dash vers le haut, bouton DASH mobile seulement faux en main, correction du FOV gardée |
| 06 | SCYTHE_CONFIG | ReplicatedStorage ▸ JackScythe | `MaxUpAngle = 85` (dash vers le haut) |
| 07 | LoadingScreen | StarterPlayer ▸ StarterPlayerScripts (à la place de ton loader) | Plus de flash des UI à la fin du chargement |
| 08 | HowToPlay LocalScript | StarterGui ▸ How to Play ▸ HtpButton2 | S'ouvre sous l'écran noir, tout revient à la fermeture |
| 09 | UI_FOCUS_CONFIG | StarterGui ▸ UIFocusSystem | Ne cache jamais l'écran noir du loader |

**Ne pas remplacer** : `HALLOWEEN_EVENT_CONFIG` et `ScytheFX` — garde tes versions actuelles.
(Optionnel, dans HALLOWEEN_EVENT_CONFIG sous `C.ResetHourUTC` : `C.WeeklyResetDay = "Saturday"` — c'est déjà la valeur par défaut.)

⚠️ **Zones de coins** : si ton jeu a la version « une limite de coins par zone », dis-le avant d'installer le 02.
