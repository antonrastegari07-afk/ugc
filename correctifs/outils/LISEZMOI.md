# 🧰 Outils : dons, PvP, inventaire (correctifs)

| Script | Problème | Correction |
|---|---|---|
| tp1v1 new gestion (arène) | À l'entrée, les outils étaient détruits puis recréés depuis ServerStorage à la sortie. Les outils rangés ailleurs (Admin Abuse, Halloween, quête Noob) et les attributs (prêts, sessions) étaient perdus. Un outil reçu pendant le PvP (gamepass au respawn, Daily, prêt) arrivait au milieu des armes puis était détruit. | Les vrais outils sont mis de côté puis rendus tels quels. Tout outil non-PvP reçu pendant l'arène est mis de côté aussi. À la sortie : pas de doublon, pas de prêt expiré, pas d'outil d'un Admin Abuse terminé. Si l'entrée échoue, les outils sont rendus tout de suite. |
| 7 scripts de gamepass | Retirer le VIP retirait aussi l'outil payé avec un autre gamepass (Slap Hand, Coil Pack). Un doublon était possible si l'outil était en main. Les outils étaient redonnés en pleine arène. | Un seul script, `GamepassTools`. Les 7 anciens sont à désactiver. |
| CustomBackpack | La case d'une arme était perdue en changeant de skin. La Scythe changeait de case à chaque serveur. | Les skins gardent la case de l'arme ; la Scythe a toujours la même case. |
| remove and regive tools during tutoriel | Un tutoriel relancé écrasait la sauvegarde : les outils étaient perdus. | La sauvegarde est complétée au lieu d'être écrasée. |
| leave_popup | FusionCoil en double si elle était en main. | Vérifie aussi la main. |
| DAILY_TOOLs | Copie en double si l'outil était déjà là (gamepass, en main). | Vérifie le sac et la main. |
