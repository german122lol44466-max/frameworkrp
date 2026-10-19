--[[
	Руки на экране при подборе предметов и взаимодействии; оружие в это время опущено («на предохранителе»).

	Модель — руки игрока (GetHands, у winterizedarmor свои; иначе c_arms_citizen). Анимаций у таких моделей
	нет, поэтому поза считается здесь: плечо — у нижнего правого края обзора, кисть идёт к цели (обратная
	кинематика двух звеньев: плечо → локоть → кисть), пальцы сгибаются по своим осям, ладонь развёрнута
	по задаче. Левая рука и плечевой пояс убраны (сжаты в точку за камерой).

	Виды (сервер присылает ws.hand, сюжет — через ws_use):
	  pickup   — протянуть руку к предмету, взять, убрать вниз;
	  interact — протянуть руку вперёд и держать, пока удерживается E (ретранслятор, генератор, заряды, ящики);
	  use      — поднести к груди и «работать» (бинт, аптечка, промедол, батарея).
	ws_hands 0 — выключить.
]]

local H = {}
WS.Hands = H

local enabled = CreateClientConVar("ws_hands", "1", true, false, "Руки на экране при взаимодействии", 0, 1)

-- ---------------------------------------------------------------- векторная математика (таблицы {x,y,z})

local function v(x, y, z) return { x = x, y = y, z = z } end
local function add(a, b) return v(a.x + b.x, a.y + b.y, a.z + b.z) end
local function sub(a, b) return v(a.x - b.x, a.y - b.y, a.z - b.z) end
local function mul(a, k) return v(a.x * k, a.y * k, a.z * k) end
local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function cross(a, b) return v(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x) end
local function len(a) return math.sqrt(dot(a, a)) end
local function norm(a) local l = len(a) if l < 1e-6 then return v(1, 0, 0) end return mul(a, 1 / l) end
local function lerpv(t, a, b) return add(a, mul(sub(b, a), t)) end
local function perp(a, axis) return norm(sub(a, mul(axis, dot(a, axis)))) end
H.vec = { v = v, add = add, sub = sub, mul = mul, dot = dot, cross = cross, norm = norm }

-- кадр кости: оси X Y Z (столбцы) и положение T
local function frame(X, Y, Z, T) return { X = X, Y = Y, Z = Z, T = T } end

-- родитель * относительная матрица (rel.m — строки 3×4)
local function compose(p, m)
	local function col(c) return v(m[1][c], m[2][c], m[3][c]) end
	local function apply(d) return add(add(mul(p.X, d.x), mul(p.Y, d.y)), mul(p.Z, d.z)) end
	return frame(apply(col(1)), apply(col(2)), apply(col(3)), add(p.T, apply(col(4))))
end

local function rotZ(f, ang)
	local c, s = math.cos(ang), math.sin(ang)
	return frame(add(mul(f.X, c), mul(f.Y, s)), add(mul(f.X, -s), mul(f.Y, c)), f.Z, f.T)
end

-- ---------------------------------------------------------------- скелет

local REL, PARENT, ORDER = {}, {}, {}
for i, b in ipairs(WS.HandsData or {}) do
	REL[b.name] = b.m
	PARENT[b.name] = b.parent
	ORDER[i] = b.name
end

H.PalmAxis = "-Y"                     -- какая ось кисти смотрит из ладони (проверено превью tools/test/hands_preview.py)
local UPPER, LOWER = 11.69, 11.48     -- длины плеча и предплечья (юниты)
local FINGER_CURL = { Finger0 = 0.45, Finger1 = 1, Finger2 = 1.05, Finger3 = 1.1, Finger4 = 1.15 }

local function easeIO(t) t = math.Clamp(t, 0, 1) return t * t * (3 - 2 * t) end

