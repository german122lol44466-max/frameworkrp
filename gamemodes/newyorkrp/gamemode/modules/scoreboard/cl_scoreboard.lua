--[[
	Список игроков (зажать TAB): панель выезжает слева.
	Лого, правее и выше — онлайн; ниже — игроки: ник Steam и наигранные часы.
	ПКМ по игроку: скопировать SteamID / SteamID64, открыть профиль.
]]

local UI = NYRP.UI
local SB = {}
NYRP.Scoreboard = SB

local function hours(ply)
	local sec = ply:GetNW2Int("nyrp.playtime", 0) + (CurTime() - ply:GetNW2Float("nyrp.joined", CurTime()))
	return sec / 3600
end

local function pingBars(x, y, ping, a)
	local bars = ping < 60 and 4 or ping < 100 and 3 or ping < 160 and 2 or 1
	local col = bars >= 3 and UI.Col.green or (bars == 2 and UI.Col.accent or UI.Col.red)
	for i = 1, 4 do
		local bh = UI.S(4) + i * UI.S(3)
		UI.RoundedRect(UI.S(1), x + (i - 1) * UI.S(5), y - bh, UI.S(3), bh, i <= bars and UI.Alpha(col, 255 * a) or Color(255, 255, 255, 30 * a))
	end
end

