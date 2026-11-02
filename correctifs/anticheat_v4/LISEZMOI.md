# 🛡️ Anti-cheat V4 : installation et réglages

## Installation (dans Studio)

| # | Où | Quoi faire | Fichier |
|---|---|---|---|
| 1 | ServerScriptService | **Nouveau ModuleScript**, nommé exactement `ANTICHEAT_CONFIG` | `ANTICHEAT_CONFIG.lua` |
| 2 | ServerScriptService ▸ anti fly/tp server | Remplacer tout | `AntiFlyTP_SERVEUR.lua` |
| 3 | ServerScriptService ▸ AntiCheat_UGCRestrict | Remplacer tout | `AntiCheat_UGCRestrict_SERVEUR.lua` |
| 4 | ServerScriptService ▸ time | Remplacer tout | `time_COMPLET.lua` |
| 5 | ServerScriptService ▸ Admin server | Remplacer tout | `Admin_server_COMPLET.lua` |
| 6 | ServerScriptService ▸ AdminAbuse_Server | Remplacer tout | `AdminAbuse_Server_COMPLET.lua` |
| 7 | StarterPlayerScripts ▸ UGCRestrictNotify | Remplacer tout | `UGCRestrictNotify_CLIENT.lua` |
| 8 | ServerStorage ▸ AdminClientScripts ▸ Admin_client | Remplacer tout | `Admin_client_COMPLET.lua` |
| 9 | ServerScriptService ▸ Tp finish obby shop | Cocher **Disabled** (faille : téléportation gratuite à la fin de l'obby) | — |
| 10 | Page du jeu | Publier, puis **Shut down all servers** | — |

Tous les fichiers sont faits à partir de ta version actual_version_1.0.

## Où régler quoi

**Un seul fichier contient TOUS les réglages : `ANTICHEAT_CONFIG`.**

| Section | Contenu | Aussi dans le panel ? |
|---|---|---|
| ① Activation | Mode (UGC / ban), mode test, analyser les admins | 🖥️ oui |
| ② Sanction | Warnings avant sanction, durée, messages, kick, dons, rebirth | 🖥️ oui |
| ③ Discrétion | Le joueur ne voit rien, durée de vie d'un warning, sanction montrée seulement à l'achat | 🖥️ oui |
| ④ Niveau de preuve | Seuils 55 / 70 / 85 % | 🖥️ oui |
| ⑤ Mode ban | Réglages du ban | 🖥️ oui |
| ⑥ Mode test | Réglages de l'observation | 🖥️ oui |
| ⑦ Messages | Tous les textes vus par le joueur | 🖥️ oui |
| ⑧ Admins | Qui a accès au panel anti-cheat, comptes jamais analysés | 📄 fichier seulement |
| ⑨ Détection | Sévérité, vol, téléport, vitesse, strikes, calcul de la certitude | 📄 fichier seulement |
| ⑩ Mouvements normaux du jeu | Outils, attributs, launchers, ragdoll, arène, PvP, tolérances, tapis roulants, tyrolienne | 📄 fichier seulement |

**La règle fichier ↔ panel :**
- Pour les sections 🖥️ ① à ⑦ :
  - un changement dans le **panel** s'applique tout de suite et reste actif ;
  - un changement dans le **fichier** demande de monter `VERSION` de 1 puis de publier. Au démarrage, le fichier écrase alors le panel.
- Pour les sections 📄 ⑧ à ⑩, il suffit de publier.
