--[[
	Отрисовка своих моделей (tools/content/props.py → cl_mesh_data.lua + materials/whitesilence/props).

	WS.Props.Draw(ent, id)  — нарисовать сетку id в системе координат сущности.
	Освещение считается как у моделей движка: «кубик» света в точке (6 направлений, render.ComputeLighting +
	динамические источники — фонари, ПНВ) и смешивание по нормали вершины; цвет запекается в сетку и
	пересчитывается, когда свет вокруг заметно меняется или предмет повернули.
]]

local P = WS.Props or {}
WS.Props = P

local DIRS = { Vector(1, 0, 0), Vector(-1, 0, 0), Vector(0, 1, 0), Vector(0, -1, 0), Vector(0, 0, 1), Vector(0, 0, -1) }
local cache = setmetatable({}, { __mode = "k" })   -- [ent] = { mesh, cube, ang, t }
local mats = {}

local function material(id)
	if not mats[id] then mats[id] = Material("whitesilence/props/" .. id) end
	return mats[id]
end

local function lightCube(pos)
	local c = {}
	for i, d in ipairs(DIRS) do
		local l = render.ComputeLighting(pos, d) + render.ComputeDynamicLighting(pos, d)
		c[i] = l
	end
	return c
end

local function cubeDiff(a, b)
	local m = 0
	for i = 1, 6 do
		m = math.max(m, math.abs(a[i].x - b[i].x) + math.abs(a[i].y - b[i].y) + math.abs(a[i].z - b[i].z))
	end
	return m
end

-- свет по нормали n (мировой): формула ambient cube Source
local function shade(cube, n)
	local x, y, z = n.x * n.x, n.y * n.y, n.z * n.z
	local cx = n.x >= 0 and cube[1] or cube[2]
	local cy = n.y >= 0 and cube[3] or cube[4]
	local cz = n.z >= 0 and cube[5] or cube[6]
	return cx * x + cy * y + cz * z
end

local function build(id, cube, ang, fullbright)
	local d = WS.MeshData[id]
	local v, t = d.v, d.t
	local m = Mesh()
	local tris = #t / 3
	local rotm = Matrix()
	rotm:SetAngles(ang)
	mesh.Begin(m, MATERIAL_TRIANGLES, tris)
	for i = 1, #t do
		local k = t[i] * 8
		local n = Vector(v[k + 4], v[k + 5], v[k + 6])
		local r, g, b = 255, 255, 255
		if not fullbright then
			local l = shade(cube, rotm * n)
			-- немного «заполняющего» света, чтобы в тени предмет не пропадал совсем
			r = math.min(255, (l.x * 1.15 + 0.035) * 255)
			g = math.min(255, (l.y * 1.15 + 0.035) * 255)
			b = math.min(255, (l.z * 1.15 + 0.04) * 255)
		end
		mesh.Position(Vector(v[k + 1], v[k + 2], v[k + 3]))
		mesh.Normal(n)
		mesh.TexCoord(0, v[k + 7], v[k + 8])
		mesh.Color(r, g, b, 255)
		mesh.AdvanceVertex()
	end
	mesh.End()
	return m
end

function P.Draw(ent, id)
	local d = WS.MeshData and WS.MeshData[id]
	if not d then return false end
	local c = cache[ent]
	local now = RealTime()
	if not c or c.id ~= id or now > c.next then
		local pos = ent:LocalToWorld(ent:OBBCenter())
		local cube = lightCube(pos)
		local ang = ent:GetAngles()
		local turned = c and (math.abs(math.AngleDifference(ang.y, c.ang.y)) + math.abs(math.AngleDifference(ang.p, c.ang.p))
			+ math.abs(math.AngleDifference(ang.r, c.ang.r))) > 4
		if not c or c.id ~= id or turned or cubeDiff(cube, c.cube) > 0.04 then
			if c and c.mesh then c.mesh:Destroy() end
			c = { id = id, mesh = build(id, cube, ang, d.fullbright), cube = cube, ang = ang }
			cache[ent] = c
		end
		c.next = now + (ent:GetVelocity():LengthSqr() > 1 and 0.1 or 0.4)
	end
	cam.PushModelMatrix(ent:GetWorldTransformMatrix())
		render.SetMaterial(material(id))
		c.mesh:Draw()
	cam.PopModelMatrix()
	return true
end

function P.Release(ent)
	local c = cache[ent]
	if c and c.mesh then c.mesh:Destroy() end
	cache[ent] = nil
end

-- Значок предмета для интерфейса: модель в 2D (своя камера, без мира)
function P.DrawIcon(id, x, y, w, h, yaw)
	local d = WS.MeshData and WS.MeshData[id]
	local def = P.Defs and P.Defs[id]
	if not d or not def then return end
	P.IconMeshes = P.IconMeshes or {}
	if not P.IconMeshes[id] then
		local cube = {}
		local key = { Vector(0.75, 0.75, 0.78), Vector(0.32, 0.33, 0.38), Vector(0.55, 0.56, 0.6), Vector(0.45, 0.46, 0.5), Vector(0.95, 0.95, 0.98), Vector(0.22, 0.22, 0.25) }
		for i = 1, 6 do cube[i] = key[i] end
		P.IconMeshes[id] = build(id, cube, Angle(0, 0, 0), d.fullbright)
	end
	local mins, maxs = def.mins, def.maxs
	local center = (mins + maxs) * 0.5
	local size = (maxs - mins):Length()
	local ang = Angle(22, (yaw or 215), 0)
	local pos = center - ang:Forward() * size * 1.6
	cam.Start3D(pos, ang, 34, x, y, w, h, 1, size * 6)
		render.SuppressEngineLighting(true)
		render.SetMaterial(material(id))
		P.IconMeshes[id]:Draw()
		render.SuppressEngineLighting(false)
	cam.End3D()
end
