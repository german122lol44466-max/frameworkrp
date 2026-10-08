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
	waistbag = { bone = "ValveBiped.Bip01_Pelvis", offset = Vector(7.4, 0, 1.5), yaw = 0 },
	backpack = { bone = "ValveBiped.Bip01_Spine2", offset = Vector(-8.2, 0, -4), yaw = 180 },
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
	NYRP.Camera.LookPitch = bag == "backpack" and 38 or 62
	NYRP.Camera.LookYaw = bag == "backpack" and 35 or 0
end)
