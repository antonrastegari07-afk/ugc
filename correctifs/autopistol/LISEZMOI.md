# 🔫 AutoPistol : perso bloqué + animation buggée au retrait du chargeur

Cause : dans ServerStorage ▸ AutoPistol ▸ Part, le chargeur `mag` porte 3 soudures « BTWeld »
vers `gun`, `cock` et `cock ▸ 3.5`. Le moteur d'animation (WeaponFX2.PartsIndex) considère tout ce
que le chargeur tient comme SES décorations : le corps de l'arme suit donc le chargeur. Quand le
chargeur est décroché (soudé à un repère ANCRÉ), toute l'arme — et le personnage qui la tient — est
accrochée à ce repère immobile → blocage d'une fraction de seconde + animation qui part en vrille.
Seule l'AutoPistol a ce montage.

Correction (Studio, ServerStorage ▸ AutoPistol ▸ Part) :
1. `mag` : supprimer les 3 `BTWeld`.
2. `cock` : supprimer les Welds `1` et `2`.
3. `gun` : ajouter un WeldConstraint, Part0 = AutoPistol ▸ Handle, Part1 = gun.
4. `cock ▸ 3.5` : ajouter un WeldConstraint, Part0 = cock, Part1 = 3.5.