--[[
	Поза правой руки. ctx = { eye, F, R, U (базис взгляда), kind, u (0..1 — фаза), target (мир, для pickup), hold }
	Возвращает { [имя кости] = кадр } и долю «опускания» оружия.
]]
function H.Pose(ctx)
	local eye, F, R, U = ctx.eye, ctx.F, ctx.R, ctx.U
	local u = ctx.u
	-- плечо: справа снизу за краем обзора
	local S = add(add(add(eye, mul(F, -3)), mul(R, 8.5)), mul(U, -12))
	local rest = add(add(add(eye, mul(F, 9)), mul(R, 9)), mul(U, -22))       -- кисть внизу, вне экрана
	local reachT, palm, curl, out, point
	if ctx.kind == "pickup" then
		-- к предмету: направление на него, но не дальше вытянутой руки и в пределах экрана
		local dir = ctx.target and norm(sub(ctx.target, eye)) or F
		local lat = math.Clamp(dot(dir, R), -0.3, 0.35)
		local vert = math.Clamp(dot(dir, U), -0.6, 0.2)
		local reach = add(add(add(eye, mul(F, 15.5)), mul(R, 10 * lat + 3)), mul(U, 4 * vert - 1.2))
		local a = easeIO(u / 0.38)                 -- протянуть
		local g = easeIO((u - 0.3) / 0.15)         -- сжать пальцы
		local b = easeIO((u - 0.52) / 0.48)        -- убрать
		reachT = lerpv(b, lerpv(a, rest, reach), add(rest, mul(U, -4)))
		palm = norm(add(mul(U, -0.85), mul(R, -0.35)))          -- ладонью вниз
		point = norm(add(mul(F, 1), mul(U, -0.35)))              -- пальцы — вперёд и вниз, к предмету
		curl = 0.15 + 0.85 * g
		out = math.min(easeIO(u / 0.2), 1 - easeIO((u - 0.82) / 0.18))
	elseif ctx.kind == "use" then
		-- у груди, лёгкие движения «перевязки»
		local a = easeIO(u / 0.15)
		local b = easeIO((u - 0.88) / 0.12)
		local wob = math.sin(u * 28) * 1.2
		local work = add(add(add(eye, mul(F, 14)), mul(R, 3 + wob * 0.6)), mul(U, -3.2 + math.cos(u * 23) * 0.6))
		reachT = lerpv(b, lerpv(a, rest, work), rest)
		palm = norm(add(mul(U, 0.6), mul(R, -0.7)))             -- ладонью к центру и вверх
		curl = 0.55 + 0.25 * math.sin(u * 19)
		out = math.min(easeIO(u / 0.12), 1 - easeIO((u - 0.9) / 0.1))
	else -- interact: вперёд и держать
		local a = easeIO(u / 0.3)
		local b = ctx.hold and 0 or easeIO((u - 0.75) / 0.25)
		local press = add(add(add(eye, mul(F, 15)), mul(R, 3)), mul(U, -1.2 + math.sin(RealTime and RealTime() * 9 or 0) * 0.25))
		reachT = lerpv(b, lerpv(a, rest, press), rest)
		palm = norm(add(F, mul(U, -0.4)))                        -- ладонью вперёд (толкать, крутить)
		point = norm(add(add(F, mul(U, 0.55)), mul(R, -0.25)))
		curl = 0.35
		out = ctx.hold and easeIO(u / 0.2) or math.min(easeIO(u / 0.2), 1 - easeIO((u - 0.8) / 0.2))
	end

	-- обратная кинематика: локоть вниз и наружу
	local T = reachT
	local d = sub(T, S)
	local dist = math.Clamp(len(d), 4, UPPER + LOWER - 0.05)
	local dir = norm(d)
	T = add(S, mul(dir, dist))
	local x = (UPPER * UPPER - LOWER * LOWER + dist * dist) / (2 * dist)
	local h = math.sqrt(math.max(UPPER * UPPER - x * x, 0))
	local pole = perp(add(mul(U, -1), mul(R, 0.7)), dir)
	local Eb = add(add(S, mul(dir, x)), mul(pole, h))

	local Xu, Xf = norm(sub(Eb, S)), norm(sub(T, Eb))
	-- сгиб локтя — в сторону ладони (ось Z предплечья смотрит к ладони, как у ValveBiped)
	local Zu = perp(Xf, Xu)
	if len(sub(Xf, Xu)) < 0.02 then Zu = perp(palm, Xu) end
	local upper = frame(Xu, cross(Zu, Xu), Zu, S)
	local Zf = perp(palm, Xf)
	local fore = frame(Xf, cross(Zf, Xf), Zf, Eb)
	-- кисть: пальцы вперёд по предплечью с небольшим «изломом» запястья, ладонь — palm (ладонь = −Y)
	local Xh = point and norm(add(mul(Xf, 0.45), point)) or norm(add(Xf, mul(F, 0.5)))
	local hand
	if H.PalmAxis == "+Z" or H.PalmAxis == "-Z" then
		local Zh = perp(mul(palm, H.PalmAxis == "+Z" and 1 or -1), Xh)
		hand = frame(Xh, cross(Zh, Xh), Zh, T)
	else
		local Yh = perp(mul(palm, H.PalmAxis == "+Y" and 1 or -1), Xh)
		hand = frame(Xh, Yh, cross(Xh, Yh), T)
	end

	local P = {}
	P["ValveBiped.Bip01_R_UpperArm"] = upper
	P["ValveBiped.Bip01_R_Forearm"] = fore
	P["ValveBiped.Bip01_R_Hand"] = hand
	-- вспомогательные кости: локтевая — посередине предплечья, запястье — у кисти
	local midZ = norm(add(Zu, Zf))
	P["ValveBiped.Bip01_R_Ulna"] = frame(Xf, cross(midZ, Xf), midZ, add(Eb, mul(Xf, LOWER * 0.5)))
	P["ValveBiped.Bip01_R_Wrist"] = frame(Xf, fore.Y, fore.Z, T)
	-- пальцы: смещения из позы привязки + сгиб вокруг своей оси Z к ладони
	for _, name in ipairs(ORDER) do
		local f, seg = name:match("R_(Finger%d)(%d?)")
		if f then
			local parent = PARENT[name]
			local pf = P[parent]
			if pf then
				local k = (FINGER_CURL[f] or 1) * (seg == "" and 0.55 or (seg == "1" and 0.95 or 0.8))
				P[name] = rotZ(compose(pf, REL[name]), -curl * k * 1.25)
			end
		end
	end
	return P, out, S
