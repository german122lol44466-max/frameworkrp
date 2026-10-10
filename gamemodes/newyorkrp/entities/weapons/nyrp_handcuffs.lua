--[[
	Наручники. ЛКМ по человеку — надеть (2.5 с), ЛКМ по задержанному — вести за собой / отпустить,
	ПКМ по задержанному — снять наручники.
]]

AddCSLuaFile()

SWEP.Base = "nyrp_handheld"
SWEP.PrintName = "Наручники"
SWEP.Instructions = "ЛКМ — надеть / вести, ПКМ — снять"
SWEP.Slot = 0
SWEP.SlotPos = 6
SWEP.ViewModel = "models/nyrp/city/v_handcuffs.mdl"
SWEP.WorldModel = "models/nyrp/city/handcuffs.mdl"
SWEP.HoldType = "slam"
SWEP.WMOffset = { pos = Vector(0.5, 0, 0), ang = Angle(0, 90, 0) }

local function target(ply)
	local tr = util.TraceLine({ start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * 90, filter = ply })
	local e = tr.Entity
	if IsValid(e) and e:IsPlayer() and e:Alive() then return e end
end

function SWEP:PrimaryAttack()
	self:SetNextPrimaryFire(CurTime() + 1)
	if CLIENT then return end
	local ply = self:GetOwner()
	local t = target(ply)
	if not t then return end
	local F = NYRP.Factions
	if F.Cuffed(t) then
		if t.nyrpDraggedBy == ply then
			t.nyrpDraggedBy = nil
			NYRP.Notify(ply, "Вы отпустили задержанного", "info")
		else
			t.nyrpDraggedBy = ply
			NYRP.Notify(ply, "Вы ведёте задержанного. ЛКМ — отпустить", "info")
		end
		return
	end
	self:PlaySeq("use")
	NYRP.Action(ply, "Надеваю наручники...", 2.5, function()
		if not IsValid(t) or not t:Alive() or t:GetPos():Distance(ply:GetPos()) > 110 then
			NYRP.Notify(ply, "Не получилось — человек отошёл", "warning")
			return
		end
		F.Cuff(ply, t, true)
		NYRP.Notify(ply, "Наручники надеты. ЛКМ — вести, ПКМ — снять", "success")
	end, "lock")
end

function SWEP:SecondaryAttack()
	self:SetNextSecondaryFire(CurTime() + 1)
	if CLIENT then return end
	local ply = self:GetOwner()
	local t = target(ply)
	if not t or not NYRP.Factions.Cuffed(t) then return end
	self:PlaySeq("use")
	NYRP.Action(ply, "Снимаю наручники...", 2, function()
		if IsValid(t) and t:GetPos():Distance(ply:GetPos()) < 110 then NYRP.Factions.Cuff(ply, t, false) end
	end, "unlock")
end
