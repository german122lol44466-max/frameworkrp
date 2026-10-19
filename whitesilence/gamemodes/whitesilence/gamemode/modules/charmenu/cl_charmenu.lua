--[[
	Q — снаряжение и состояние (нажать — открыть, Q или Esc — закрыть).
	  слева   — имя, отряд, здоровье, броня, выносливость, ПНВ, кровотечение, вес, состояние, отряд;
	  в центре — модель бойца;
	  справа  — оружие в руках, рюкзак-сетка: перетаскивание мышью, R — повернуть, вынести за окно —
	            выбросить, двойной клик — использовать, ПКМ — меню; описание предмета под сеткой.
	Вместо меню спавна Sandbox; суперадмину с зажатым Shift — обычное меню спавна.
]]

local L = WS.Lobby
local UI = WS.UI
local E = WS.Ease
local C = WS.Config
local I = WS.Inv
local panel, openT, closing
local drag, hover

local function icon(n) return UI.Mat("whitesilence/icons/" .. n .. ".png", "smooth") end

local function condition(ply)
	local list = {}
	local hp = ply:Health() / math.max(ply:GetMaxHealth(), 1)
	if hp >= 0.9 then list[#list + 1] = { "Здоров", Color(140, 210, 150) }
	elseif hp >= 0.5 then list[#list + 1] = { "Ранен", Color(226, 190, 120) }
	elseif hp >= 0.25 then list[#list + 1] = { "Тяжело ранен", Color(230, 130, 90) }
	else list[#list + 1] = { "При смерти", Color(230, 80, 70) } end
	local b = ply:GetNW2Int("ws_bleed", 0)
	if b > 0 then list[#list + 1] = { b > 1 and "Сильное кровотечение" or "Кровотечение", Color(230, 80, 70) } end
	if ply:GetNW2Float("ws_pain_until", 0) > CurTime() then list[#list + 1] = { "Обезболен", Color(150, 210, 160) } end
	if WS.Move.Exhausted(ply) then list[#list + 1] = { "Выдохся", Color(230, 130, 90) }
	elseif WS.Move.Stamina(ply) < C.StaminaMax * 0.4 then list[#list + 1] = { "Устал", Color(226, 190, 120) } end
	if ply:GetNW2Float("ws_weight", 0) > I.CarryLight then list[#list + 1] = { "Перегружен", Color(226, 190, 120) } end
	if WS.Vision and WS.Vision.Mode then list[#list + 1] = { WS.Vision.Mode == "nvg" and "ПНВ включён" or "Тепловизор включён", Color(140, 220, 160) } end
	return list
end

local function statBar(x, y, w, label, ic, frac, col, valueText)
	local s = ScrH() / 1080
	surface.SetMaterial(icon(ic))
	surface.SetDrawColor(col.r, col.g, col.b, 230)
	surface.DrawTexturedRect(x, y, 22 * s, 22 * s)
	draw.SimpleText(label, WS.Font("menu", 17), x + 32 * s, y + 11 * s, Color(214, 220, 228), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	draw.SimpleText(valueText, WS.Font("menusemi", 17), x + w, y + 11 * s, col, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	surface.SetDrawColor(255, 255, 255, 30)
	surface.DrawRect(x + 32 * s, y + 26 * s, w - 32 * s, 5 * s)
	surface.SetDrawColor(col.r, col.g, col.b, 230)
	surface.DrawRect(x + 32 * s, y + 26 * s, (w - 32 * s) * math.Clamp(frac, 0, 1), 5 * s)
end

local KIND_COL = {
	ammo_rifle = Color(120, 140, 90), ammo_pistol = Color(170, 140, 90), medkit = Color(190, 70, 60),
	bandage = Color(200, 196, 180), painkillers = Color(210, 130, 60), battery = Color(210, 170, 60),
}

-- ---------------------------------------------------------------- рюкзак (сетка)

local function itemAt(cx, cy)
	for _, it in ipairs(I.Mine) do
		local w, h = I.Size(it)
		if cx >= it.x and cx < it.x + w and cy >= it.y and cy < it.y + h then return it end
	end
end

local function amountText(it)
	local d = I.Def(it.id)
	if d.charges then return it.charges .. "/" .. d.charges end
	if d.ammo then return tostring(it.count) end
	if (it.count or 1) > 1 then return "×" .. it.count end
	return ""
end

local function buildGrid(parent, x, y, cell)
	local g = vgui.Create("DPanel", parent)
	g:SetPos(x, y)
	g:SetSize(cell * I.GridW, cell * I.GridH)
	g.cell = cell
	local function cellOf(mx, my) return math.floor(mx / cell) + 1, math.floor(my / cell) + 1 end
	g.Paint = function(self, w, h)
		local s = ScrH() / 1080
		draw.RoundedBox(4, 0, 0, w, h, Color(255, 255, 255, 6))
		for cy = 0, I.GridH - 1 do
			for cx = 0, I.GridW - 1 do
				surface.SetDrawColor(255, 255, 255, 14)
				surface.DrawOutlinedRect(cx * cell + 1, cy * cell + 1, cell - 2, cell - 2, 1)
			end
		end
		local mx, my = self:CursorPos()
		hover = nil
		for _, it in ipairs(I.Mine) do
			if not (drag and drag.it == it) then
				local iw, ih = I.Size(it)
				local rx, ry, rw, rh = (it.x - 1) * cell + 2, (it.y - 1) * cell + 2, iw * cell - 4, ih * cell - 4
				local over = mx >= rx and mx < rx + rw and my >= ry and my < ry + rh
				if over then hover = it end
				local kc = KIND_COL[it.id] or Color(200, 200, 200)
				draw.RoundedBox(3, rx, ry, rw, rh, Color(kc.r * 0.25, kc.g * 0.25, kc.b * 0.25, over and 230 or 190))
				surface.SetDrawColor(kc.r, kc.g, kc.b, over and 200 or 90)
				surface.DrawOutlinedRect(rx, ry, rw, rh, 1)
				local ax, ay = self:LocalToScreen(rx, ry)
				WS.Props.DrawIcon(I.Def(it.id).mesh, ax + 4, ay + 2, rw - 8, rh - 14 * s, it.rot and 125 or 215)
				draw.SimpleText(amountText(it), WS.Font("menusemi", 13), rx + rw - 4, ry + rh - 2, Color(236, 240, 246, 230), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
			end
		end
		-- перетаскиваемый предмет: призрак на сетке и под курсором
		if drag then
			local w2, h2 = I.Def(drag.it.id).w, I.Def(drag.it.id).h
			if drag.rot then w2, h2 = h2, w2 end
			local gx, gy = cellOf(mx - drag.ox + cell / 2, my - drag.oy + cell / 2)
			local inside = mx >= 0 and my >= 0 and mx < w and my < h
			if inside then
				local ok = I.Fits(I.Mine, gx, gy, w2, h2, drag.it)
				draw.RoundedBox(3, (gx - 1) * cell + 2, (gy - 1) * cell + 2, w2 * cell - 4, h2 * cell - 4,
					ok and Color(120, 220, 140, 50) or Color(230, 80, 70, 60))
			end
			drag.gx, drag.gy, drag.inside = gx, gy, inside
			local ax, ay = self:LocalToScreen(mx - drag.ox, my - drag.oy)
			WS.Props.DrawIcon(I.Def(drag.it.id).mesh, ax, ay, w2 * cell, h2 * cell, drag.rot and 125 or 215)
		end
	end
	g.OnMousePressed = function(self, code)
		local mx, my = self:CursorPos()
		local it = itemAt(cellOf(mx, my))
		if not it then return end
		if code == MOUSE_RIGHT then
			local m = DermaMenu()
			local d = I.Def(it.id)
			if d.use then m:AddOption("Использовать", function() I.Use(it) end) end
			m:AddOption("Выбросить", function() I.Drop(it) end)
			m:Open()
			return
		end
		if code ~= MOUSE_LEFT then return end
		-- двойной клик — использовать
		if self.lastClick and self.lastClick.it == it and RealTime() - self.lastClick.t < 0.35 then
			I.Use(it)
			self.lastClick = nil
			return
		end
		self.lastClick = { it = it, t = RealTime() }
		drag = { it = it, ox = mx - (it.x - 1) * cell, oy = my - (it.y - 1) * cell, rot = it.rot }
		self:MouseCapture(true)
		surface.PlaySound("ui/buttonrollover.wav")
	end
	g.OnMouseReleased = function(self, code)
		if code ~= MOUSE_LEFT or not drag then return end
		self:MouseCapture(false)
		local d = drag
		drag = nil
		if d.inside then
			if d.gx ~= d.it.x or d.gy ~= d.it.y or d.rot ~= d.it.rot then
				local w2, h2 = I.Def(d.it.id).w, I.Def(d.it.id).h
				if d.rot then w2, h2 = h2, w2 end
				if I.Fits(I.Mine, d.gx, d.gy, w2, h2, d.it) then
					d.it.x, d.it.y, d.it.rot = d.gx, d.gy, d.rot     -- сразу, не дожидаясь сервера
					I.Move(d.it, d.gx, d.gy, d.rot)
					surface.PlaySound("ui/buttonclick.wav")
				end
			end
		else
			-- вынесли за пределы окна — выбросить
			local px, py = parent:CursorPos()
			if px < 0 or py < 0 or px > parent:GetWide() or py > parent:GetTall() then I.Drop(d.it) end
		end
	end
	g.Think = function()
		local r = input.IsKeyDown(KEY_R)
		if drag and r and not g.rWas then drag.rot = not drag.rot end
		g.rWas = r
	end
	return g
end

-- ---------------------------------------------------------------- окно

local function close()
	if IsValid(panel) and not closing then closing = RealTime() end
	drag = nil
end

local function open()
	local s = ScrH() / 1080
	local ply = LocalPlayer()
	if IsValid(panel) then panel:Remove() end
	panel = vgui.Create("DPanel")
	local w, h = 1500 * s, 760 * s
	panel:SetSize(w, h)
	panel:Center()
	openT, closing = RealTime(), nil
	WS.Audio.Play("whitesilence/game/select.ogg", { volume = 0.4 })

	local mdl = vgui.Create("DModelPanel", panel)
	mdl:SetPos(400 * s, 20 * s)
	mdl:SetSize(340 * s, h - 40 * s)
	mdl:SetModel(ply:GetModel())
	mdl:SetFOV(30)
	mdl:SetCamPos(Vector(110, 0, 44))
	mdl:SetLookAt(Vector(0, 0, 38))
	mdl:SetAmbientLight(Color(40, 46, 56))
	mdl:SetDirectionalLight(BOX_TOP, Color(190, 200, 215))
	mdl:SetDirectionalLight(BOX_FRONT, Color(90, 100, 120))
	mdl.LayoutEntity = function(self, ent)
		ent:SetAngles(Angle(0, 20 + math.sin(RealTime() * 0.5) * 25, 0))
		local seq = ent:LookupSequence("idle_ar2")
		if seq and seq >= 0 and ent:GetSequence() ~= seq then ent:ResetSequence(seq) end
		ent:FrameAdvance(FrameTime())
	end
	if IsValid(mdl.Entity) then
		mdl.Entity:SetSkin(ply:GetSkin())
		for _, b in pairs(ply:GetBodyGroups()) do mdl.Entity:SetBodygroup(b.id, ply:GetBodygroup(b.id)) end
	end

	local cell = 78 * s
	local gx, gy = 780 * s, 250 * s
	buildGrid(panel, gx, gy, cell)

	panel.Paint = function(self, pw, ph)
		local a = closing and (1 - E.Smooth((RealTime() - closing) / 0.15)) or E.Smooth((RealTime() - openT) / 0.2)
		self:SetAlpha(255 * a)
		if closing and RealTime() - closing > 0.15 then self:Remove() return end
		if not IsValid(ply) then return end
		draw.RoundedBox(6, 0, 0, pw, ph, Color(6, 8, 12, 232))
		surface.SetDrawColor(255, 255, 255, 16)
		surface.DrawOutlinedRect(0, 0, pw, ph, 1)
		surface.SetDrawColor(196, 38, 38, 220)
		surface.DrawRect(0, 0, 90 * s, 3 * s)
		surface.SetMaterial(UI.Mat(WS.Intro.Path .. "flake.png", "smooth"))
		surface.SetDrawColor(120, 150, 190, 30)
		surface.DrawTexturedRect(400 * s, 80 * s, 340 * s, 600 * s)

		-- слева: состояние
		local x, y, cw = 30 * s, 30 * s, 340 * s
		draw.SimpleText(WS.Upper(L.Name(ply)), WS.Font("menubold", 30), x, y, Color(238, 240, 244))
		local sub = "Боец МОГ «Буран»"
		if L.Id(ply) ~= 0 then sub = sub .. (L.IsLeader(ply) and " · командир" or " · стрелок") end
		local title = WS.Ach and WS.Ach.TitleOf and WS.Ach.TitleOf(ply)
		draw.SimpleText(sub, WS.Font("menulight", 17), x, y + 40 * s, Color(170, 178, 190))
		if title then draw.SimpleText("«" .. title .. "»", WS.Font("menusemi", 15), x, y + 62 * s, Color(226, 190, 120)) end
		y = y + 100 * s
		local hp, mx = math.max(ply:Health(), 0), math.max(ply:GetMaxHealth(), 1)
		statBar(x, y, cw, "Здоровье", "health", hp / mx, hp / mx < 0.3 and Color(230, 90, 80) or Color(236, 239, 244), tostring(hp))
		statBar(x, y + 50 * s, cw, "Броня", "armor", ply:Armor() / 100, Color(170, 196, 228), tostring(ply:Armor()))
		local st = WS.Move.Stamina(ply)
		statBar(x, y + 100 * s, cw, "Выносливость", "stamina", st / C.StaminaMax, Color(226, 190, 120), math.Round(st) .. "%")
		local bat = WS.Vision and WS.Vision.Battery or C.NVGBattery
		statBar(x, y + 150 * s, cw, "Заряд ПНВ", "battery", bat / C.NVGBattery, Color(130, 220, 150), math.Round(bat / C.NVGBattery * 100) .. "%")
		local wt = ply:GetNW2Float("ws_weight", 0)
		statBar(x, y + 200 * s, cw, "Вес снаряжения", "steps", wt / I.CarryMax, wt > I.CarryLight and Color(226, 190, 120) or Color(170, 178, 190),
			string.format("%.1f / %d кг", wt, I.CarryMax))

		y = y + 262 * s
		draw.SimpleText("СОСТОЯНИЕ", WS.Font("menusemi", 15), x, y, Color(150, 158, 170))
		local cx, cy = x, y + 24 * s
		for _, c in ipairs(condition(ply)) do
			surface.SetFont(WS.Font("menu", 16))
			local tw = surface.GetTextSize(c[1])
			if cx + tw + 20 * s > x + cw then cx, cy = x, cy + 32 * s end
			draw.RoundedBox(3, cx, cy, tw + 20 * s, 26 * s, Color(c[2].r, c[2].g, c[2].b, 30))
			draw.SimpleText(c[1], WS.Font("menu", 16), cx + 10 * s, cy + 13 * s, c[2], TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			cx = cx + tw + 28 * s
		end
		y = cy + 50 * s
		draw.SimpleText("ОТРЯД", WS.Font("menusemi", 15), x, y, Color(150, 158, 170))
		y = y + 24 * s
		for _, m in ipairs(L.Members(L.Id(ply))) do
			local alive = m:Alive() and L.InGame(m)
			local mhp = alive and math.max(m:Health(), 0) / math.max(m:GetMaxHealth(), 1) or 0
			draw.SimpleText(L.Name(m), WS.Font("menu", 16), x, y, m == ply and Color(226, 190, 120) or Color(222, 226, 234))
			draw.SimpleText(alive and (math.Round(mhp * 100) .. "%") or (L.InGame(m) and "наблюдает" or "в меню"), WS.Font("menulight", 15),
				x + cw, y, alive and Color(170, 178, 190) or Color(220, 100, 90), TEXT_ALIGN_RIGHT)
			surface.SetDrawColor(255, 255, 255, 25)
			surface.DrawRect(x, y + 22 * s, cw, 3 * s)
			surface.SetDrawColor(140, 210, 150, 200)
			surface.DrawRect(x, y + 22 * s, cw * mhp, 3 * s)
			y = y + 32 * s
		end

		-- справа: оружие
		local ex, ey = gx, 30 * s
		draw.SimpleText("В РУКАХ", WS.Font("menusemi", 15), ex, ey, Color(150, 158, 170))
		ey = ey + 26 * s
		for i, wep in ipairs(ply:GetWeapons()) do
			if i > 2 then break end
			local bx = ex + (i - 1) * 236 * s
			draw.RoundedBox(4, bx, ey, 228 * s, 150 * s, Color(255, 255, 255, wep == ply:GetActiveWeapon() and 18 or 8))
			local name = wep.GetPrintName and wep:GetPrintName() or wep:GetClass()
			draw.SimpleText(name, WS.Font("menusemi", 16), bx + 10 * s, ey + 8 * s, Color(222, 226, 234))
			local clip = wep:Clip1()
			if clip >= 0 then
				draw.SimpleText(clip .. " / " .. ply:GetAmmoCount(wep:GetPrimaryAmmoType()), WS.Font("menulight", 15),
					bx + 218 * s, ey + 142 * s, Color(170, 178, 190), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
			end
		end
		draw.SimpleText("РЮКЗАК", WS.Font("menusemi", 15), gx, gy - 24 * s, Color(150, 158, 170))
		draw.SimpleText("ЛКМ — перенести · R — повернуть · двойной клик — использовать · ПКМ — меню · за окно — выбросить",
			WS.Font("menulight", 13), gx + cell * I.GridW, gy - 22 * s, Color(130, 138, 150), TEXT_ALIGN_RIGHT)

		-- описание предмета
		local it = (drag and drag.it) or hover
		local dy = gy + cell * I.GridH + 16 * s
		if it then
			local d = I.Def(it.id)
			draw.SimpleText(d.name, WS.Font("menubold", 20), gx, dy, Color(238, 240, 244))
			draw.SimpleText(string.format("%.2f кг", I.Weight(it)), WS.Font("menulight", 15), gx + cell * I.GridW, dy + 4 * s, Color(170, 178, 190), TEXT_ALIGN_RIGHT)
			local lay = UI.Layout(d.desc, WS.Font("menulight", 16), cell * I.GridW)
			local ly = dy + 30 * s
			for _, line in ipairs(lay.lines) do
				draw.SimpleText(table.concat(line.chars), WS.Font("menulight", 16), gx, ly, Color(190, 196, 206))
				ly = ly + 20 * s
			end
			if d.quick then draw.SimpleText("Быстрый слот: " .. d.quick, WS.Font("menusemi", 14), gx, ly + 4 * s, Color(226, 190, 120)) end
		end
		draw.SimpleText("Q — закрыть", WS.Font("menulight", 14), pw - 20 * s, ph - 16 * s, Color(130, 138, 150), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)

		-- Esc — закрыть
		if gui.IsGameUIVisible() then gui.HideGameUI() close() end
	end
	-- оружие моделью в карточках
	panel.PaintOver = function(self, pw, ph)
		local ex, ey = gx, 56 * s
		for i, wep in ipairs(ply:GetWeapons()) do
			if i > 2 then break end
			local bx = ex + (i - 1) * 236 * s
			local ax, ay = self:LocalToScreen(bx + 8 * s, ey + 30 * s)
			if WS.Inv.WeaponIcon then WS.Inv.WeaponIcon(wep, ax, ay, 212 * s, 96 * s, 1) end
		end
	end
	panel:MakePopup()
	panel:SetKeyboardInputEnabled(false)
end

local function allowSandbox()
	return LocalPlayer():IsSuperAdmin() and input.IsKeyDown(KEY_LSHIFT)
end

hook.Add("OnSpawnMenuOpen", "ws.charmenu", function()
	if allowSandbox() then return end
	if IsValid(panel) and not closing then
		close()
	elseif WS.Lobby.InGame(LocalPlayer()) and LocalPlayer():Alive() then
		open()
	end
	return false
end)

hook.Add("OnSpawnMenuClose", "ws.charmenu", function()
	if allowSandbox() then return end
	return false
end)

-- погиб или вышел в меню — закрыть
hook.Add("Think", "ws.charmenu", function()
	if IsValid(panel) and not closing then
		local ply = LocalPlayer()
		if not ply:Alive() or not WS.Lobby.InGame(ply) then close() end
	end
end)
