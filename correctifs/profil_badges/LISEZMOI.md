# 🏅 Profil : badges VIP et boosts permanents

## Pourquoi ça ne marchait pas

La fiche profil ne regardait que les **gamepass**, et depuis le client. Les boosts permanents **offerts** (cadeau, admin, `_PermBoosts`) n'apparaissaient donc jamais. Ton propre profil (Settings ▸ PROFILE) n'avait aucun badge.

## Maintenant

- Le **serveur** calcule les badges :
  - 👑 VIP, acheté ou offert ;
  - ⚡ x2 / x5 / x10, achetés **ou** offerts.
- Il les publie sur chaque joueur, dans l'attribut `ProfileBadges`, et dans la fiche des joueurs hors ligne.
- Les badges se mettent à jour tout de suite après un achat, un boost offert ou un VIP donné / retiré.
- **Fiche d'un autre joueur** : les bons badges, qu'il soit sur ce serveur ou hors ligne.
- **Ton profil** (Settings ▸ PROFILE) : nouvelle rangée de badges sous ton nom (VIP, x2, x5, x10), ou « No VIP or permanent boost yet ».

## Installation (remplacer tout le contenu)

| # | Où | Fichier |
|---|---|---|
| 1 | ServerScriptService ▸ **PUBLIC PROFILE** | `PUBLIC_PROFILE_SERVEUR.lua` |
| 2 | StarterPlayer ▸ StarterPlayerScripts ▸ **PlayerProfileHover** | `PlayerProfileHover_COMPLET.lua` |
| 3 | StarterPlayer ▸ StarterPlayerScripts ▸ **SettingsUI** | `SettingsUI_COMPLET.lua` |
| 4 | Page du jeu | Publier, puis **Shut down all servers** |
