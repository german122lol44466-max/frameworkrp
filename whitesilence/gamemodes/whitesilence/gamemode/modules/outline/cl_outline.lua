--[[
	Подсветка своих: контур товарищей сквозь стены — модель целиком, оружие в руках и всё, что на них надето
	(дочерние сущности). Внутри силуэта — штриховка из материала whitesilence/fx/outline_fill.

	Как рисуется (своя замена halo):
	  1) силуэты в render target (белый материал, окрашенный цветом группы), без глубины мира — значит, видны
	     сквозь стены;
	  2) по альфе силуэта в трафарете (stencil) отмечаются пиксели «внутри»;
	  3) размытая копия силуэта рисуется снаружи трафарета — получается мягкий контур;
	  4) внутри — слабая штриховка, сильнее, если товарищ за препятствием.
	Цвета: свой отряд — золото, остальные бойцы — холодный голубой. ws_outline 0 — выключить.
]]

local O = {}
WS.Outline = O

local enabled = CreateClientConVar("ws_outline", "1", true, false, "Контур товарищей сквозь стены", 0, 1)
local MAX_DIST = 6000

O.Colors = {
	squad = Color(236, 196, 110),
	ally = Color(130, 190, 240),
	down = Color(220, 80, 70),
}

local rtSil, rtBlur, matSil, matBlur, matCut, matFill, matWhite
local rw, rh

local function ensure()
	if rtSil and rw == ScrW() and rh == ScrH() then return true end
	rw, rh = ScrW(), ScrH()
	local flags = 2 + 256 + 32768   -- точечная выборка, без мипов, с альфой
	rtSil = GetRenderTargetEx("ws_outline_sil_" .. rw, rw, rh, RT_SIZE_NO_CHANGE, MATERIAL_RT_DEPTH_SEPARATE, flags, 0, IMAGE_FORMAT_RGBA8888)
	rtBlur = GetRenderTargetEx("ws_outline_blur_" .. rw, rw / 2, rh / 2, RT_SIZE_NO_CHANGE, MATERIAL_RT_DEPTH_NONE, 2 + 256, 0, IMAGE_FORMAT_RGBA8888)
	matSil = CreateMaterial("ws_outline_silm_" .. rw, "UnlitGeneric", {
		["$basetexture"] = rtSil:GetName(), ["$translucent"] = "1", ["$vertexalpha"] = "1", ["$vertexcolor"] = "1" })
	matBlur = CreateMaterial("ws_outline_blurm_" .. rw, "UnlitGeneric", {
		["$basetexture"] = rtBlur:GetName(), ["$additive"] = "1", ["$vertexalpha"] = "1", ["$vertexcolor"] = "1" })
	-- трафарет: пишем только там, где альфа силуэта есть
	matCut = CreateMaterial("ws_outline_cut_" .. rw, "UnlitGeneric", {
		["$basetexture"] = rtSil:GetName(), ["$alphatest"] = "1", ["$alphatestreference"] = "0.3" })
	matFill = Material("whitesilence/fx/outline_fill")
	matWhite = Material("models/debug/debugwhite")
	return true
end

