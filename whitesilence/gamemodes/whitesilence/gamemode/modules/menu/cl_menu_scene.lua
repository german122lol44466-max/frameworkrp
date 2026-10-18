--[[
	3D-сцена главного меню: отряд из пяти бойцов (модель и оружие из конфига) выходит из темноты.

	Порядок: первый выходит и встаёт на «своё» место справа; за ним второй; потом ещё двое;
	когда подходит пятый, первый делает пару шагов вперёд, а пятый встаёт туда, где стоял первый.
	Все стоят вполоборота к центру экрана, дышат (idle-анимация), из темноты их отделяет туман.

	Камера смотрит вдоль +X, «вправо по экрану» — это −Y. Координаты — юниты Source (боец ~72 юнита).
]]

local Scene = {}
WS.Menu.Scene = Scene

local CAM_POS = Vector(0, 0, 52)
local CAM_ANG = Angle(3, 0, 0)
local CAM_FOV = 42

-- Маршруты: { время старта, точка входа, место, взгляд (yaw) }, у первого — второй отрезок, когда приходит пятый
local ROUTES = {
	{ { 0.6, Vector(430, -205, 0), Vector(178, -66, 0) }, { 7.9, nil, Vector(146, -64, 0) }, yaw = 150 },
	{ { 2.8, Vector(520, -150, 0), Vector(250, -52, 0) }, yaw = 158 },
	{ { 5.0, Vector(560, -250, 0), Vector(262, -122, 0) }, yaw = 143 },
	{ { 5.4, Vector(600, -190, 0), Vector(332, -90, 0) }, yaw = 152 },
	{ { 7.5, Vector(470, -230, 0), Vector(178, -66, 0) }, yaw = 147 },
}

local soldiers = {}
local startTime

local function seq(ent, names)
	for _, n in ipairs(names) do
		local s = ent:LookupSequence(n)
		if s and s >= 0 then return s end
	end
	return 0
end

function Scene.Init()
	Scene.Remove()
	local C = WS.Config
	local mdl = util.IsValidModel(C.SquadModel) and C.SquadModel or C.SquadModelFallback
	local stored = weapons.GetStored(C.MenuWeapon)
	local wmdl = stored and stored.WorldModel or C.MenuWeaponFallback
	if not util.IsValidModel(wmdl) then wmdl = C.MenuWeaponFallback end
	for i, route in ipairs(ROUTES) do
		local ent = ClientsideModel(mdl, RENDERGROUP_OPAQUE)
		if not IsValid(ent) then goto skip end
		ent:SetNoDraw(true)
		ent:SetSkin(i % 2)
		local wep = ClientsideModel(wmdl, RENDERGROUP_OPAQUE)
		if IsValid(wep) then
			wep:SetNoDraw(true)
			wep:SetParent(ent)
			wep:AddEffects(EF_BONEMERGE)
		end
		soldiers[i] = {
			ent = ent, wep = wep, route = route,
			walk = seq(ent, { "walk_ar2", "walk_rpg", "walk_all" }),
			idle = seq(ent, { "idle_ar2", "idle_rpg", "idle_all_01" }),
			pos = route[1][2], yaw = route.yaw, phase = math.Rand(0, 1),
		}
		::skip::
	end
	startTime = RealTime()
end

function Scene.Remove()
	for _, s in ipairs(soldiers) do
		if IsValid(s.wep) then s.wep:Remove() end
		if IsValid(s.ent) then s.ent:Remove() end
	end
	soldiers = {}
end

-- Где боец в момент t и что делает: позиция, направление, идёт ли, сколько прошёл
local function evaluate(s, t)
	local route = s.route
	local speed = math.max(s.ent:GetSequenceGroundSpeed(s.walk), 40)
	local pos = route[1][2]
	local walking, yaw, dist = false, route.yaw, 0
	for _, leg in ipairs(route) do
		local t0, from, to = leg[1], leg[2] or pos, leg[3]
		if t < t0 then break end
		local len = from:Distance(to)
		local d = (t - t0) * speed
		local dir = (to - from):GetNormalized()
		if d < len then
			pos = from + dir * d
			walking, yaw, dist = true, dir:Angle().y, d
			break
		end
		pos = to
		-- дошёл: плавно поворачивается к центру
		local turn = math.Clamp((d - len) / speed / 0.7, 0, 1)
		yaw = Lerp(turn, dir:Angle().y, route.yaw)
		dist = len
	end
	return pos, yaw, walking, dist, speed
end

function Scene.Draw(alpha, light)
	if not startTime or alpha <= 0 then return end
	local t = RealTime() - startTime
	local w, h = ScrW(), ScrH()

	cam.Start3D(CAM_POS, CAM_ANG, CAM_FOV, 0, 0, w, h, 5, 2000)
	render.ClearDepth()
	render.SuppressEngineLighting(true)
	-- тёмная сцена: слабый холодный верх, контровой свет сзади, тёплые всполохи искр справа
	local spark = light or 0
	render.ResetModelLighting(0.015, 0.017, 0.022)
	render.SetModelLighting(BOX_TOP, 0.20, 0.23, 0.30)
	render.SetModelLighting(BOX_FRONT, 0.16, 0.20, 0.27)
	render.SetModelLighting(BOX_BACK, 0.03, 0.035, 0.045)
	render.SetModelLighting(BOX_RIGHT, 0.05 + spark * 0.45, 0.04 + spark * 0.22, 0.03 + spark * 0.05)
	render.SetModelLighting(BOX_LEFT, 0.04, 0.05, 0.07)
	render.FogMode(MATERIAL_FOG_LINEAR)
	render.FogStart(230)
	render.FogEnd(640)
	render.FogMaxDensity(0.97)
	render.FogColor(6, 7, 10)

	for _, s in ipairs(soldiers) do
		local ent = s.ent
		if not IsValid(ent) or t < s.route[1][1] then goto next end
		local pos, yaw, walking, dist, speed = evaluate(s, t)
		ent:SetPos(pos)
		ent:SetAngles(Angle(0, yaw, 0))
		if walking then
			ent:SetSequence(s.walk)
			ent:SetPoseParameter("move_x", 1)
			ent:SetPoseParameter("move_y", 0)
			-- цикл шага привязан к пройденному пути — ноги не скользят
			local stride = math.max(ent:SequenceDuration(s.walk) * speed, 1)
			ent:SetCycle((dist / stride + s.phase) % 1)
		else
			ent:SetSequence(s.idle)
			ent:SetPoseParameter("move_x", 0)
			ent:SetCycle(((t + s.phase * 3) / math.max(ent:SequenceDuration(s.idle), 0.5)) % 1)
		end
		ent:InvalidateBoneCache()
		ent:SetupBones()
		-- проявляется из темноты в первые полсекунды пути
		render.SetBlend(alpha * math.Clamp((t - s.route[1][1]) / 0.6, 0, 1))
		ent:DrawModel()
		if IsValid(s.wep) then
			s.wep:InvalidateBoneCache()
			s.wep:DrawModel()
		end
		::next::
	end

	render.SetBlend(1)
	render.FogMode(MATERIAL_FOG_NONE)
	render.SuppressEngineLighting(false)
	cam.End3D()
end
