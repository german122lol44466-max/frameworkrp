--[[
	Основа для предметов в правой руке (ключи, рация, зажигалка): вьюмодель v_<предмет> с руками c_arms,
	последовательности draw → idle, use (действие), holster (убрать, потом смена оружия).
	Камера «с телом» рисует самого игрока (drawviewer), движок тогда не рисует вьюмодель —
	рисуем её сами (как у телефона). От третьего лица предмет лежит в правой ладони.

	Наследник задаёт: SWEP.ViewModel, SWEP.WorldModel, SWEP.WMOffset = { pos = Vector, ang = Angle } (от кости кисти),
	SWEP.IdleAfter = { use = "idle" | "idle_use" } и свои PrimaryAttack/SecondaryAttack.
]]

AddCSLuaFile()

SWEP.PrintName = "Предмет"
SWEP.Author = "NYRP"
SWEP.Spawnable = false
SWEP.Slot = 0
SWEP.SlotPos = 5
SWEP.ViewModelFOV = 62
SWEP.UseHands = true
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = false
SWEP.HoldType = "slam"
SWEP.NYRPHandheld = true
-- от третьего лица: позиция от кисти, поворот — от направления корпуса (x — вперёд, y — влево, z — вверх)
SWEP.WMOffset = { pos = Vector(1, 0, 0), ang = Angle(0, 0, 0) }
SWEP.LoopSeqs = { idle = true, idle_use = true }
SWEP.NextSeq = { draw = "idle", use = "idle", unuse = "idle" }

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

local HOLSTER_TIME = 0.5

function SWEP:Initialize()
	self:SetHoldType(self.HoldType)
end

function SWEP:PlaySeq(name, rate)
	local owner = self:GetOwner()
	if not IsValid(owner) then return end
	local vm = owner:GetViewModel()
	if not IsValid(vm) then return end
	local seq = vm:LookupSequence(name)
	if seq < 0 then return end
	vm:SendViewModelMatchingSequence(seq)
	vm:SetPlaybackRate(rate or 1)
	self.SeqName = name
	self.SeqEnd = CurTime() + vm:SequenceDuration(seq) / (rate or 1)
	return vm:SequenceDuration(seq) / (rate or 1)
end

function SWEP:Deploy()
	self.HolsterAt, self.HolsterTo, self.HolsterDone = nil, nil, nil
	self:PlaySeq("draw")
	self:SetNextPrimaryFire(CurTime() + 0.5)
	self:SetNextSecondaryFire(CurTime() + 0.5)
	if self.OnDeploy then self:OnDeploy() end
	return true
end

function SWEP:PrimaryAttack() end
function SWEP:SecondaryAttack() end
function SWEP:Reload() end

function SWEP:Think()
	if self.SeqEnd and CurTime() >= self.SeqEnd then
		self.SeqEnd = nil
		local nxt = self.NextSeq[self.SeqName]
		if nxt then self:PlaySeq(nxt) end
	end
	if self.HolsterAt and CurTime() >= self.HolsterAt then
		local to = self.HolsterTo
		self.HolsterAt, self.HolsterTo = nil, nil
		self.HolsterDone = true
		if IsValid(to) then
			if SERVER then self:GetOwner():SelectWeapon(to:GetClass()) else input.SelectWeapon(to) end
		end
	end
	if self.OnThink then self:OnThink() end
end

function SWEP:Holster(wep)
	if self.HolsterDone or not IsValid(wep) or wep == self then
		self.HolsterDone = nil
		if self.OnHolster then self:OnHolster() end
		return true
	end
	if not self.HolsterAt then
		self.HolsterTo = wep
		self.HolsterAt = CurTime() + HOLSTER_TIME
		self:PlaySeq("holster")
		if self.OnHolster then self:OnHolster() end
	else
		self.HolsterTo = wep
	end
	return false
end

