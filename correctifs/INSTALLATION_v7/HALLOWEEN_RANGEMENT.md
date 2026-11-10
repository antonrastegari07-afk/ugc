# 🎃 Ranger Halloween sans rien supprimer (la Scythe reste aux joueurs)

## À NE PAS TOUCHER (sinon les joueurs perdent leur Scythe)
- `ReplicatedStorage ▸ JackScythe ▸ SCYTHE_CONFIG` : laisse `C.Enabled = true`.
  (false = personne ne reçoit plus sa faux et le dash est coupé)
- Dossier `ServerScriptService ▸ JackScythe` (JackScytheService, JackScythe_Server) : laisse-le actif.
- `ServerStorage ▸ JackScythe` (les modèles de la faux) : laisse-le.
- `StarterPlayerScripts ▸ JackScythe_Client` : laisse-le.
- Ne supprime aucun DataStore : les numéros de série et les pass sont dedans.

## Étapes
1. `ReplicatedStorage ▸ HALLOWEEN_EVENT_CONFIG` → `C.Enabled = false`
   → le pass Halloween, ses quêtes, ses coins et sa fenêtre disparaissent pour TOUT LE MONDE
     (les testeurs aussi, tant que `C.TestMode.Enabled = false`).
2. `ServerScriptService ▸ JackQuest ▸ JACK_CONFIG` → `C.Enabled = false`
   → plus de quêtes de Jack.
3. Dans `ServerStorage`, crée un dossier `Halloween_Range` et GLISSE-Y depuis le Workspace
   (glisser = déplacer, rien n'est supprimé, tout est gardé tel quel) :
   - les 2 modèles `Jack Lantern`
   - `ShopHalloween` et `ShopHalloween1`
   - le dossier `HalloweenCoinZones`
   - le dossier `JackQuest_PageSpots`
   - le dossier `halloween` (les fantômes)
   - le dossier `HalloweenEventBoards` (les panneaux de l'event)
   - la déco trouvée dans ta version 11.0 : `Bat`, les 2 `pumpkin 2`, `Pumpkin Hat`
   - à vérifier toi-même (peut-être pas d'Halloween) : les 4 `Lantern` et les pierres tombales
     (`tombstone_cross`) qui sont dans un `Model` du Workspace
   - toute autre déco d'Halloween que tu as posée
   Ce qui est dans ServerStorage n'est envoyé à aucun joueur : invisible et zéro coût.
4. `StarterPlayer ▸ StarterPlayerScripts ▸ HalloweenGhosts` → coche la propriété `Enabled = false`
   (sinon il cherche le dossier des fantômes pour rien).
5. Admin panel → 🔔 What's new : dépublie l'annonce d'Halloween (si tu en as une).
6. Ciel : les ciels d'Halloween sont rangés dans `Lighting ▸ halloween` (dossier) — ils ne sont pas
   actifs, tu peux les laisser là. Ne touche pas à `Lighting ▸ day` / `night`.
7. Publie, puis **Shut down all servers**.

## Vérifier
- Un joueur qui avait la Scythe la retrouve dans son inventaire et peut toujours dasher.
- Plus de Jack, plus de bouton / fenêtre du pass, plus de coins dans la map.

## Pour réactiver plus tard
Ressors les objets de `ServerStorage ▸ Halloween_Range` vers le Workspace, remets les deux
`C.Enabled = true` (et les dates dans HALLOWEEN_EVENT_CONFIG), réactive HalloweenGhosts.