end

-- ---------------------------------------------------------------- состояние анимации

local anim                 -- { kind, t0, dur, target, hold }
H.Lower = 0

function H.Play(kind, dur, target, hold)
	if not enabled:GetBool() then return end
	anim = { kind = kind, t0 = RealTime(), dur = math.max(dur or 1, 0.3), target = target, hold = hold }
end

function H.Active() return anim ~= nil end

net.Receive("ws.hand", function()
	local kind, pos, dur = net.ReadString(), net.ReadVector(), net.ReadFloat()
	H.Play(kind, dur, kind == "pickup" and v(pos.x, pos.y, pos.z) or nil)
end)

-- удержание E на сюжетном объекте — рука «работает», пока идёт прогресс
local holdingUse = false
hook.Add("Think", "ws.hands", function()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local using = ply:Alive() and ply:GetNW2Float("ws_use", 0) > 0
	if using and not holdingUse and not anim then
		H.Play("interact", 1.2, nil, true)
	end
	if not using and holdingUse and anim and anim.kind == "interact" and anim.hold then
		anim.hold = false
		anim.t0 = RealTime() - anim.dur * 0.75     -- убрать руку
	end
	holdingUse = using
	if anim then
		local u = (RealTime() - anim.t0) / anim.dur
		if anim.hold then u = math.min(u, 0.5) end
		if u >= 1 or not ply:Alive() then anim = nil end
	end
end)

-- ---------------------------------------------------------------- отрисовка

local handsEnt, handsModel
local current = {}        -- поза текущего кадра (по именам)

local function hideFrame(eye, F)
	local far = add(eye, mul(F, -200))
	local zero = v(0, 0, 0)
	return frame(zero, zero, zero, far)
end

local function toMatrix(f)
	return Matrix({
		{ f.X.x, f.Y.x, f.Z.x, f.T.x },
		{ f.X.y, f.Y.y, f.Z.y, f.T.y },
		{ f.X.z, f.Y.z, f.Z.z, f.T.z },
		{ 0, 0, 0, 1 },
	})
end

