--[[
	Смартфон в руке. Вьюмодель v_phone (руки c_arms по бонмерджу): draw → idle,
	ЛКМ — поднести к лицу и открыть интерфейс (open → idle_open), ПКМ — закрыть (close → idle),
	при смене оружия — holster (телефон опускается и уходит из кадра), только потом переключение.
	Интерфейс — modules/phone/cl_phone*.lua.
]]

AddCSLuaFile()

SWEP.PrintName = "Телефон"
SWEP.Author = "NYRP"
SWEP.Instructions = "ЛКМ — открыть, ПКМ — закрыть"
SWEP.Slot = 4
SWEP.SlotPos = 1
SWEP.Spawnable = false
SWEP.ViewModel = "models/nyrp/phone/v_phone.mdl"
SWEP.WorldModel = "models/nyrp/phone/w_phone.mdl"
SWEP.ViewModelFOV = 62
SWEP.UseHands = true
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = false
SWEP.HoldType = "slam"

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

local HOLSTER_TIME = 0.5

function SWEP:SetupDataTables()
	self:NetworkVar("Bool", 0, "Raised")
end

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
end

function SWEP:Deploy()
	self.HolsterAt, self.HolsterTo, self.HolsterDone = nil, nil, nil
	self:SetRaised(false)
	self:PlaySeq("draw")
	self:SetNextPrimaryFire(CurTime() + 0.4)
	if SERVER then self:GetOwner():EmitSound("nyrp/fx/cloth_off.wav", 45, 130, 0.5) end
	return true
end

function SWEP:Raise(up)
	if self:GetRaised() == up then return end
	self:SetRaised(up)
	self:PlaySeq(up and "open" or "close")
end

function SWEP:PrimaryAttack()
	self:SetNextPrimaryFire(CurTime() + 0.3)
	if self.HolsterAt then return end
	-- без SIM-карты телефон не активирован — экран не открывается
	if SERVER and not (NYRP.Phone and NYRP.Phone.Number(self:GetOwner())) then return end
	if CLIENT and IsFirstTimePredicted() and NYRP.Phone and NYRP.Phone.OpenUI then
		if not NYRP.Phone.OpenUI() then return end
	end
	self:Raise(true)
end

function SWEP:SecondaryAttack()
	self:SetNextSecondaryFire(CurTime() + 0.3)
	if CLIENT and IsFirstTimePredicted() and NYRP.Phone and NYRP.Phone.CloseUI then NYRP.Phone.CloseUI(true) end
	self:Raise(false)
end

function SWEP:Reload() end

function SWEP:Think()
	-- переходы в зацикленные позы
	if self.SeqEnd and CurTime() >= self.SeqEnd then
		self.SeqEnd = nil
		if self.SeqName == "draw" or self.SeqName == "close" then self:PlaySeq("idle")
		elseif self.SeqName == "open" then self:PlaySeq("idle_open") end
	end
	if self.HolsterAt and CurTime() >= self.HolsterAt then
		local to = self.HolsterTo
		self.HolsterAt, self.HolsterTo = nil, nil
		self.HolsterDone = true
		if IsValid(to) then
			if SERVER then self:GetOwner():SelectWeapon(to:GetClass()) else input.SelectWeapon(to) end
		end
	end
end

function SWEP:Holster(wep)
	if self.HolsterDone or not IsValid(wep) or wep == self then
		self.HolsterDone = nil
		if CLIENT and NYRP.Phone and NYRP.Phone.CloseUI then NYRP.Phone.CloseUI(true) end
		return true
	end
	if not self.HolsterAt then
		self.HolsterTo = wep
		self.HolsterAt = CurTime() + HOLSTER_TIME
		self:SetRaised(false)
		self:PlaySeq("holster")
		if CLIENT and NYRP.Phone and NYRP.Phone.CloseUI then NYRP.Phone.CloseUI(true) end
	else
		self.HolsterTo = wep
	end
	return false
end

function SWEP:OnRemove()
	if CLIENT and NYRP.Phone and NYRP.Phone.CloseUI and IsValid(self:GetOwner()) and self:GetOwner() == LocalPlayer() then
		NYRP.Phone.CloseUI(true)
	end
