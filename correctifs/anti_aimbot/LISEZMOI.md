# Anti-aimbot (AimGuard) — détection SANS changer le gameplay

## Pourquoi tes tricheurs passaient
Le **HitValidator** vérifie déjà chaque balle : le point touché était sur le corps, pas de mur, le canon près du tireur. Il bloque les balles « magiques ». Mais un **aimbot** vise à ta place avec une vraie visée : ses tirs sont **valides** un par un. On ne peut donc l'attraper qu'avec ses **statistiques**. Il touche presque tout, et presque toujours la tête, même de loin.

## Ce que fait AimGuard
Il **observe seulement** ce que le serveur reçoit déjà (chaque tir + chaque touche validée). Il ne change ni les dégâts, ni la visée, ni le recul, ni la cadence. **Le gameplay est strictement identique.**

Sur les 3 dernières minutes de combat d'un joueur, **par classe d'arme** :

| Classe | Armes | Aimbot si précision ≥ | ET headshots à distance ≥ | « Head lock » si headshots ≥ |
|---|---|---|---|---|
| auto | AK, Scar, AutoPistol, Minigun | 85 % | 60 % | 85 % (25 touches) |
| semi | Deagle, Magnum | 90 % | 70 % | 90 % (25 touches) |
| sniper | Sniper | 95 % | 80 % | 92 % (30 touches) |

- Il faut au moins **40 tirs** et **15 touches sur de VRAIS joueurs à ≥ 25 studs**. De près, tout le monde touche, donc ces touches-là ne comptent pas dans les %.
- **Shotgun, RPG et Bazooka sont ignorés** : plusieurs plombs par tir, ou explosion.
- **Bonus :** plus de touches que de tirs = dégâts envoyés sans tirer (triche réseau).

**Sanction :** `AntiExploit.HandleSuspiciousActivity`, ton anti-cheat existant. Le joueur est averti et une infraction est comptée. Il est banni au seuil habituel (5). Une détection au plus toutes les 150 s, chaque fois sur de **nouveaux** tirs. Tes développeurs sont ignorés, comme pour le reste. Tout est écrit dans l'Output avec les chiffres.

**Testé en simulation (10 min de combat, 3 tirages chacun) :**
- **Jamais détectés :** bon joueur AK (45 % / 30 % tête), très bon joueur AK (60 % / 45 %), sniper fort (80 % / 55 %), sniper pro (85 % / 70 %), très bon Deagle (75 % / 55 %).
- **Toujours détectés :** aimbot AK (97 % / 95 %), aimbot « discret » (88 % / 65 %), aimbot tête seulement (60 % / 95 %), aimbot sniper (100 % / 98 %).

## Installation
1. **ServerScriptService ▸ CombatSystem** : nouveau **ModuleScript** `AimGuard` ← `AimGuard.lua`.
2. **ReplicatedStorage ▸ WeaponSystem ▸ WeaponServer** : remplace **tout** par `WeaponServer_COMPLET.lua`. C'est seulement 3 ajouts : charger AimGuard, lui signaler chaque tir, lui signaler chaque touche validée.

## Réglages / console
- Tout est dans `CONFIG`, en haut d'AimGuard.
  - `Action = "log"` : seulement l'Output, pas d'avertissement ni d'infraction. Utile pour observer quelques jours avant d'activer.
  - `Enabled = false` : coupe tout.
- Console serveur (F9 ▸ Server) : `_G.AimStats("pseudo")` affiche les chiffres actuels d'un joueur.
