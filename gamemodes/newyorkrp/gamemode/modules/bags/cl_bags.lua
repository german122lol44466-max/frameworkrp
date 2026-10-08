--[[
	Сумки на персонаже: части .mdl (models/nyrp/bags/*) крепятся к телу,
	крышка/клапан и бегунок молнии анимируются кадрами из sh_bag_models.lua.
	NYRP.Bags.DrawOn(ent, bagId, frame) — рисует сумку на модели (сейчас нигде не используется:
	на теле сумку не видно). На экране при открытии — вьюмодель с руками c_arms (см. ниже).
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
		m.RenderOverride = function(e) if e.nyrpDraw then e:DrawModel() end end
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
			m.nyrpDraw = true
			m:DrawModel()
			m.nyrpDraw = false
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

-- Сумку на теле не рисуем вообще: её видно только в анимации рук на экране при открытии инвентаря.

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
	local custom = Bags.FPActive and Bags.FPActive()
	-- со своей анимацией рук камеру не наклоняем: руки и так подносят сумку к глазам
	local want = inv and (inv.Opening or (inv.IsOpen and inv.IsOpen())) and not NYRP.Camera.IsThirdPerson() and not custom
	look = UI.Approach(look, want and 1 or 0, want and 6 or 8)
	local bag = LocalPlayer():GetNW2String("nyrp.bag", "waistbag")
	NYRP.Camera.LookBlend = look
	NYRP.Camera.LookPitch = custom and 0 or (bag == "backpack" and 38 or 62)
	NYRP.Camera.LookYaw = (custom or bag ~= "backpack") and 0 or 35
end)

-- ------------------------------------------- своя анимация от первого лица --
-- Играет и от первого, и от третьего лица — руки с сумкой всегда перед экраном.
-- Вьюмодель models/nyrp/bags/v_<сумка>.mdl: скелет c_arms + кости сумки, анимация сделана в
-- tools/models/viewmodel (Blender + IK): руки достают сумку, левая тянет бегунок молнии и откидывает
-- крышку (у рюкзака — правая поднимает клапан). Руки вашего персонажа (ply:GetHands()) цепляются
-- к ней бонмерджем, так что перчатки/кожа — свои. Последовательности: open, close, idle_open, idle_closed.
local VM_FOV = 62
local OPEN_RATE, CLOSE_RATE = 1.25, 1.7
local OPEN_FRAMES = 48 / 30
local fp
local fpVM, fpHands

local function ensureModels(bag)
	local path = "models/nyrp/bags/v_" .. bag .. ".mdl"
	if not IsValid(fpVM) or fpVM:GetModel() ~= path then
		if IsValid(fpVM) then fpVM:Remove() end
		fpVM = ClientsideModel(path, RENDERGROUP_OPAQUE)
		if not IsValid(fpVM) then return end
		fpVM:SetNoDraw(true)
		-- рисуем только сами, в нужный момент (иначе модель могла остаться висеть в мире)
		fpVM.RenderOverride = function(e) if e.nyrpDraw then e:DrawModel() end end
		if IsValid(fpHands) then fpHands:Remove() end
		fpHands = nil
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

-- Через сколько секунд после начала анимации показывать окно инвентаря (крышка почти открыта).
function Bags.FPOpenDelay()
	if not fp then return 0.95 end
	return OPEN_FRAMES / OPEN_RATE * 0.9
end

function Bags.FPStart()
	local bag = LocalPlayer():GetNW2String("nyrp.bag", "")
	if not NYRP.BagModels[bag] then bag = "waistbag" end
	local path = "models/nyrp/bags/v_" .. bag .. ".mdl"
	if not file.Exists(path, "GAME") then
		print("[NYRP] нет модели " .. path .. " — обновите контент режима (newyorkrp_content.zip)")
		return
	end
	util.PrecacheModel(path)
	fp = { bag = bag, seq = "open", start = RealTime(), from = 0 }
end

function Bags.FPClose()
	if not fp or fp.seq == "close" then return end
	-- закрываем с того места, где сейчас открытие (обратная последовательность)
	local c = math.Clamp((RealTime() - fp.start) * OPEN_RATE / OPEN_FRAMES, 0, 1)
	fp = { bag = fp.bag, seq = "close", start = RealTime(), from = 1 - c }
end

function Bags.FPActive() return fp ~= nil end

-- Анимация кончилась — модели убираем совсем.
function Bags.FPCleanup()
	fp = nil
	if IsValid(fpHands) then fpHands:Remove() end
	if IsValid(fpVM) then fpVM:Remove() end
	fpHands, fpVM = nil, nil
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
	if not ply:Alive() then Bags.FPCleanup() return end
	local vm, hands = ensureModels(fp.bag)
	if not IsValid(vm) or not IsValid(hands) then Bags.FPCleanup() return end

	local t = RealTime() - fp.start
	local seqName, cycle
	if fp.seq == "open" then
		cycle = math.min(t * OPEN_RATE / OPEN_FRAMES, 1)
		seqName = cycle >= 1 and "idle_open" or "open"
	else
		cycle = fp.from + t * CLOSE_RATE / OPEN_FRAMES
		if cycle >= 1 then Bags.FPCleanup() return end
		seqName = "close"
	end
	local seq = vm:LookupSequence(seqName)
	if seq < 0 then Bags.FPCleanup() return end
	if vm:GetSequence() ~= seq then vm:ResetSequence(seq) end
	vm:SetPlaybackRate(0)
	vm:SetCycle(math.Clamp(cycle, 0, 0.999))

	local eye, view = EyePos(), EyeAngles()
	-- лёгкое покачивание вместе с дыханием, чтобы картинка не была мёртвой
	local sway = Angle(math.sin(RealTime() * 1.3) * 0.35, math.cos(RealTime() * 0.9) * 0.3, 0)
	vm:SetPos(eye)
	vm:SetAngles(view + sway)
	vm:InvalidateBoneCache()
	vm:SetupBones()
	hands:InvalidateBoneCache()
	hands:SetupBones()

	cam.Start3D(eye, view, VM_FOV, nil, nil, nil, nil, 1, 300)
	render.ClearDepth()
	render.SuppressEngineLighting(true)
	setupLighting(eye, view)
	vm.nyrpDraw, hands.nyrpDraw = true, true
	vm:DrawModel()
	hands:DrawModel()
	vm.nyrpDraw, hands.nyrpDraw = false, false
	render.SuppressEngineLighting(false)
	cam.End3D()
end)
