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

-- Мировая точка localPoint на части part (root/lid/zipper/flap) при кадре frame.
function Bags.PartPoint(bagId, pos, ang, frame, scale, part, localPoint)
	local def = NYRP.BagModels[bagId]
	local lp, la = Vector(0, 0, 0), Angle(0, 0, 0)
	if part ~= "root" and def then
		lp, la = frameData(def, part, frame or 0)
		if not lp then lp, la = Vector(0, 0, 0), Angle(0, 0, 0) end
	end
	local pp, pa = LocalToWorld(lp * (scale or 1), la, pos, ang)
	return (LocalToWorld(localPoint * (scale or 1), Angle(), pp, pa))
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

-- Настройка анимации рук от первого лица (единицы — в масштабе модели сумки).
-- grip  — за что берётся левая рука, пока едет молния (точка на бегунке);
-- lift  — край крышки/клапана, который она поднимает;
-- wrist — смещение запястья от точки хвата (вдоль взгляда / вправо / вверх).
local poses = {
	waistbag = {
		scale = 0.62, pitch = 34,
		zip = { from = 0, to = 12 }, lift = { from = 13, to = 24 },
		grip = { part = "zipper", pt = Vector(0.3, 0, -0.5) },
		edge = { part = "lid", pt = Vector(3.4, 0, 1.1) },
		wrist = Vector(-3.2, -0.6, -1.2),
	},
	backpack = {
		scale = 0.48, pitch = 18,
		zip = { from = 0, to = 4 }, lift = { from = 4, to = 24 },
		grip = { part = "flap", pt = Vector(5.3, 0, -4.8) },
		edge = { part = "flap", pt = Vector(5.3, 0, -4.8) },
		wrist = Vector(-3.2, -0.6, -1.4),
	},
}
CreateClientConVar("nyrp_bagfp_debug", "0", false, false, "Показать точки, к которым тянется рука при открытии сумки")

-- Кость предмета во вьюмодели (аптечка) — на её место ставим сумку: рука держит именно её.
local propBone
local function findPropBone(vm)
	if propBone and propBone.model == vm:GetModel() then return propBone.id end
	local id
	for i = 0, vm:GetBoneCount() - 1 do
		local name = vm:GetBoneName(i) or ""
		if name ~= "__INVALIDBONE__" and not string.find(name, "ValveBiped", 1, true) then id = i break end
	end
	propBone = { model = vm:GetModel(), id = id }
	return id
end

-- Переносим всю левую руку (от плеча, оно за кадром) так, чтобы кисть оказалась в target.
local function placeLeftHand(vm, target)
	local upper = vm:LookupBone("ValveBiped.Bip01_L_UpperArm")
	local hand = vm:LookupBone("ValveBiped.Bip01_L_Hand")
	if not upper or not hand then return end
	vm:ManipulateBonePosition(upper, vector_origin)
	vm:InvalidateBoneCache()
	vm:SetupBones()
	if not target then return end
	local hm = vm:GetBoneMatrix(hand)
	local parent = vm:GetBoneParent(upper)
	local pm = parent and parent >= 0 and vm:GetBoneMatrix(parent)
	if not hm or not pm then return end
	local delta = target - hm:GetTranslation()
	local localDelta = WorldToLocal(delta, Angle(), vector_origin, pm:GetAngles())
	vm:ManipulateBonePosition(upper, localDelta)
	vm:InvalidateBoneCache()
	vm:SetupBones()
end

