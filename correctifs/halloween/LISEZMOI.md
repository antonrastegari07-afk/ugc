# 🎃 HalloweenEvent_Client : correctif « trop de variables locales »

StarterPlayer ▸ StarterPlayerScripts ▸ HalloweenEvent_Client : remplacer tout par `HalloweenEvent_Client_COMPLET.lua`.

Le script avait 209 variables locales au niveau principal. Roblox en accepte 200 au maximum, donc il ne pouvait pas démarrer : pas de fenêtre du pass Halloween, pas de pièces dans les zones.

Correctif : 6 services regroupés dans une table `SVC`, et 11 petites fonctions dans une table `H`. Le script a maintenant 194 variables locales. Rien d'autre ne change.