if CLIENT then
	local VM_FOV = 62
	local fpVM, fpHands, fpModel
	local seqId, seqStart = -1, 0

	local function cleanup()
		if IsValid(fpHands) then fpHands:Remove() end
		if IsValid(fpVM) then fpVM:Remove() end
		fpHands, fpVM, fpModel = nil, nil, nil
	end

	local function ensure(model)
		if IsValid(fpVM) and fpModel ~= model then cleanup() end
		if not IsValid(fpVM) then
			fpVM = ClientsideModel(model, RENDERGROUP_OPAQUE)
			if not IsValid(fpVM) then return end
			fpModel = model
			fpVM:SetNoDraw(true)
			fpVM.RenderOverride = function(e) if e.nyrpDraw then e:DrawModel() end end
		end
		local hands = LocalPlayer():GetHands()
		local mdl = IsValid(hands) and hands:GetModel() or ""
		if mdl == "" then mdl = "models/weapons/c_arms_citizen.mdl" end
		if not IsValid(fpHands) or fpHands:GetModel() ~= mdl then
			if IsValid(fpHands) then fpHands:Remove() end
			fpHands = ClientsideModel(mdl, RENDERGROUP_OPAQUE)
			if not IsValid(fpHands) then return end
			fpHands:SetNoDraw(true)
			fpHands.RenderOverride = function(e) if e.nyrpDraw then e:DrawModel() end end
			fpHands:SetParent(fpVM)
			fpHands:AddEffects(EF_BONEMERGE)
		end
		if IsValid(hands) then
			fpHands:SetSkin(hands:GetSkin())
			for i = 0, hands:GetNumBodyGroups() - 1 do fpHands:SetBodygroup(i, hands:GetBodygroup(i)) end
		end
		return fpVM, fpHands
	end

	local function light(eye, dir)
		local c = render.ComputeLighting(eye, dir) + render.ComputeDynamicLighting(eye, dir)
		return math.Clamp(c.x + 0.15, 0, 1.4), math.Clamp(c.y + 0.15, 0, 1.4), math.Clamp(c.z + 0.17, 0, 1.4)
	end

	hook.Add("HUDPaintBackground", "nyrp.handheld.vm", function()
		local ply = LocalPlayer()
		local wep = IsValid(ply) and ply:GetActiveWeapon()
		local Cam = NYRP.Camera
		local bodyCam = Cam and Cam.BodyEnabled and Cam.BodyEnabled() and not Cam.IsThirdPerson()
		if not ply:Alive() or not bodyCam or not IsValid(wep) or not wep.NYRPHandheld then
			if IsValid(fpVM) then cleanup() end
			return
		end
		local real = ply:GetViewModel()
		local vm, hands = ensure(wep.ViewModel)
		if not IsValid(vm) or not IsValid(hands) or not IsValid(real) then return end
		local seq = real:GetSequence()
		if seq ~= seqId then seqId, seqStart = seq, RealTime() end
		if vm:GetSequence() ~= seq then vm:ResetSequence(seq) end
		local dur = math.max(vm:SequenceDuration(seq), 0.01)
		local t = (RealTime() - seqStart) / dur
		local loop = wep.LoopSeqs[vm:GetSequenceName(seq)]
		vm:SetPlaybackRate(0)
		vm:SetCycle(loop and t % 1 or math.Clamp(t, 0, 0.999))

		local eye, view = EyePos(), EyeAngles()
		local spd = math.min(ply:GetVelocity():Length2D() / 200, 1)
		local bob = Angle(math.sin(RealTime() * 9) * 0.6 * spd, math.cos(RealTime() * 4.5) * 0.5 * spd, 0)
		vm:SetPos(eye)
		vm:SetAngles(view + bob)
		vm:InvalidateBoneCache()
		vm:SetupBones()
		hands:InvalidateBoneCache()
		hands:SetupBones()

		cam.Start3D(eye, view, VM_FOV, nil, nil, nil, nil, 1, 300)
		render.ClearDepth()
		render.SuppressEngineLighting(true)
		render.SetModelLighting(BOX_TOP, light(eye, Vector(0, 0, 1)))
		render.SetModelLighting(BOX_BOTTOM, light(eye, Vector(0, 0, -1)))
		render.SetModelLighting(BOX_FRONT, light(eye, view:Forward()))
		render.SetModelLighting(BOX_BACK, light(eye, -view:Forward()))
		render.SetModelLighting(BOX_LEFT, light(eye, -view:Right()))
		render.SetModelLighting(BOX_RIGHT, light(eye, view:Right()))
		vm.nyrpDraw, hands.nyrpDraw = true, true
		vm:DrawModel()
		hands:DrawModel()
		vm.nyrpDraw, hands.nyrpDraw = false, false
		render.SuppressEngineLighting(false)
		if wep.DrawFPExtra then wep:DrawFPExtra(vm) end
		cam.End3D()
	end)

	-- от третьего лица — в правой ладони (смещение задаёт наследник)
	function SWEP:DrawWorldModel()
		local owner = self:GetOwner()
		if not IsValid(owner) then self:DrawModel() return end
		if owner == LocalPlayer() and not (NYRP.Camera and NYRP.Camera.IsThirdPerson and NYRP.Camera.IsThirdPerson()) then return end
		local bone = owner:LookupBone("ValveBiped.Bip01_R_Hand")
		local m = bone and owner:GetBoneMatrix(bone)
		if not m then return end
		-- кость кисти у разных моделей и поз повёрнута по-разному (предметы ложились горизонтально),
		-- поэтому ориентация берётся от корпуса, а от кисти — только положение
		local body = Angle(0, owner:GetRenderAngles().y, 0)
		local pos, ang = LocalToWorld(self.WMOffset.pos, self.WMOffset.ang, m:GetTranslation(), body)
		self:SetRenderOrigin(pos)
		self:SetRenderAngles(ang)
		self:SetupBones()
		self:DrawModel()
		self:SetRenderOrigin()
		self:SetRenderAngles()
	end

	function SWEP:DrawHUD() end
end
