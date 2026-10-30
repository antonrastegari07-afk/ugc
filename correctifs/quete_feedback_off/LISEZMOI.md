# Désactiver la quête « Leave Feedback » (sans la supprimer)

1. **ReplicatedStorage ▸ QUEST_SYSTEM_CONFIG**, 2 remplacements :

   Cherche :
   ```lua
   	Feedback = {          -- envoyer un feedback (serveur : module FeedbackQuest)
   		Enabled = true,
   ```
   Remplace par :
   ```lua
   	Feedback = {          -- envoyer un feedback (serveur : module FeedbackQuest)
   		Enabled = false,  -- 🔘 quête désactivée (true pour la remettre)
   ```

   Cherche :
   ```lua
   		"Kill500", "Group", "Discord", "Feedback",
   ```
   Remplace par :
   ```lua
   		"Kill500", "Group", "Discord", -- "Feedback",  (quête désactivée : remets "Feedback", pour la réafficher)
   ```

2. **ServerScriptService ▸ QuestSystem ▸ FeedbackQuest** (ModuleScript) : remplace **tout** par `FeedbackQuest_COMPLET.lua`.
   - Il lit `Enabled` dans la config.
   - À `false`, **aucun point ne peut être réclamé**, même en appelant le remote à la main.
   - Envoyer un feedback ne débloque plus rien.
   - La quête est cachée de la liste et son bouton est inactif.
   - La progression des joueurs est **gardée** pour le jour où tu la remets.

**Pour la réactiver :** remets `Enabled = true` et `"Feedback",` dans `Order`. Le code reste en place.
