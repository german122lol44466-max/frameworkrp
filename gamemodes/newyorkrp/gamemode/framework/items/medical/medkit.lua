ITEM.Name = "Аптечка"
ITEM.Description = "Бинты, антисептик и обезболивающее. Поможет продержаться до больницы."
ITEM.Model = "models/items/healthkit.mdl"
ITEM.Stack = 2
ITEM.Health = 40
ITEM.UseSound = "items/medshot4.wav"
ITEM.Treats = { head = true, body = true, arm = true, leg = true }   -- в меню состояния (J) — на любую часть тела
ITEM.Skill = 0
ITEM.TreatTime = 6
ITEM.Difficulty = 0.05
ITEM.Buffs = { { "+40 к здоровью", true }, { "Шина на перелом, снимает ушиб и кровотечение", true } }
-- можно и при полном здоровье, если есть травма
ITEM.OnUse = function(ply)
	local Cond = NYRP.Cond
	local hurt = Cond and (Cond.Until(ply, "fracture") > 0 or Cond.Until(ply, "bruise") > 0 or ply:GetNW2Bool("nyrp.bleeding")
		or (Cond.HasWound and Cond.HasWound(ply)))
	if ply:Health() >= ply:GetMaxHealth() and not hurt then NYRP.Notify(ply, "Вы и так здоровы", "warning") return false end
	ply:SetHealth(math.min(ply:GetMaxHealth(), ply:Health() + 40))
	ply:EmitSound("items/medshot4.wav", 60)
	hook.Run("NYRP.ItemUsed", ply, "medkit")
	return true
end
