--[[
	Иконки предметов — настоящие модели, отрисованные в текстуру (render target) один раз.
	NYRP.ItemIconMat(id) -> Material
]]

local cache = {}
local iconEnts = {}

local function model(path)
	local e = iconEnts[path]
	if not IsValid(e) then
		e = ClientsideModel(path, RENDERGROUP_OPAQUE)
		if not IsValid(e) then return end
		e:SetNoDraw(true)
		iconEnts[path] = e
	end
	return e
end

local function render3D(def, size)
	local ent = model(def.model)
	if not IsValid(ent) then return end
	ent:SetPos(vector_origin)
	ent:SetAngles(angle_zero)
	if def.skin then ent:SetSkin(def.skin) end
	local mn, mx = ent:GetModelBounds()
	local center = (mn + mx) / 2
	local radius = (mx - mn):Length() / 2
	local ang = def.icon and def.icon.ang or Angle(28, 220, 0)
	local fov = 26
	local dist = radius / math.sin(math.rad(fov / 2)) / (def.icon and def.icon.zoom or 1)
	local pos = center - ang:Forward() * dist

	cam.Start3D(pos, ang, fov, 0, 0, size, size, 1, dist * 4)
	render.SuppressEngineLighting(true)
	render.SetLightingOrigin(center)
	render.ResetModelLighting(0.28, 0.29, 0.33)
	render.SetModelLighting(BOX_TOP, 1.25, 1.2, 1.1)
	render.SetModelLighting(BOX_FRONT, 0.75, 0.75, 0.8)
	render.SetModelLighting(BOX_RIGHT, 0.55, 0.6, 0.75)
	render.SetModelLighting(BOX_LEFT, 0.45, 0.42, 0.4)
	render.SetColorModulation(1, 1, 1)
	render.SetBlend(1)
	ent:SetupBones()
	ent:DrawModel()
	render.SuppressEngineLighting(false)
	cam.End3D()
	return true
end

function NYRP.ItemIconMat(id)
	local c = cache[id]
	if c and c.ready then return c.mat end
	local def = NYRP.Items.Get(id)
	if not def then return end
	if not c then
		local rt = GetRenderTargetEx("nyrp_icon_" .. id, 256, 256, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_SEPARATE,
			bit.bor(4, 8, 256), 0, IMAGE_FORMAT_RGBA8888)
		local mat = CreateMaterial("nyrp_iconmat_" .. id, "UnlitGeneric", {
			["$basetexture"] = rt:GetName(), ["$translucent"] = 1, ["$vertexcolor"] = 1, ["$vertexalpha"] = 1,
		})
		c = { rt = rt, mat = mat }
		cache[id] = c
	end
	render.PushRenderTarget(c.rt)
	render.OverrideAlphaWriteEnable(true, true)
	render.ClearDepth()
	render.Clear(0, 0, 0, 0)
	local ok = render3D(def, 256)
	render.OverrideAlphaWriteEnable(false)
	render.PopRenderTarget()
	c.ready = ok
	return c.mat
end

-- Иконка по пути модели (оружие и т.п.). key — уникальное имя кэша.
function NYRP.ModelIconMat(path, ang, zoom)
	if not path or path == "" then return end
	local key = "mdl_" .. util.CRC(path)
	local c = cache[key]
	if c and c.ready then return c.mat end
	if not c then
		local rt = GetRenderTargetEx("nyrp_icon_" .. key, 256, 256, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_SEPARATE,
			bit.bor(4, 8, 256), 0, IMAGE_FORMAT_RGBA8888)
		local mat = CreateMaterial("nyrp_iconmat_" .. key, "UnlitGeneric", {
			["$basetexture"] = rt:GetName(), ["$translucent"] = 1, ["$vertexcolor"] = 1, ["$vertexalpha"] = 1,
		})
		c = { rt = rt, mat = mat }
		cache[key] = c
	end
	render.PushRenderTarget(c.rt)
	render.OverrideAlphaWriteEnable(true, true)
	render.ClearDepth()
	render.Clear(0, 0, 0, 0)
	c.ready = render3D({ model = path, icon = { ang = ang or Angle(8, 90, 0), zoom = zoom or 1.05 } }, 256)
	render.OverrideAlphaWriteEnable(false)
	render.PopRenderTarget()
	return c.mat
end

-- Нарисовать иконку предмета в прямоугольнике.
function NYRP.DrawItemIcon(id, x, y, w, h, alpha)
	local mat = NYRP.ItemIconMat(id)
	if not mat then return end
	surface.SetMaterial(mat)
	surface.SetDrawColor(255, 255, 255, alpha or 255)
	local s = math.min(w, h)
	surface.DrawTexturedRect(x + (w - s) / 2, y + (h - s) / 2, s, s)
end

-- Сброс после смены разрешения/потери устройства.
hook.Add("OnScreenSizeChanged", "nyrp.icons", function()
	for _, c in pairs(cache) do c.ready = false end
end)
