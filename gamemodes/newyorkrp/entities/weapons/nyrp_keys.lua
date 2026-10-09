--[[
	Ключи от квартиры (слот «Холодное»). ЛКМ, глядя на свою дверь (арендатор или жилец), — запереть,
	ещё раз ЛКМ — отпереть. Действие с прогресс-баром и анимацией поворота ключа.
	Ключи выдаёт почтовый ящик дома (entities/entities/nyrp_mailbox.lua) после аренды.
]]

AddCSLuaFile()

SWEP.Base = "nyrp_handheld"
SWEP.PrintName = "Ключи"
SWEP.Instructions = "ЛКМ по своей двери — запереть / отпереть"
SWEP.Slot = 0
SWEP.SlotPos = 3
SWEP.ViewModel = "models/nyrp/props/v_keys.mdl"
SWEP.WorldModel = "models/nyrp/props/w_keys.mdl"
SWEP.HoldType = "slam"
SWEP.WMOffset = { pos = Vector(0.2, 0, -1.2), ang = Angle(0, 90, 0) }   -- брелок в кулаке, ключи свисают

local RANGE = 90

function SWEP:PrimaryAttack()
	self:SetNextPrimaryFire(CurTime() + 0.6)
	if CLIENT or self.HolsterAt then return end
	local ply = self:GetOwner()
	local D = NYRP.Doors
	local tr = ply:GetEyeTrace()
	local door, id = tr.Entity, D and D.IdOf and D.IdOf(tr.Entity)
	if not id or tr.HitPos:Distance(ply:EyePos()) > RANGE then
		NYRP.Notify(ply, "Подойдите к двери вплотную", "warning", 2)
		return
	end
	if not D.HasAccess(ply, id) then
		ply:EmitSound("doors/handle_pushbar_locked1.wav", 55)
		NYRP.Notify(ply, "Ключ не подходит к этой двери", "error", 3)
		return
	end
	local lock = not D.IsLocked(id)
	self:PlaySeq("use")
	ply:EmitSound("nyrp/fx/keys.wav", 55, math.random(95, 105))
	NYRP.Action(ply, lock and "Запираю дверь..." or "Отпираю дверь...", 1.3, function()
		if not IsValid(door) or not IsValid(self) or ply:GetActiveWeapon() ~= self then return end
		if ply:EyePos():Distance(door:NearestPoint(ply:EyePos())) > RANGE + 20 then return end
		D.SetLocked(ply, id, lock)
	end, lock and "lock" or "unlock")
	self:SetNextPrimaryFire(CurTime() + 1.4)
end

function SWEP:SecondaryAttack() end
