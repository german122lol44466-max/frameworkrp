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

local function row(parent, ply)
	local r = vgui.Create("DButton", parent)
	r:SetText("")
	r:Dock(TOP)
	r:DockMargin(0, 0, 0, UI.S(6))
	r:SetTall(UI.S(56))
	r.Hover = 0
	local av = vgui.Create("AvatarImage", r)
	av:SetSize(UI.S(38), UI.S(38))
	av:SetPos(UI.S(10), UI.S(9))
	av:SetPlayer(ply, 64)
	av:SetMouseInputEnabled(false)
	r.Paint = function(s, w, h)
		if not IsValid(ply) then s:Remove() return end
		s.Hover = UI.Approach(s.Hover, s:IsHovered() and 1 or 0, 14)
		UI.RoundedRect(UI.S(10), 0, 0, w, h, Color(255, 255, 255, 8 + s.Hover * 12))
		if ply == LocalPlayer() then UI.RoundedRect(UI.S(2), 0, UI.S(12), UI.S(3), h - UI.S(24), UI.Col.accent) end
		draw.SimpleText(ply:Nick(), NYRP.Font("semibold", 17), UI.S(60), h / 2 - UI.S(1), UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
		local hrs = hours(ply)
		UI.DrawIcon("clock", UI.S(67), h / 2 + UI.S(10), UI.S(13), UI.Col.faint)
		draw.SimpleText(string.format("%.1f ч наиграно", hrs), NYRP.Font("regular", 14), UI.S(78), h / 2 + UI.S(10), UI.Col.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		local ping = ply:Ping()
		local pc = ping < 80 and UI.Col.green or (ping < 150 and UI.Col.accent or UI.Col.red)
		draw.SimpleText(ping .. " мс", NYRP.Font("semibold", 14), w - UI.S(16), h / 2, pc, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
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
	local w = UI.S(470)
	local p = vgui.Create("EditablePanel")
	SB.Panel = p
	p:SetSize(w, ScrH() - UI.S(48))
	p:SetPos(-w, UI.S(24))
	p:MakePopup()
	p:SetKeyboardInputEnabled(false)
	p.Born = RealTime()
	p.Closing = nil
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
	p.Paint = function(s, pw, ph)
		UI.RoundedBlurPanel(s, UI.S(18), 5)
		UI.RoundedRect(UI.S(18), 0, 0, pw, ph, Color(10, 12, 20, 228))
		UI.Outline(UI.S(18), 0, 0, pw, ph, Color(255, 255, 255, 16), 1)
		-- лого
		surface.SetMaterial(UI.Mat("nyrp/logo.png"))
		surface.SetDrawColor(255, 255, 255)
		surface.DrawTexturedRect(UI.S(22), UI.S(22), UI.S(92), UI.S(92))
		-- онлайн (выше), название (ниже)
		local n, max = player.GetCount(), game.MaxPlayers()
		local ot = "Онлайн: " .. n .. " / " .. max
		local ow = UI.TextSize(ot, NYRP.Font("semibold", 14)) + UI.S(30)
		UI.RoundedRect(UI.S(11), UI.S(130), UI.S(26), ow, UI.S(24), Color(104, 200, 120, 30))
		UI.Circle(UI.S(143), UI.S(38), UI.S(4), UI.Col.green)
		draw.SimpleText(ot, NYRP.Font("semibold", 14), UI.S(153), UI.S(38), UI.Col.green, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText("NEW-YORK", NYRP.Font("title", 32), UI.S(128), UI.S(56), UI.Col.text)
		draw.SimpleText("ROLEPLAY", NYRP.Font("bold", 14), UI.S(130), UI.S(94), UI.Col.accent)
		surface.SetDrawColor(255, 255, 255, 14)
		surface.DrawRect(UI.S(22), UI.S(132), pw - UI.S(44), 1)
	end
	local list = vgui.Create("NYRP.Scroll", p)
	list:SetPos(UI.S(18), UI.S(146))
	list:SetSize(w - UI.S(36), p:GetTall() - UI.S(164))
	local players = player.GetAll()
	table.sort(players, function(a, b) return a:Nick():lower() < b:Nick():lower() end)
	for _, ply in ipairs(players) do row(list, ply) end
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
