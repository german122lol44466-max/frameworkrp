--[[
	Точки сюжета на карте: data/whitesilence/points/<карта>.json

	P.Get(id)            -> pos, yaw, radius   (расставленная или подобранная автоматически)
	P.GroupSpots(group)  -> { {pos, yaw}, ... } (точки появления группы врагов, может быть пусто)
	P.AutoNear(origin, min, max)  -> pos       (свободное место на земле на заданном расстоянии)
]]

local S = WS.Story
local P = {}
S.P = P

P.Data = { points = {}, groups = {} }
P.Auto = {}

local DIR = "whitesilence/points"
local function path() return DIR .. "/" .. game.GetMap() .. ".json" end

local function vec(t) return Vector(t[1], t[2], t[3]) end
local function tab(v) return { math.Round(v.x, 1), math.Round(v.y, 1), math.Round(v.z, 1) } end

function P.Load()
	P.Data = { points = {}, groups = {} }
	P.Auto = {}
	local raw = file.Read(path(), "DATA")
	if not raw then return false end
	local t = util.JSONToTable(raw)
	if not istable(t) then
		WS.Print("Файл точек повреждён: data/%s", path())
		return false
	end
	for id, p in pairs(t.points or {}) do
		if S.PointById[id] and istable(p.pos) then
			P.Data.points[id] = { pos = vec(p.pos), yaw = tonumber(p.yaw) or 0, r = tonumber(p.r) }
		end
	end
	for gid, list in pairs(t.groups or {}) do
		if S.GroupById[gid] and istable(list) then
			local out = {}
			for _, s in ipairs(list) do
				if istable(s.pos) then out[#out + 1] = { pos = vec(s.pos), yaw = tonumber(s.yaw) or 0 } end
			end
			P.Data.groups[gid] = out
		end
	end
	return true
end

function P.Save()
	file.CreateDir(DIR)
	local t = { map = game.GetMap(), points = {}, groups = {} }
	for id, p in pairs(P.Data.points) do t.points[id] = { pos = tab(p.pos), yaw = math.Round(p.yaw), r = p.r } end
	for gid, list in pairs(P.Data.groups) do
		t.groups[gid] = {}
		for _, s in ipairs(list) do t.groups[gid][#t.groups[gid] + 1] = { pos = tab(s.pos), yaw = math.Round(s.yaw) } end
	end
	file.Write(path(), util.TableToJSON(t, true))
end

-- ---------------------------------------------------------------- автоматический подбор

local function ground(pos)
	local tr = util.TraceLine({ start = pos + Vector(0, 0, 48), endpos = pos - Vector(0, 0, 4096), mask = MASK_PLAYERSOLID_BRUSHONLY })
	if tr.Hit and not tr.HitSky and not tr.StartSolid and tr.HitNormal.z > 0.6 then return tr.HitPos end
end

local function free(pos)
	local tr = util.TraceHull({ start = pos + Vector(0, 0, 6), endpos = pos + Vector(0, 0, 10),
		mins = Vector(-17, -17, 0), maxs = Vector(17, 17, 72), mask = MASK_PLAYERSOLID })
	return not tr.Hit
end
P.Free = free
P.Ground = ground

function P.MapOrigin()
	for _, cls in ipairs({ "info_player_start", "info_player_deathmatch", "info_player_combine", "info_player_rebel",
		"info_player_counterterrorist", "info_player_terrorist" }) do
		local e = ents.FindByClass(cls)[1]
		if IsValid(e) then return e:GetPos(), e:GetAngles().y end
	end
	return ground(vector_origin) or vector_origin, 0
end

function P.AutoNear(origin, dmin, dmax)
	if dmax <= 0 then return origin end
	-- навмеш: случайная зона на нужном расстоянии
	if navmesh.IsLoaded() then
		local pool = {}
		for _, a in ipairs(navmesh.GetAllNavAreas()) do
			if a:GetSizeX() >= 48 and a:GetSizeY() >= 48 and not a:IsUnderwater() then
				local d = a:GetCenter():Distance(origin)
				if d >= dmin and d <= dmax and math.abs(a:GetCenter().z - origin.z) < 600 then pool[#pool + 1] = a end
			end
		end
		for _ = 1, 12 do
			local a = pool[math.random(#pool)]
			if not a then break end
			local pos = a:GetRandomPoint()
			if free(pos) then return pos end
		end
	end
	-- без навмеша: лучи в случайные стороны, точка на земле, где помещается человек
	local best, bestD = nil, -1
	for _ = 1, 48 do
		local ang = math.Rand(0, math.pi * 2)
		local want = math.Rand(dmin, dmax)
		local dir = Vector(math.cos(ang), math.sin(ang), 0)
		local tr = util.TraceHull({ start = origin + Vector(0, 0, 40), endpos = origin + Vector(0, 0, 40) + dir * want,
			mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 36), mask = MASK_PLAYERSOLID_BRUSHONLY })
		local pos = ground(tr.HitPos - dir * 24)
		if pos and free(pos) then
			local d = pos:Distance(origin)
			if d >= dmin then return pos end
			if d > bestD then best, bestD = pos, d end
		end
	end
	return best or origin
end

local resolving = {}
function P.Get(id)
	local p = P.Data.points[id]
	local def = S.PointById[id]
	if p then return p.pos, p.yaw, p.r or (def and def.r) or 250 end
	if not P.Auto[id] then
		if not def then return P.MapOrigin(), 0, 250 end
		if def.near and not resolving[id] then
			resolving[id] = true
			local base = P.Get(def.near)
			resolving[id] = nil
			P.Auto[id] = { pos = P.AutoNear(base, def.dist[1], def.dist[2]), yaw = math.random(0, 359) }
		else
			local pos, yaw = P.MapOrigin()
			P.Auto[id] = { pos = pos, yaw = yaw }
		end
	end
	local a = P.Auto[id]
	return a.pos, a.yaw, (def and def.r) or 250
end

function P.IsSet(id) return P.Data.points[id] ~= nil end

function P.GroupSpots(gid) return P.Data.groups[gid] or {} end

-- Все нерасставленные точки — в файл (чтобы потом поправить руками)
function P.FillAuto()
	local n = 0
	for _, def in ipairs(S.Points) do
		if not P.Data.points[def.id] then
			local pos, yaw = P.Get(def.id)
			P.Data.points[def.id] = { pos = pos, yaw = yaw, r = def.r }
			n = n + 1
		end
	end
	return n
end

hook.Add("Initialize", "ws.points", function() P.Load() end)
hook.Add("PostCleanupMap", "ws.points", function() P.Auto = {} end)
P.Load()
