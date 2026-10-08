--[[
	Сумки на персонаже: части .mdl (models/nyrp/bags/*) крепятся к телу,
	крышка/клапан и бегунок молнии анимируются кадрами из sh_bag_models.lua.
	NYRP.Bags.DrawOn(ent, bagId, frame) — рисует сумку на любой модели (превью в меню создания).
]]

local UI = NYRP.UI
NYRP.Bags = NYRP.Bags or {}
local Bags = NYRP.Bags

-- Крепление: кость, смещение (вперёд, вправо, вверх) и разворот относительно взгляда тела.
Bags.Mount = {
	waistbag = { bone = "ValveBiped.Bip01_Pelvis", offset = Vector(6.0, 0, 1.2), yaw = 0 },
	backpack = { bone = "ValveBiped.Bip01_Spine2", offset = Vector(-6.4, 0, -3.2), yaw = 180 },
}

local cache = {}
local function partModel(path)
	local m = cache[path]
	if not IsValid(m) then
		m = ClientsideModel(path, RENDERGROUP_OPAQUE)
		if not IsValid(m) then return end
		m:SetNoDraw(true)
		cache[path] = m
	end
	return m
end

local function frameData(def, part, frame)
	local keys = def.anim[part]
	if not keys then return end
	local n = #keys
	frame = math.Clamp(frame, 0, n - 1)
	local i = math.floor(frame)
	local f = frame - i
	local a, b = keys[i + 1], keys[math.min(i + 2, n)]
	return Vector(Lerp(f, a[1], b[1]), Lerp(f, a[2], b[2]), Lerp(f, a[3], b[3])),
		Angle(Lerp(f, a[4], b[4]), Lerp(f, a[5], b[5]), Lerp(f, a[6], b[6]))
end

-- Рисует сумку в мировых pos/ang (ang — «вперёд от владельца»).
function Bags.DrawAt(bagId, pos, ang, frame, scale)
	local def = NYRP.BagModels and NYRP.BagModels[bagId]
	if not def then return end
	for part, path in pairs(def.parts) do
		local m = partModel(path)
		if IsValid(m) then
			local lp, la = Vector(0, 0, 0), Angle(0, 0, 0)
			if part ~= "root" then
				lp, la = frameData(def, part, frame or 0)
				if not lp then lp, la = Vector(0, 0, 0), Angle(0, 0, 0) end
			end
			local wp, wa = LocalToWorld(lp * (scale or 1), la, pos, ang)
			m:SetModelScale(scale or 1, 0)
			m:SetRenderOrigin(wp)
			m:SetRenderAngles(wa)
			m:SetupBones()
			m:DrawModel()
		end
	end
end

function Bags.MountTransform(ent, bagId)
	local mount = Bags.Mount[bagId]
	if not mount then return end
	local bone = ent:LookupBone(mount.bone)
	if not bone then return end
	local bp = ent:GetBonePosition(bone)
	if not bp then return end
	local yaw = ent:IsPlayer() and ent:GetRenderAngles().y or ent:GetAngles().y
	local base = Angle(0, yaw, 0)
	local scale = ent:GetModelScale() or 1
	local pos = LocalToWorld(mount.offset * scale, Angle(), bp, base)
	return pos, Angle(0, yaw + mount.yaw, 0), scale
end

function Bags.DrawOn(ent, bagId, frame)
	local pos, ang, scale = Bags.MountTransform(ent, bagId)
	if pos then Bags.DrawAt(bagId, pos, ang, frame, scale) end
end

-- Кадр анимации открытия у игрока (по сетевым меткам времени).
function Bags.Frame(ply, bagId)
	local def = NYRP.BagModels[bagId]
	local last = #(select(2, next(def.anim))) - 1
	local fps = def.fps
	if ply:GetNW2Bool("nyrp.bagOpen") then
		return math.Clamp((CurTime() - ply:GetNW2Float("nyrp.bagTime")) * fps, 0, last)
	end
	return math.Clamp(last - (CurTime() - ply:GetNW2Float("nyrp.bagTime")) * fps * 1.4, 0, last)
end

hook.Add("PostPlayerDraw", "nyrp.bags", function(ply)
	if not ply:Alive() or ply:GetNoDraw() then return end
	local bag = ply:GetNW2String("nyrp.bag", "")
	if bag == "" or not (NYRP.BagModels and NYRP.BagModels[bag]) then return end
	Bags.DrawOn(ply, bag, Bags.Frame(ply, bag))
end)

-- Жест рук при открытии/закрытии (у всех игроков вокруг).
net.Receive("nyrp.inv.anim", function()
	local ply = net.ReadEntity()
	local act = net.ReadUInt(16)
	if IsValid(ply) then ply:AnimRestartGesture(GESTURE_SLOT_CUSTOM, act, true) end
end)

-- Камера при открытии: поясная — взгляд вниз на сумку, рюкзак — через плечо.
local look = 0
hook.Add("Think", "nyrp.bags.look", function()
	local inv = NYRP.Inventory
	local want = inv and (inv.Opening or (inv.IsOpen and inv.IsOpen())) and not NYRP.Camera.IsThirdPerson()
	look = UI.Approach(look, want and 1 or 0, want and 6 or 8)
	local bag = LocalPlayer():GetNW2String("nyrp.bag", "waistbag")
	NYRP.Camera.LookBlend = look
	local custom = Bags.FPActive and Bags.FPActive()
	NYRP.Camera.LookPitch = custom and 22 or (bag == "backpack" and 38 or 62)
	NYRP.Camera.LookYaw = (custom or bag ~= "backpack") and 0 or 35
end)

-- ------------------------------------------- своя анимация от первого лица --
-- От первого лица на экране руки (модель рук вашего персонажа) поднимают сумку в кадр,
-- бегунок едет по молнии, крышка откидывается; при закрытии — обратно и руки опускаются.
-- От третьего лица — жест рук и анимация сумки на теле (её видят и другие).
local fp
local HANDS_VM = "models/weapons/c_medkit.mdl" -- даёт позу и анимацию доставания для рук
local fpVM, fpHands

local function ensureHands()
	local ply = LocalPlayer()
	local hands = ply:GetHands()
	local mdl = IsValid(hands) and hands:GetModel() or "models/weapons/c_arms_citizen.mdl"
	if not mdl or mdl == "" then return end
	if not IsValid(fpVM) then
		fpVM = ClientsideModel(HANDS_VM, RENDERGROUP_OPAQUE)
		if not IsValid(fpVM) then return end
		fpVM:SetNoDraw(true)
	end
	if not IsValid(fpHands) or fpHands:GetModel() ~= mdl then
		if IsValid(fpHands) then fpHands:Remove() end
		fpHands = ClientsideModel(mdl, RENDERGROUP_OPAQUE)
		if not IsValid(fpHands) then return end
		fpHands:SetNoDraw(true)
		fpHands:SetParent(fpVM)
		fpHands:AddEffects(EF_BONEMERGE)
	end
	if IsValid(hands) then
		fpHands:SetSkin(hands:GetSkin())
		for i = 0, hands:GetNumBodyGroups() - 1 do fpHands:SetBodygroup(i, hands:GetBodygroup(i)) end
	end
	return fpVM, fpHands
end

function Bags.FPStart()
	if NYRP.Camera.IsThirdPerson() then return end
	local bag = LocalPlayer():GetNW2String("nyrp.bag", "")
	if not NYRP.BagModels[bag] then return end
	fp = { bag = bag, start = RealTime() }
end

function Bags.FPClose()
	if fp and not fp.closing then fp.closing = RealTime() end
end

function Bags.FPActive() return fp ~= nil end

local poses = {
	waistbag = { width = 10.5, pitch = 38, lift = 1.5 },
	backpack = { width = 11, pitch = 20, lift = 3.5 },
}

-- Отражение относительно вертикальной плоскости камеры: из правой руки получается левая.
local function mirrorMatrix(eye, view)
	local r = Matrix()
	r:SetAngles(view)
	local t1, t2, sc = Matrix(), Matrix(), Matrix()
	t1:SetTranslation(eye)
	t2:SetTranslation(-eye)
	sc:Scale(Vector(1, -1, 1))
	return t1 * r * sc * r:GetInverse() * t2
end

local function setupLighting(eye, view)
	local function light(dir)
		local c = render.ComputeLighting(eye, dir) + render.ComputeDynamicLighting(eye, dir)
		return math.Clamp(c.x + 0.12, 0, 1.4), math.Clamp(c.y + 0.12, 0, 1.4), math.Clamp(c.z + 0.14, 0, 1.4)
	end
	render.SetModelLighting(BOX_TOP, light(Vector(0, 0, 1)))
	render.SetModelLighting(BOX_BOTTOM, light(Vector(0, 0, -1)))
	render.SetModelLighting(BOX_FRONT, light(view:Forward()))
	render.SetModelLighting(BOX_BACK, light(-view:Forward()))
	render.SetModelLighting(BOX_LEFT, light(-view:Right()))
	render.SetModelLighting(BOX_RIGHT, light(view:Right()))
end

hook.Add("HUDPaintBackground", "nyrp.bags.fp", function()
	if not fp then return end
	local ply = LocalPlayer()
	if not ply:Alive() or NYRP.Camera.IsThirdPerson() then fp = nil return end
	local def = NYRP.BagModels[fp.bag]
	local last = #(select(2, next(def.anim))) - 1
	local now = RealTime()
	local t = now - fp.start
	local p = poses[fp.bag]
	local eye, view = EyePos(), EyeAngles()

	local vm, hands = ensureHands()
	local drawSeq = IsValid(vm) and vm:SelectWeightedSequence(ACT_VM_DRAW) or -1
	local idleSeq = IsValid(vm) and vm:SelectWeightedSequence(ACT_VM_IDLE) or -1
	local drawDur = 0.55
	local raise = math.Clamp(t / drawDur, 0, 1)                 -- руки поднимаются
	local frame = math.Clamp((t - drawDur * 0.8) / 0.5, 0, 1) * last
	local lower = 0
	if fp.closing then
		local c = now - fp.closing
		frame = frame * (1 - math.Clamp(c / 0.28, 0, 1))
		lower = UI.Ease((c - 0.22) / 0.35)
		if c > 0.6 then fp = nil return end
	end

	cam.Start3D(eye, view, 62)
	render.ClearDepth()
	render.SuppressEngineLighting(true)
	setupLighting(eye, view)

	local bagPos, bagScale
	if IsValid(vm) and IsValid(hands) and drawSeq >= 0 then
		-- поза рук: анимация доставания, потом idle; при закрытии — опускаем
		local seq = (raise < 1 or idleSeq < 0) and drawSeq or idleSeq
		if vm:GetSequence() ~= seq then vm:ResetSequence(seq) end
		vm:SetCycle(seq == drawSeq and raise or (t * 0.2) % 1)
		local drop = view:Up() * (-14 * lower) + view:Forward() * (-2 * lower)
		vm:SetPos(eye + drop)
		vm:SetAngles(view)
		vm:SetupBones()
		hands:SetupBones()
		local bone = vm:LookupBone("ValveBiped.Bip01_R_Hand")
		local m = bone and vm:GetBoneMatrix(bone)
		if m then
			local right = view:Right()
			local rp = m:GetTranslation()
			local lp = rp - right * (2 * (rp - eye):Dot(right))
			bagPos = (rp + lp) / 2 + view:Up() * p.lift + view:Forward() * 1.5
			bagScale = math.Clamp(rp:Distance(lp) / p.width, 0.55, 1.15)
		end
		hands:DrawModel()
		cam.PushModelMatrix(mirrorMatrix(eye, view))
		render.CullMode(MATERIAL_CULLMODE_CW)
		hands:DrawModel()
		render.CullMode(MATERIAL_CULLMODE_CCW)
		cam.PopModelMatrix()
	end
	if not bagPos then
		-- без рук: сумка просто поднимается в кадр
		local rise = UI.Ease(t / 0.35) * (1 - lower)
		bagPos = LocalToWorld(Vector(15, 0, Lerp(rise, -28, -7)), Angle(), eye, view)
		bagScale = 1
	end
	local wobble = (frame > 0 and frame < last and not fp.closing) and math.sin(t * 60) * 1.5 or 0
	local _, ang = LocalToWorld(Vector(), Angle(p.pitch, 180, math.sin(t * 1.6) * 2 + wobble), eye, view)
	Bags.DrawAt(fp.bag, bagPos, ang, frame, bagScale)
	render.SuppressEngineLighting(false)
	cam.End3D()
end)