local function ensureEnt(ply)
	local mdl = "models/weapons/c_arms_citizen.mdl"
	local hands = ply:GetHands()
	if IsValid(hands) and hands:GetModel() and hands:GetModel() ~= "" then mdl = hands:GetModel() end
	if IsValid(handsEnt) and handsModel == mdl then return handsEnt end
	if IsValid(handsEnt) then handsEnt:Remove() end
	handsEnt = ClientsideModel(mdl, RENDERGROUP_VIEWMODEL)
	handsModel = mdl
	if not IsValid(handsEnt) then return end
	handsEnt:SetNoDraw(true)
	if IsValid(hands) then
		handsEnt:SetSkin(hands:GetSkin())
		for _, b in pairs(hands:GetBodyGroups() or {}) do handsEnt:SetBodygroup(b.id, hands:GetBodygroup(b.id)) end
	end
	handsEnt:AddCallback("BuildBonePositions", function(e, n)
		local eye, F = current.eye, current.F
		if not eye then return end
		for i = 0, n - 1 do
			local name = e:GetBoneName(i)
			local f = current.pose and current.pose[name]
			e:SetBoneMatrix(i, toMatrix(f or hideFrame(eye, F)))
		end
	end)
	return handsEnt
end

hook.Add("PostDrawViewModel", "ws.hands", function(vm, ply, wep)
	if not anim or not IsValid(vm) or vm:ViewModelIndex() ~= 0 then return end
	local e = ensureEnt(ply)
	if not IsValid(e) then return end
	local ang = EyeAngles()
	local eyeP = EyePos()
	local f, r, up = ang:Forward(), ang:Right(), ang:Up()
	local u = (RealTime() - anim.t0) / anim.dur
	if anim.hold then u = math.min(u, 0.5) end
	local ctx = { eye = v(eyeP.x, eyeP.y, eyeP.z), F = v(f.x, f.y, f.z), R = v(r.x, r.y, r.z), U = v(up.x, up.y, up.z),
		kind = anim.kind, u = math.Clamp(u, 0, 1), target = anim.target, hold = anim.hold }
	local pose = H.Pose(ctx)
	current.pose, current.eye, current.F = pose, ctx.eye, ctx.F
	e:SetPos(eyeP)
	e:SetAngles(ang)
	e:SetupBones()
	e:InvalidateBoneCache()
	e:DrawModel()
end)

-- ---------------------------------------------------------------- оружие вниз

local function lowerTarget()
	local ply = LocalPlayer()
	if anim then
		local u = (RealTime() - anim.t0) / anim.dur
		if anim.hold then return 1 end
		return math.Clamp(math.min(u / 0.15, (1 - u) / 0.2), 0, 1)
	end
	if ply:GetNW2Float("ws_using_until", 0) > CurTime() then return 1 end
	return 0
end

hook.Add("CalcViewModelView", "ws.hands", function(wep, vm, oldPos, oldAng, pos, ang)
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	H.Lower = WS.Approach(H.Lower, lowerTarget(), 4)
	local roll = WS.Camera and WS.Camera.Roll and WS.Camera.Roll() or 0
	if math.abs(roll) < 0.01 then roll = 0 end
	if H.Lower <= 0.001 and roll == 0 then return end
	-- сначала обычное положение оружия (TFA: прицеливание, качка), потом опускание
	local p, a = pos, ang
	if GAMEMODE.CalcViewModelView then
		local p2, a2 = GAMEMODE:CalcViewModelView(wep, vm, oldPos, oldAng, pos, ang)
		p, a = p2 or p, a2 or a
	end
	a = Angle(a.p, a.y, a.r)
	local k = easeIO(H.Lower)
	local fwd, right, up = a:Forward(), a:Right(), a:Up()
	p = p - up * 7 * k + right * 3 * k - fwd * 3 * k
	a:RotateAroundAxis(right, -38 * k)
	a:RotateAroundAxis(fwd, 18 * k + roll)
	return p, a
end)

-- пока оружие опущено — не стреляет
hook.Add("CreateMove", "ws.hands", function(cmd)
	if H.Lower > 0.3 then
		cmd:RemoveKey(IN_ATTACK)
		cmd:RemoveKey(IN_ATTACK2)
	end
end)