-- Кого подсвечивать: { ent, color, hidden }
local function targets()
	local me = LocalPlayer()
	local out = {}
	local eye = EyePos()
	local myLobby = WS.Lobby.Id(me)
	local spectating = me:GetNW2Bool("ws_spectating", false)
	for _, p in ipairs(player.GetAll()) do
		if p ~= me and p:Alive() and WS.Lobby.InGame(p) and not p:GetNoDraw() then
			local d = eye:Distance(p:GetPos())
			if d < MAX_DIST and not (spectating and p == me:GetObserverTarget() and d < 120) then
				local squad = myLobby ~= 0 and WS.Lobby.Id(p) == myLobby
				local col = squad and O.Colors.squad or O.Colors.ally
				if p:Health() < p:GetMaxHealth() * 0.3 then col = O.Colors.down end
				local tr = util.TraceLine({ start = eye, endpos = p:EyePos(), filter = { me, p }, mask = MASK_OPAQUE })
				out[#out + 1] = { ent = p, col = col, hidden = tr.Hit, dist = d }
			end
		end
	end
	return out
end

local function drawEnt(e)
	if not IsValid(e) or e:GetNoDraw() then return end
	e:DrawModel()
end

local function drawAll(t)
	local p = t.ent
	drawEnt(p)
	drawEnt(p:GetActiveWeapon())
	for _, c in ipairs(p:GetChildren()) do
		if c ~= p:GetActiveWeapon() then drawEnt(c) end
	end
end

hook.Add("PostDrawEffects", "ws.outline", function()
	if not enabled:GetBool() then return end
	local me = LocalPlayer()
	if not IsValid(me) or not WS.Lobby.InGame(me) or (WS.Menu and WS.Menu.IsOpen()) then return end
	local list = targets()
	if #list == 0 or not ensure() then return end

	-- 1. силуэты
	render.PushRenderTarget(rtSil)
	render.OverrideAlphaWriteEnable(true, true)
	render.Clear(0, 0, 0, 0, true, true)
	cam.Start3D()
		render.SuppressEngineLighting(true)
		render.MaterialOverride(matWhite)
		for _, t in ipairs(list) do
			render.SetColorModulation(t.col.r / 255, t.col.g / 255, t.col.b / 255)
			drawAll(t)
		end
		render.MaterialOverride(nil)
		render.SetColorModulation(1, 1, 1)
		render.SuppressEngineLighting(false)
	cam.End3D()
	render.OverrideAlphaWriteEnable(false)
	render.PopRenderTarget()

	-- 2. размытая копия
	render.PushRenderTarget(rtBlur)
	render.Clear(0, 0, 0, 0)
	render.SetMaterial(matSil)
	render.DrawScreenQuad()
	render.PopRenderTarget()
	render.BlurRenderTarget(rtBlur, 3, 3, 2)

	-- 3. трафарет по силуэту
	render.SetStencilEnable(true)
	render.SetStencilWriteMask(255)
	render.SetStencilTestMask(255)
	render.ClearStencil()
	render.SetStencilReferenceValue(1)
	render.SetStencilCompareFunction(STENCIL_ALWAYS)
	render.SetStencilPassOperation(STENCIL_REPLACE)
	render.SetStencilFailOperation(STENCIL_KEEP)
	render.SetStencilZFailOperation(STENCIL_KEEP)
	render.OverrideColorWriteEnable(true, false)
	render.SetMaterial(matCut)
	render.DrawScreenQuad()
	render.OverrideColorWriteEnable(false)

	-- 4. контур снаружи силуэта (дважды — плотнее у края)
	render.SetStencilCompareFunction(STENCIL_NOTEQUAL)
	render.SetStencilPassOperation(STENCIL_KEEP)
	render.SetMaterial(matBlur)
	for _ = 1, 3 do render.DrawScreenQuad() end

	-- 5. штриховка внутри силуэта
	render.SetStencilCompareFunction(STENCIL_EQUAL)
	local anyHidden = false
	for _, t in ipairs(list) do if t.hidden then anyHidden = true end end
	cam.Start2D()
		local a = anyHidden and 70 or 28
		local scroll = (RealTime() * 18) % 64
		surface.SetMaterial(matFill)
		surface.SetDrawColor(255, 255, 255, a)
		surface.DrawTexturedRectUV(0, 0, rw, rh, scroll / 256, 0, rw / 256 + scroll / 256, rh / 256)
	cam.End2D()
	render.SetStencilEnable(false)

	-- 6. подписи над теми, кто за стеной: имя и расстояние
	cam.Start2D()
		for _, t in ipairs(list) do
			if t.hidden then
				local sp = (t.ent:GetPos() + Vector(0, 0, 82)):ToScreen()
				if sp.visible then
					local m = math.floor(t.dist * 0.01905)
					draw.SimpleTextOutlined(WS.Lobby.Name(t.ent) .. "  ·  " .. m .. " м", WS.Font("menusemi", 14), sp.x, sp.y,
						Color(t.col.r, t.col.g, t.col.b, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, 160))
				end
			end
		end
	cam.End2D()
end)
