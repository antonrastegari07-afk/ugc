# 🧰 Outils gardés pendant un reset serveur + 🔒 faille GiveToolEvent
Installation complète : voir la conversation (SessionToolCarry + 3 petites lignes + UIFocus).

## 🖐️ Outil en main + rechargement AFK
- L'outil tenu en main (coil, Scythe…) est ré-équipé au retour (seulement un outil déjà dans le sac, jamais créé).
- Script « time », dans `_G.TeleportForAfkReload`, juste après `local opts = Instance.new("TeleportOptions")` :
  `if _G.SessionToolCarrySave then pcall(_G.SessionToolCarrySave, player) end`
