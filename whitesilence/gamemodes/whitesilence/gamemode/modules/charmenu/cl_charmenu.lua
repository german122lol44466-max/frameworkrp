--[[
	Q (пока держишь) — состояние персонажа: модель бойца, имя и отряд, здоровье, броня, выносливость,
	заряд ПНВ, общее состояние, снаряжение с патронами и состав отряда со здоровьем.
	Вместо стандартного меню спавна Sandbox; суперадмину с зажатым Shift — обычное меню спавна.
]]

local L = WS.Lobby
local UI = WS.UI
local E = WS.Ease
local C = WS.Config
local panel, openT, closing

local function icon(n) return UI.Mat("whitesilence/icons/" .. n .. ".png", "smooth") end

local function condition(ply)
	local list = {}
	local hp = ply:Health() / math.max(ply:GetMaxHealth(), 1)
	if hp >= 0.9 then list[#list + 1] = { "Здоров", Color(140, 210, 150) }
	elseif hp >= 0.5 then list[#list + 1] = { "Ранен", Color(226, 190, 120) }
	elseif hp >= 0.25 then list[#list + 1] = { "Тяжело ранен", Color(230, 130, 90) }
	else list[#list + 1] = { "При смерти", Color(230, 80, 70) } end
	if WS.Move.Exhausted(ply) then list[#list + 1] = { "Выдохся", Color(230, 130, 90) }
	elseif WS.Move.Stamina(ply) < C.StaminaMax * 0.4 then list[#list + 1] = { "Устал", Color(226, 190, 120) } end
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

local function open()
	local s = ScrH() / 1080
	local ply = LocalPlayer()
	if IsValid(panel) then panel:Remove() end
	panel = vgui.Create("DPanel")
	local w, h = 1100 * s, 640 * s
	panel:SetSize(w, h)
	panel:Center()
	openT, closing = RealTime(), nil

	local mdl = vgui.Create("DModelPanel", panel)
	mdl:SetPos(10 * s, 10 * s)
	mdl:SetSize(380 * s, h - 20 * s)
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

	panel.Paint = function(self, pw, ph)
		local a = closing and (1 - E.Smooth((RealTime() - closing) / 0.15)) or E.Smooth((RealTime() - openT) / 0.2)
		self:SetAlpha(255 * a)
		if closing and RealTime() - closing > 0.15 then self:Remove() return end
		if not IsValid(ply) then return end
		draw.RoundedBox(6, 0, 0, pw, ph, Color(6, 8, 12, 225))
		surface.SetDrawColor(255, 255, 255, 16)
		surface.DrawOutlinedRect(0, 0, pw, ph, 1)
		surface.SetDrawColor(196, 38, 38, 220)
		surface.DrawRect(0, 0, 90 * s, 3 * s)
		-- силуэт стоит на тёмной «подставке»
		surface.SetMaterial(UI.Mat(WS.Intro.Path .. "flake.png", "smooth"))
		surface.SetDrawColor(120, 150, 190, 30)
		surface.DrawTexturedRect(20 * s, 80 * s, 360 * s, 520 * s)

		local x, y, cw = 420 * s, 30 * s, 330 * s
		draw.SimpleText(WS.Upper(L.Name(ply)), WS.Font("menubold", 32), x, y, Color(238, 240, 244))
		local sub = "Боец спецподразделения"
		if L.Id(ply) ~= 0 then sub = sub .. " · отряд №" .. L.Id(ply) .. (L.IsLeader(ply) and " · командир" or "") end
		draw.SimpleText(sub, WS.Font("menulight", 17), x, y + 42 * s, Color(170, 178, 190))

		y = y + 90 * s
		local hp, mx = math.max(ply:Health(), 0), math.max(ply:GetMaxHealth(), 1)
		statBar(x, y, cw, "Здоровье", "health", hp / mx, hp / mx < 0.3 and Color(230, 90, 80) or Color(236, 239, 244), tostring(hp))
		statBar(x, y + 50 * s, cw, "Броня", "armor", ply:Armor() / 100, Color(170, 196, 228), tostring(ply:Armor()))
		local st = WS.Move.Stamina(ply)
		statBar(x, y + 100 * s, cw, "Выносливость", "stamina", st / C.StaminaMax, Color(226, 190, 120), math.Round(st) .. "%")
		local bat = WS.Vision and WS.Vision.Battery or C.NVGBattery
		statBar(x, y + 150 * s, cw, "Заряд ПНВ", "battery", bat / C.NVGBattery, Color(130, 220, 150), math.Round(bat / C.NVGBattery * 100) .. "%")

		y = y + 210 * s
		draw.SimpleText("СОСТОЯНИЕ", WS.Font("menusemi", 15), x, y, Color(150, 158, 170))
		local cx = x
		for _, c in ipairs(condition(ply)) do
			surface.SetFont(WS.Font("menu", 16))
			local tw = surface.GetTextSize(c[1])
			draw.RoundedBox(3, cx, y + 24 * s, tw + 20 * s, 26 * s, Color(c[2].r, c[2].g, c[2].b, 30))
			draw.SimpleText(c[1], WS.Font("menu", 16), cx + 10 * s, y + 37 * s, c[2], TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			cx = cx + tw + 28 * s
		end

		-- снаряжение
		local ex = 790 * s
		y = 30 * s
		draw.SimpleText("СНАРЯЖЕНИЕ", WS.Font("menusemi", 15), ex, y, Color(150, 158, 170))
		y = y + 26 * s
		for _, wep in ipairs(ply:GetWeapons()) do
			local name = wep.GetPrintName and wep:GetPrintName() or wep:GetClass()
			draw.SimpleText(name, WS.Font("menu", 17), ex, y, Color(222, 226, 234))
			local clip = wep:Clip1()
			if clip >= 0 then
				draw.SimpleText(clip .. " / " .. ply:GetAmmoCount(wep:GetPrimaryAmmoType()), WS.Font("menulight", 16),
					pw - 24 * s, y, Color(170, 178, 190), TEXT_ALIGN_RIGHT)
			end
			y = y + 26 * s
		end

		-- отряд
		y = math.max(y + 20 * s, 300 * s)
		draw.SimpleText("ОТРЯД", WS.Font("menusemi", 15), ex, y, Color(150, 158, 170))
		y = y + 26 * s
		for _, m in ipairs(L.Members(L.Id(ply))) do
			local alive = m:Alive() and L.InGame(m)
			local mhp = alive and math.max(m:Health(), 0) / math.max(m:GetMaxHealth(), 1) or 0
			draw.SimpleText(L.Name(m), WS.Font("menu", 16), ex, y, m == ply and Color(226, 190, 120) or Color(222, 226, 234))
			draw.SimpleText(alive and (math.Round(mhp * 100) .. "%") or (L.InGame(m) and "погиб" or "в меню"), WS.Font("menulight", 15),
				pw - 24 * s, y, alive and Color(170, 178, 190) or Color(220, 100, 90), TEXT_ALIGN_RIGHT)
			surface.SetDrawColor(255, 255, 255, 25)
			surface.DrawRect(ex, y + 22 * s, pw - 24 * s - ex, 3 * s)
			surface.SetDrawColor(140, 210, 150, 200)
			surface.DrawRect(ex, y + 22 * s, (pw - 24 * s - ex) * mhp, 3 * s)
			y = y + 34 * s
		end
		draw.SimpleText("Q — закрыть", WS.Font("menulight", 14), pw - 20 * s, ph - 16 * s, Color(130, 138, 150), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
	end
	panel:MakePopup()
	panel:SetKeyboardInputEnabled(false)
end

local function allowSandbox()
	return LocalPlayer():IsSuperAdmin() and input.IsKeyDown(KEY_LSHIFT)
end

hook.Add("OnSpawnMenuOpen", "ws.charmenu", function()
	if allowSandbox() then return end
	if WS.Lobby.InGame(LocalPlayer()) and LocalPlayer():Alive() then open() end
	return false
end)

hook.Add("OnSpawnMenuClose", "ws.charmenu", function()
	if IsValid(panel) and not closing then closing = RealTime() end
	if allowSandbox() then return end
	return false
end)
