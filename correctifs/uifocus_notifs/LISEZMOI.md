# UIFocus : les notifications ne sont plus cachées par les fenêtres

**Avant :** quand une fenêtre est ouverte (shop, settings, profil…), UIFocus éteignait **toutes** les autres interfaces, sauf 3 (CoinRewardGui, RobuxPromptFX, LoadingScreen). Les messages d'achat réussi, d'UGC, d'Halloween, de quêtes, de récompenses… étaient donc invisibles.

**Maintenant :** les notifications restent visibles et passent **au-dessus** de la fenêtre ouverte. 3 règles se cumulent :
1. **Liste de noms** (`C.NotificationScreenGuis`) ;
2. **Mots-clés dans le nom** (`C.NotificationNamePatterns`) : `notif`, `toast`, `popup`, `error`, `result`, `confirm`, `warning`, `notice`, `message`, `vote`, `countdown`… Les futures notifs bien nommées sont couvertes automatiquement ;
3. **Toute interface créée ou allumée PENDANT qu'une fenêtre est ouverte** : c'est forcément une réaction à ce que fait le joueur (achat, récompense, message…). Ça couvre aussi les notifs aux noms imprévus.

Ce qui ne change pas :
- Les autres interfaces (HUD, boutons, barre du haut, backpack…) sont toujours cachées.
- Les fenêtres du focus gardent leur priorité.
- À la fermeture, tout est remis exactement comme avant, ordre d'affichage (DisplayOrder) compris.

## Installation (2 scripts, remplacer TOUT)
1. **StarterGui ▸ UIFocusSystem ▸ FocusEngine** ← `FocusEngine_COMPLET.lua`
2. **StarterGui ▸ UIFocusSystem ▸ UI_FOCUS_CONFIG** ← `UI_FOCUS_CONFIG_COMPLET.lua`

## Interfaces du jeu vérifiées
J'ai vérifié toutes les ScreenGui du jeu : StarterGui, celles créées par les scripts client (134 trouvées) et celles créées côté serveur.

**Gardées (notifications) :**
- **Achats et shop :** UGCNotification, UGCVerifyingGui, UGCSalesFrozenGui, CoilToast, GamepassNotificationGui, DevProductNotificationGui, ErrorNotificationGui, BuyCancelNotificationGui, BoxBuyConfirm.
- **Halloween et events :** HalloweenEventToast, AdminAbuseGui.
- **Quêtes :** toutes les notifs de quêtes (Quest…Notif, HuntQuestNotif, EggToast, NoDeathNotif, LikeGamePopupGui, DiscordQuestNotifGui…).
- **Récompenses :** PointsNotificationGui, PlaytimeNotifGui, DailyRewardNotification, StreakClaimNotif, AdRewardNotificationGui, ReferralRewardGui, ReferralNotifGui, CoinRewardGui.
- **Messages divers :** CodeResultGui, RebirthCooldownGui, AlreadyCollectedPopup, CheckpointNotifications, GroupMessageGui, DonationNotification(Gui), UGCRestrictedGui, AntiFlyTPGui, WarningNotificationGui, SettingsToast, LeavePopupGui.
- **Tutoriel et dialogues :** TutorialGui / TutorialOverlayGui / TutorialPopupGui, NpcDialogGui.
- **PvP :** MapVoteGui, MapCountdownGui, MapIntermissionGui, ZoneNotifGui, ArenaKillFeed, KillConfirm, KillFX / Headshot / HitDirection, DeathCam…, ServerBrowserOverlay, ArenaBotsNotice.
- **Hideout et quête de Jack :** HideoutTeleportFade, JackSubtitles, JackFlash.

**Toujours cachées (HUD) :** Music Player, # Stage, 1v1button, Bouton hide, Daily tool, invites, dailyspin, VIP offer, Skip Obby / Skip Level, ShiftLockButton, Servers, Reward_ads, TopBarGui, CustomBackpack, CombatHUD, ArenaHUD, TempBoostsHUD, HalloweenCoinsHUD, PerfHud, les HUD d'armes mobiles, etc.

## Ajouter une exception
- Une interface qui doit rester visible : ajoute son nom dans `C.NotificationScreenGuis`.
- Une interface qui ne doit **pas** l'être alors qu'elle contient un mot-clé : renomme-la, ou retire le mot de `C.NotificationNamePatterns`.

## Tests en Play
1. Ouvre le shop UGC et achète : le message vert « purchase successful » s'affiche par-dessus le shop.
2. Ouvre le shop de points et achète : la notification s'affiche.
3. Pendant l'event Halloween, ouvre un shop : les messages Halloween s'affichent.
4. Ferme le shop : toutes tes interfaces reviennent comme avant.