local function badge(x, y, text, col)
	local tw = UI.TextSize(text, NYRP.Font("bold", 11)) + UI.S(12)
	UI.RoundedRect(UI.S(4), x, y - UI.S(9), tw, UI.S(18), UI.Alpha(col, 40))
	draw.SimpleText(text, NYRP.Font("bold", 11), x + tw / 2, y, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	return tw
end

local function row(parent, ply, index)
	local r = vgui.Create("DButton", parent)
	r:SetText("")
	r:Dock(TOP)
	r:DockMargin(0, 0, 0, UI.S(6))
	r:SetTall(UI.S(60))
	r.Hover = 0
	r.Born = RealTime() + index * 0.035
	local av = vgui.Create("AvatarImage", r)
	av:SetSize(UI.S(40), UI.S(40))
	av:SetPos(UI.S(14), UI.S(10))
	av:SetPlayer(ply, 64)
	av:SetMouseInputEnabled(false)
	r.Paint = function(s, w, h)
		if not IsValid(ply) then s:Remove() return end
		local t = UI.Ease((RealTime() - s.Born) / 0.3)
		s.Hover = UI.Approach(s.Hover, s:IsHovered() and 1 or 0, 14)
		local ox = (1 - t) * -UI.S(40)
		av:SetPos(UI.S(14) + ox, UI.S(10))
		av:SetAlpha(255 * t)
		local me = ply == LocalPlayer()
		UI.RoundedRect(UI.S(12), ox, 0, w, h, Color(255, 255, 255, (index % 2 == 0 and 6 or 9) + s.Hover * 12))
		if me or s.Hover > 0.01 then
			UI.RoundedRect(UI.S(2), ox, UI.S(14), UI.S(3), h - UI.S(28), UI.Alpha(UI.Col.accent, me and 255 or 255 * s.Hover))
		end
		UI.Ring(UI.S(34) + ox, h / 2, UI.S(23), UI.Alpha(me and UI.Col.accent or Color(255, 255, 255), (me and 200 or 40) * t))
		local nx = UI.S(68) + ox
		draw.SimpleText(ply:Nick(), NYRP.Font("semibold", 17), nx, h / 2 - UI.S(2), Color(236, 237, 242, 255 * t), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
		local bx = nx + UI.TextSize(ply:Nick(), NYRP.Font("semibold", 17)) + UI.S(8)
		if me then bx = bx + badge(bx, h / 2 - UI.S(11), "ВЫ", UI.Col.accent) + UI.S(4) end
		if ply:IsAdmin() then badge(bx, h / 2 - UI.S(11), ply:IsSuperAdmin() and "ВЛАДЕЛЕЦ" or "АДМИН", UI.Col.red) end
		UI.DrawIcon("clock", nx + UI.S(7), h / 2 + UI.S(11), UI.S(13), UI.Col.faint)
		draw.SimpleText(string.format("%.1f ч в городе", hours(ply)), NYRP.Font("regular", 14), nx + UI.S(18), h / 2 + UI.S(11), UI.Col.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		local ping = ply:Ping()
		pingBars(w - UI.S(36), h / 2 + UI.S(8), ping, t)
		draw.SimpleText(ping .. " мс", NYRP.Font("semibold", 12), w - UI.S(44), h / 2, UI.Col.faint, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		return true
	end
	r.OnCursorEntered = function() UI.Sound("hover") end
	r.DoRightClick = function()
		if not IsValid(ply) then return end
		UI.Menu({
			{ text = "Скопировать SteamID", icon = "copy", func = function() SetClipboardText(ply:SteamID()) NYRP.Notify("SteamID скопирован", "success", 3) end },
			{ text = "Скопировать SteamID64", icon = "id", func = function() SetClipboardText(ply:SteamID64() or "") NYRP.Notify("SteamID64 скопирован", "success", 3) end },
			{ divider = true },
			{ text = "Открыть профиль Steam", icon = "steam", func = function() ply:ShowProfile() end },
		})
	end
	return r
end

function SB.Show()
	if IsValid(SB.Panel) then SB.Panel:Remove() end
	local w = UI.S(500)
	local p = vgui.Create("EditablePanel")
	SB.Panel = p
	p:SetSize(w, ScrH() - UI.S(48))
	p:SetPos(-w, UI.S(24))
	p:MakePopup()
	p:SetKeyboardInputEnabled(false)
	p.Born = RealTime()
	p.Think = function(s)
		local t
		if s.Closing then
			t = 1 - UI.Ease((RealTime() - s.Closing) / 0.22)
			if t <= 0 then s:Remove() return end
		else
			t = UI.Ease((RealTime() - s.Born) / 0.35)
		end
		s:SetPos(-w + (w + UI.S(24)) * t, UI.S(24))
		s:SetAlpha(255 * math.min(t * 1.5, 1))
	end
	local headH = UI.S(176)
	p.Paint = function(s, pw, ph)
		UI.RoundedBlurPanel(s, UI.S(20), 5)
		UI.RoundedRect(UI.S(20), 0, 0, pw, ph, Color(9, 11, 18, 232))
		-- шапка: баннер города
		UI.Masked(UI.S(20), 0, 0, pw, headH, function()
			surface.SetMaterial(UI.Mat("nyrp/banner.png"))
			surface.SetDrawColor(255, 255, 255, 120)
			local bw = headH * 1920 / 600
			surface.DrawTexturedRect(pw / 2 - bw / 2, 0, bw, headH)
			surface.SetMaterial(UI.Mat("vgui/gradient-u"))
			surface.SetDrawColor(9, 11, 18, 255)
			surface.DrawTexturedRect(0, headH * 0.3, pw, headH * 0.7)
		end)
		UI.Outline(UI.S(20), 0, 0, pw, ph, Color(255, 255, 255, 16), 1)
		surface.SetMaterial(UI.Mat("nyrp/logo.png"))
		surface.SetDrawColor(255, 255, 255)
		surface.DrawTexturedRect(UI.S(24), UI.S(56), UI.S(96), UI.S(96))
		-- онлайн (выше), название (ниже)
		local n, max = player.GetCount(), game.MaxPlayers()
		local ot = "ОНЛАЙН " .. n .. " / " .. max
		local ow = UI.TextSize(ot, NYRP.Font("bold", 13)) + UI.S(34)
		UI.RoundedRect(UI.S(12), UI.S(136), UI.S(58), ow, UI.S(26), Color(104, 200, 120, 36))
		UI.Circle(UI.S(150), UI.S(71), UI.S(4) + math.abs(math.sin(RealTime() * 3)) * UI.S(1.5), UI.Col.green)
		draw.SimpleText(ot, NYRP.Font("bold", 13), UI.S(162), UI.S(71), UI.Col.green, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText("NEW-YORK", NYRP.Font("title", 36), UI.S(134), UI.S(88), UI.Col.text)
		draw.SimpleText("ROLEPLAY  ·  " .. string.upper(game.GetMap()), NYRP.Font("bold", 13), UI.S(137), UI.S(132), UI.Col.accent)
		-- подписи колонок
		draw.SimpleText("ЖИТЕЛИ", NYRP.Font("title", 14), UI.S(24), headH + UI.S(6), UI.Col.faint)
		draw.SimpleText("ПИНГ", NYRP.Font("title", 14), pw - UI.S(24), headH + UI.S(6), UI.Col.faint, TEXT_ALIGN_RIGHT)
		draw.SimpleText(GetHostName(), NYRP.Font("regular", 13), pw / 2, ph - UI.S(22), UI.Col.faint, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	local list = vgui.Create("NYRP.Scroll", p)
	list:SetPos(UI.S(16), headH + UI.S(32))
	list:SetSize(w - UI.S(32), p:GetTall() - headH - UI.S(32) - UI.S(44))
	local players = player.GetAll()
	table.sort(players, function(a, b)
		if a == LocalPlayer() then return true elseif b == LocalPlayer() then return false end
		return a:Nick():lower() < b:Nick():lower()
	end)
	for i, ply in ipairs(players) do row(list, ply, i) end
	UI.Sound("swipe")
end

function SB.Hide()
	if IsValid(SB.Panel) and not SB.Panel.Closing then
		SB.Panel.Closing = RealTime()
		if IsValid(UI.ActiveMenu) then UI.ActiveMenu:Remove() end
	end
end

function GM:ScoreboardShow()
	if NYRP.State ~= "playing" then return true end
	SB.Show()
	return true
end

function GM:ScoreboardHide()
	SB.Hide()
	return true
end
