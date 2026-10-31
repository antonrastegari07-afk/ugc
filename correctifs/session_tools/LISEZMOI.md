# 🧰 Outils gardés pendant un reset serveur
1. ServerScriptService : nouveau Script `SessionToolCarry` ← `SessionToolCarry_SERVEUR.lua`
2. ServerScriptService ▸ tp1v1 new gestion : après la fonction `restorePlayerTools`, ajouter
   `_G.GetArenaSavedTools = function(uid) return playerSavedTools[uid] end`
