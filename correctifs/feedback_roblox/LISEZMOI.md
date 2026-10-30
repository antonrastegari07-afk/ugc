# Feedback : passage au système officiel de Roblox

Le bouton **FEEDBACK** des Settings garde le même style (mêmes couleurs, même police, mêmes cartes). La page contient maintenant :
1. **« What to write »** : bug (où, sur quel appareil), idée, UGC voulue, truc injuste, ce qu'il aime. « Be specific ».
2. Un gros bouton **📝 WRITE MY FEEDBACK** qui ouvre la fenêtre officielle de Roblox (`SocialService:PromptFeedbackSubmissionAsync`).
3. Les feedbacks arrivent dans ton **Creator Dashboard ▸ Audience ▸ Feedback**, plus dans l'admin panel. L'ancien onglet feedback de l'admin panel garde les anciens messages.

## Installation
1. **StarterPlayerScripts ▸ SettingsUI** : remplace **tout** par `SettingsUI_COMPLET.lua` (ce dossier). C'est la même version que celle de `notes_v6` (bouton PROFILE + UGC), avec en plus la nouvelle page Feedback.
2. **ServerScriptService** : nouveau Script `FeedbackPrompt_Server` ← `FeedbackPrompt_Server.lua`.
3. Rien d'autre à changer : la quête « Send Feedback » et `FeedbackSystem_Server` restent tels quels.

## À savoir
- Roblox ne permet **qu'un feedback par jour** par joueur et par jeu.
- **Toi (propriétaire) et tes admins** verrez « feedback unavailable » : c'est normal, Roblox ne laisse pas le créateur s'envoyer un feedback. Teste avec un autre compte, **en jeu publié**. Le bouton ne fait rien dans Studio.
- Roblox **ne dit pas** au jeu si le joueur a vraiment envoyé quelque chose. La quête se débloque donc quand il ouvre la fenêtre (voir plus bas).

## La quête « Send Feedback » (1000 pts) : on la garde ?
Oui, elle reste **sûre là où ça compte** : 1000 pts **une seule fois par compte**, garanti par son DataStore atomique (0 → 1 → 2), même en spammant ou depuis 2 serveurs. Il faut aussi être en jeu depuis 30 s.

Ce qui change : avant, il fallait écrire au moins N caractères, mais un tricheur pouvait déjà envoyer n'importe quoi. Maintenant, ouvrir la fenêtre suffit. Au pire, quelqu'un gagne 1000 pts sans écrire, une seule fois, comme avant.

En échange, la quête pousse beaucoup de joueurs à ouvrir la fenêtre, et donc à t'écrire. **Je te conseille de la garder.**
