# ⚔️ La Scythe reste en PvP (emplacements obby / pvp séparés)

## 1. ServerScriptService ▸ JackScythe ▸ JackScytheService
- Après `S.InArena = inArena` : ajouter
  `local KEEP_IN_PVP = Config.KeepInPvP ~= false   -- ⚔️ la faux reste aussi en PvP (Config.KeepInPvP = false = comme avant)`
- `if inArena(player) then return true end ...` → `if inArena(player) and not KEEP_IN_PVP then return true end`
- `if not rec or pending[uid] or inArena(player) then return end` → `if not rec or pending[uid] or (inArena(player) and not KEEP_IN_PVP) then return end`

## 2. ServerScriptService ▸ tp1v1 new gestion (Ctrl+H, Remplacer tout)
- `if item:IsA("Tool") then item:Destroy() end` → `if item:IsA("Tool") and not item:GetAttribute("JackScythe") then item:Destroy() end` (4 fois)
- `table.insert(playerSavedTools[uid], item.Name)` → `if not item:GetAttribute("JackScythe") then table.insert(playerSavedTools[uid], item.Name) end` (2 fois)

Les emplacements sont déjà sauvegardés séparément (CustomBackpack + InventoryLayoutServer : modes « obby » et « pvp »).