local function setupLighting(eye, view)
	local function light(dir)
		local c = render.ComputeLighting(eye, dir) + render.ComputeDynamicLighting(eye, dir)
		return math.Clamp(c.x + 0.15, 0, 1.4), math.Clamp(c.y + 0.15, 0, 1.4), math.Clamp(c.z + 0.17, 0, 1.4)
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

	local DRAW = 0.6
	local raise = UI.EaseInOut(math.Clamp(t / DRAW, 0, 1))          -- рука поднимает сумку
	local frame = math.Clamp((t - DRAW * 0.85) / 0.45, 0, 1) * last  -- молния и крышка
	if fp.closing then
		local c = now - fp.closing
		frame = frame * (1 - math.Clamp(c / 0.25, 0, 1))
		raise = raise * (1 - UI.EaseInOut(math.Clamp((c - 0.2) / 0.35, 0, 1)))
		if c > 0.6 then fp = nil return end
	end

	cam.Start3D(eye, view, 62)
	render.ClearDepth()
	render.SuppressEngineLighting(true)
	setupLighting(eye, view)

	local bagPos
	local vm, hands = ensureHands()
	local drawSeq = IsValid(vm) and vm:SelectWeightedSequence(ACT_VM_DRAW) or -1
	if IsValid(vm) and IsValid(hands) and drawSeq >= 0 then
		if vm:GetSequence() ~= drawSeq then vm:SetSequence(drawSeq) end
		vm:SetPlaybackRate(0)
		vm:SetCycle(math.Clamp(raise, 0, 0.999))
		-- при закрытии рука ещё и уходит вниз из кадра
		local lower = fp.closing and (1 - raise) or 0
		vm:SetPos(eye - view:Up() * (10 * lower))
		vm:SetAngles(view)
		vm:InvalidateBoneCache()
		vm:SetupBones()
		hands:InvalidateBoneCache()
		hands:SetupBones()
		placeLeftHand(vm, nil)
		local bone = findPropBone(vm) or vm:LookupBone("ValveBiped.Bip01_R_Hand")
		local m = bone and vm:GetBoneMatrix(bone)
		if m then bagPos = m:GetTranslation() end
		if bagPos then
			-- левая рука: снизу в кадр -> язычок молнии -> ведёт его -> поднимает край крышки
			local wob = (frame > 0 and frame < last and not fp.closing) and math.sin(t * 55) * 1.2 or 0
			local _, bagAng = LocalToWorld(Vector(), Angle(p.pitch, 195, math.sin(t * 1.6) * 2 + wob), eye, view)
			local function at(spec, f)
				local pt = Bags.PartPoint(fp.bag, bagPos, bagAng, f, p.scale, spec.part, spec.pt)
				return pt + LocalToWorld(p.wrist, Angle(), vector_origin, view)
			end
			local rest = eye + view:Forward() * 14 + view:Right() * -9 + view:Up() * -24
			local target
			local reach = math.Clamp((t - DRAW * 0.45) / 0.35, 0, 1)  -- рука тянется к молнии
			if frame <= p.zip.to then
				target = LerpVector(UI.EaseInOut(reach), rest, at(p.grip, frame))
			else
				local k = math.Clamp((frame - p.lift.from) / (p.lift.to - p.lift.from), 0, 1)
				target = LerpVector(UI.EaseInOut(math.min(k * 3, 1)), at(p.grip, frame), at(p.edge, frame))
			end
			if fp.closing then
				target = LerpVector(1 - raise, target, rest)
			end
			placeLeftHand(vm, target)
			hands:InvalidateBoneCache()
			hands:SetupBones()
			fp.debug = GetConVar("nyrp_bagfp_debug"):GetBool() and { target, at(p.grip, frame), at(p.edge, frame) } or nil
		end
		hands:DrawModel()
	end
	if not bagPos then
		-- без рук: сумка просто поднимается в кадр
		bagPos = LocalToWorld(Vector(18, 2, Lerp(raise, -26, -8)), Angle(), eye, view)
	end
	local wobble = (frame > 0 and frame < last and not fp.closing) and math.sin(t * 55) * 1.2 or 0
	local _, ang = LocalToWorld(Vector(), Angle(p.pitch, 195, math.sin(t * 1.6) * 2 + wobble), eye, view)
	Bags.DrawAt(fp.bag, bagPos, ang, frame, p.scale)
	if fp.debug then
		render.SetColorMaterial()
		for i, v in ipairs(fp.debug) do
			render.DrawSphere(v, 0.4, 8, 8, i == 1 and Color(255, 60, 60) or Color(60, 255, 120))
		end
	end
	render.SuppressEngineLighting(false)
	cam.End3D()
end)