end

if SERVER then
	concommand.Add("nyrp_phone_raise", function(ply, _, args)
		local w = IsValid(ply) and ply:GetActiveWeapon()
		if IsValid(w) and w:GetClass() == "nyrp_phone" and not w.HolsterAt then w:Raise(args[1] == "1") end
	end)
end

if CLIENT then
	-- Камера «с телом» рисует самого игрока (drawviewer), и тогда движок не рисует вьюмодель.
	-- Поэтому руки с телефоном рисуем сами: своя копия v_phone + руки игрока по бонмерджу,
	-- анимация — та же последовательность, что у настоящей вьюмодели (её шлёт сервер).
	local VM_FOV = 62
	local fpVM, fpHands
	local seqId, seqStart = -1, 0

	local function cleanup()
		if IsValid(fpHands) then fpHands:Remove() end
		if IsValid(fpVM) then fpVM:Remove() end
		fpHands, fpVM = nil, nil
	end

	local function ensure()
		if not IsValid(fpVM) then
			fpVM = ClientsideModel("models/nyrp/phone/v_phone.mdl", RENDERGROUP_OPAQUE)
			if not IsValid(fpVM) then return end
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

	hook.Add("HUDPaintBackground", "nyrp.phone.vm", function()
		local ply = LocalPlayer()
		local wep = IsValid(ply) and ply:GetActiveWeapon()
		local Cam = NYRP.Camera
		-- рисуем сами только в камере «с телом» (иначе вьюмодель рисует движок)
		local bodyCam = Cam and Cam.BodyEnabled and Cam.BodyEnabled() and not Cam.IsThirdPerson()
		if not ply:Alive() or not bodyCam or not IsValid(wep) or wep:GetClass() ~= "nyrp_phone" then
			if IsValid(fpVM) then cleanup() end
			return
		end
		local real = ply:GetViewModel()
		local vm, hands = ensure()
		if not IsValid(vm) or not IsValid(hands) or not IsValid(real) then return end
		-- последовательность берём у настоящей вьюмодели, время считаем сами
		local seq = real:GetSequence()
		if seq ~= seqId then seqId, seqStart = seq, RealTime() end
		if vm:GetSequence() ~= seq then vm:ResetSequence(seq) end
		local dur = math.max(vm:SequenceDuration(seq), 0.01)
		local t = (RealTime() - seqStart) / dur
		local name = vm:GetSequenceName(seq)
		local loop = name == "idle" or name == "idle_open"
		vm:SetPlaybackRate(0)
		vm:SetCycle(loop and t % 1 or math.Clamp(t, 0, 0.999))

		local eye, view = EyePos(), EyeAngles()
		-- лёгкое покачивание при ходьбе
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
		cam.End3D()
	end)

	-- от третьего лица телефон лежит в правой ладони экраном к лицу.
	-- Кость кисти ValveBiped: X — вдоль пальцев, -Y — сторона ладони.
	function SWEP:DrawWorldModel()
		local owner = self:GetOwner()
		if not IsValid(owner) then self:DrawModel() return end
		-- свой телефон в первом лице не рисуем — его показывают руки на экране
		if owner == LocalPlayer() and not (NYRP.Camera and NYRP.Camera.IsThirdPerson and NYRP.Camera.IsThirdPerson()) then return end
		local bone = owner:LookupBone("ValveBiped.Bip01_R_Hand")
		if not bone then return end
		local m = owner:GetBoneMatrix(bone)
		if not m then return end
		-- экран смотрит на лицо: чуть назад и вверх от корпуса (кость кисти у моделей повёрнута по-разному)
		local body = Angle(0, owner:GetRenderAngles().y, 0)
		local pos, ang = LocalToWorld(Vector(1.2, 0, 1.6), Angle(-35, 180, 0), m:GetTranslation(), body)
		self:SetRenderOrigin(pos)
		self:SetRenderAngles(ang)
		self:SetupBones()
		self:DrawModel()
		self:SetRenderOrigin()
		self:SetRenderAngles()
	end

	function SWEP:DrawHUD() end
end
