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

## Panel admin : un seul écran « 🛡️ ANTI-CHEAT »

Les anciens boutons « 🚫 UGC BAN » et « ⚙️ MODES & MSG » disparaissent de l'accueil du panel. Tout est dans **🛡️ ANTI-CHEAT** :

| Onglet | Contenu |
|---|---|
| 🏠 Accueil | L'état (actif ou mode test), le **nombre de warnings avant la restriction** modifiable en direct, les chiffres des 24 dernières heures, les derniers événements, le mode d'emploi |
| 📡 Fil récent | Tout ce qui s'est passé, tous serveurs confondus. Chaque entrée explique : ce qu'il a fait, où (position), avec quoi (outil, vitesse, arène), pourquoi la machine y croit (certitude et facteurs), son dossier (warnings / seuil, détections sur 24 h, points, restreint ou non) et les boutons Fiche / Restreindre / Lever / Remise à zéro. Filtres : type d'événement, type de triche, certitude, en ligne, masquer les restreints, recherche |
| 👥 Joueurs | Tous les suspects, avec 12 tris : dernière détection, proches de la sanction, warnings, certitude moyenne et max, détections totales et sur 24 h, points / UGC finançables, risque, bruit (signaux écartés), nouveaux suspects, nom. Filtres : type de triche, restreints ou non, en ligne, recherche |
| 🚫 Restreints | Tous les sanctionnés, avec la raison exacte. 6 tris et une recherche |
| 🔍 Fiche | Tout sur un joueur : warnings actifs, historique expliqué, ce que la machine a vu, sanction, actions |
| ⚙️ Réglages | **Absolument tous les réglages** (173), en 17 sections repliables, avec « ⭐ L'ESSENTIEL » en premier. Recherche, valeurs modifiées en jaune, bouton « ↺ valeur du fichier », enregistrement avec page récapitulative |

Toute action importante (restreindre, lever, remise à zéro, enregistrer, passer en mode test) ouvre une **page de confirmation**. Elle explique ce qui va se passer, et le bouton ne s'active qu'au bout de 2 secondes.
