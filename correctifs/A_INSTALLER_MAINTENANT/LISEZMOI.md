# À corriger maintenant

Les deux scripts s'appellent « UGC SHOP ORDER ». Le code serveur a été collé dans le LocalScript
(StarterPlayerScripts) au lieu du Script serveur (ServerScriptService).

| Fichier | Où dans Studio | Script |
|---|---|---|
| `1_ServerScriptService__UGC_SHOP_ORDER.lua` | **ServerScriptService** | `UGC SHOP ORDER` — icône de Script (serveur) |
| `3_StarterPlayerScripts__UGC_SHOP_ORDER__a_REMETTRE.lua` | **StarterPlayer ▸ StarterPlayerScripts** | `UGC SHOP ORDER` — icône de LocalScript : on lui remet son code d'origine |

(`stock restant` est déjà bien installé dans ta version 12.)
