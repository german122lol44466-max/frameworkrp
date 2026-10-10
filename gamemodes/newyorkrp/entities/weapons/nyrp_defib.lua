--[[
	Дефибриллятор (EMS). ЛКМ по телу:
	  без сознания в критическом состоянии — привести в чувство;
	  умер не больше 30 секунд назад — реанимация (шанс растёт с навыком «Медицина»).
]]

AddCSLuaFile()

SWEP.Base = "nyrp_handheld"
SWEP.PrintName = "Дефибриллятор"
SWEP.Instructions = "ЛКМ по телу — разряд"
SWEP.Slot = 0
SWEP.SlotPos = 7
SWEP.ViewModel = "models/nyrp/city/v_defib.mdl"
SWEP.WorldModel = "models/nyrp/city/defib.mdl"
SWEP.HoldType = "slam"
SWEP.WMOffset = { pos = Vector(0, 0, -10.6), ang = Angle(0, 90, 0) }

function SWEP:PrimaryAttack()
	self:SetNextPrimaryFire(CurTime() + 2)
	if CLIENT then return end
	local ply = self:GetOwner()
	local tr = util.TraceLine({ start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * 100, filter = ply })
	local rag = tr.Entity
	if not IsValid(rag) or rag:GetClass() ~= "prop_ragdoll" then return end
	local ko = rag:GetNW2Entity("nyrp.koOwner")
	local dead = rag:GetNW2Bool("nyrp.corpse")
	if not dead and not IsValid(ko) then return end
	if dead and CurTime() - rag:GetNW2Float("nyrp.corpseTime", 0) > 30 then
		NYRP.Notify(ply, "Слишком поздно — реанимация уже не поможет", "error")
		return
	end
	self:PlaySeq("use")
	ply:EmitSound("buttons/blip1.wav", 55, 80)
	NYRP.Action(ply, "Заряжаю дефибриллятор...", 3, function()
		if not IsValid(rag) or rag:GetPos():Distance(ply:GetPos()) > 140 then return end
		rag:EmitSound("ambient/energy/zap" .. math.random(1, 3) .. ".wav", 70)
		for i = 0, rag:GetPhysicsObjectCount() - 1 do
			local ph = rag:GetPhysicsObjectNum(i)
			if IsValid(ph) then ph:ApplyForceCenter(Vector(0, 0, 1200) * ph:GetMass() / 10) end
		end
		local SK = NYRP.Skills
		local lvl = SK and SK.Level and SK.Level(ply, "medicine") or 0
		if IsValid(ko) and not dead then
			NYRP.Cond.WakeUp(ko, 30)
			NYRP.Notify(ply, "Пострадавший пришёл в себя", "success")
			if SK and SK.AddXP then SK.AddXP(ply, "medicine", 20, "дефибриллятор") end
			return
		end
		local chance = math.min(0.9, 0.35 + lvl * 0.06 + (ply:GetNW2String("nyrp.role", "") == "medic" and 0.15 or 0))
		if math.random() < chance and NYRP.Factions.Revive(ply, rag) then
			NYRP.Notify(ply, "Сердце запустилось! Человек жив", "success")
			if SK and SK.AddXP then SK.AddXP(ply, "medicine", 50, "реанимация") end
		else
			NYRP.Notify(ply, "Не удалось. Попробуйте ещё разряд", "warning")
			if SK and SK.AddXP then SK.AddXP(ply, "medicine", 5) end
		end
	end, "heart")
end
