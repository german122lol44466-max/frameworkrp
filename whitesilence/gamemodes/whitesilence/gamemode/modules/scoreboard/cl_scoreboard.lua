--[[
	TAB: список игроков — панель слева, заходит на левую часть экрана.
	Группы по отрядам, у игрока: аватар Steam, имя (позывной) и ник, состояние (в игре / в меню / погиб), пинг.
	Клик по игроку — профиль Steam, заглушить голос, скопировать SteamID.
]]

local L = WS.Lobby
local UI = WS.UI
local E = WS.Ease
local board, openT, closing

local function icon(n) return UI.Mat("whitesilence/icons/" .. n .. ".png", "smooth") end

local function status(p)
	if not L.InGame(p) then return "в меню", Color(160, 168, 180) end
	if not p:Alive() then return p:GetNW2Bool("ws_spectating", false) and "наблюдает" or "погиб", Color(220, 100, 90) end
	return "в игре", Color(130, 210, 140)
end

local function groups()
	local byId, order = {}, {}
	for _, p in ipairs(player.GetAll()) do
		local id = L.Id(p)
		if not byId[id] then byId[id] = {} order[#order + 1] = id end
		table.insert(byId[id], p)
	end
	table.sort(order, function(a, b)
		if a == 0 or b == 0 then return b == 0 end
		local me = L.Id(LocalPlayer())
		if a == me or b == me then return a == me end
		return a < b
	end)
	return order, byId
end

local function signature()
	local t = {}
	for _, p in ipairs(player.GetAll()) do
		t[#t + 1] = p:EntIndex() .. L.Id(p) .. L.Name(p) .. tostring(L.InGame(p)) .. tostring(p:Alive())
	end
	return table.concat(t, "|")
end

local function build()
	local s = ScrH() / 1080
	board:Clear()
	board.Signature = signature()
	local scroll = vgui.Create("DScrollPanel", board)
	scroll:SetPos(26 * s, 150 * s)
	scroll:SetSize(board:GetWide() - 46 * s, board:GetTall() - 190 * s)
	local order, byId = groups()
	for _, id in ipairs(order) do
		local list = byId[id]
		local head = vgui.Create("DPanel", scroll)
		head:Dock(TOP)
		head:DockMargin(0, 10 * s, 0, 4 * s)
		head:SetTall(26 * s)
		local mine = id ~= 0 and id == L.Id(LocalPlayer())
		head.Paint = function(_, w, h)
			draw.SimpleText(id == 0 and "БЕЗ ОТРЯДА" or ("ОТРЯД №" .. id .. (mine and " · ваш" or "")), WS.Font("menusemi", 16), 2, h / 2,
				mine and Color(226, 190, 120) or Color(170, 178, 190), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			surface.SetDrawColor(255, 255, 255, 18)
			surface.DrawRect(0, h - 1, w, 1)
		end
		for _, p in ipairs(list) do
			local row = vgui.Create("DButton", scroll)
			row:SetText("")
			row:Dock(TOP)
			row:DockMargin(0, 0, 0, 4 * s)
			row:SetTall(46 * s)
			row.Paint = function(self, w, h)
				if not IsValid(p) then return true end
				draw.RoundedBox(3, 0, 0, w, h, Color(255, 255, 255, self:IsHovered() and 22 or 8))
				if p == LocalPlayer() then
					surface.SetDrawColor(226, 190, 120, 200)
					surface.DrawRect(0, 0, 3 * s, h)
				end
				local nx = h + 8 * s
				draw.SimpleText(L.Name(p), WS.Font("menusemi", 19), nx, h * 0.36, Color(236, 239, 244), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				local st, sc = status(p)
				local sub = st
				if p:GetNW2String("ws_callsign", "") ~= "" then sub = sub .. " · " .. p:Nick() end
				if L.IsLeader(p) then sub = "командир · " .. sub end
				local title = WS.Ach and WS.Ach.TitleOf(p)
				if title then sub = sub .. " · «" .. title .. "»" end
				draw.SimpleText(sub, WS.Font("menulight", 14), nx, h * 0.72, sc, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				-- пинг
				local ping = p:Ping()
				local pc = ping < 80 and Color(150, 210, 150) or ping < 160 and Color(226, 190, 120) or Color(220, 100, 90)
				draw.SimpleText(tostring(ping), WS.Font("menu", 16), w - 10 * s, h / 2, pc, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
				surface.SetMaterial(icon("ping"))
				surface.SetDrawColor(pc.r, pc.g, pc.b, 200)
				surface.DrawTexturedRect(w - 62 * s, h / 2 - 9 * s, 18 * s, 18 * s)
				if p:IsMuted() then
					surface.SetMaterial(icon("mic"))
					surface.SetDrawColor(220, 100, 90, 220)
					surface.DrawTexturedRect(w - 90 * s, h / 2 - 9 * s, 18 * s, 18 * s)
				end
				return true
			end
			local av = vgui.Create("AvatarImage", row)
			av:SetPos(5 * s, 5 * s)
			av:SetSize(36 * s, 36 * s)
			av:SetPlayer(p, 64)
			av:SetMouseInputEnabled(false)
			row.DoClick = function()
				if not IsValid(p) then return end
				local m = DermaMenu()
				m:AddOption("Профиль Steam", function() if IsValid(p) then p:ShowProfile() end end)
				if p ~= LocalPlayer() then
					m:AddOption(p:IsMuted() and "Включить голос" or "Заглушить голос", function() if IsValid(p) then p:SetMuted(not p:IsMuted()) end end)
				end
				m:AddOption("Скопировать SteamID", function() if IsValid(p) then SetClipboardText(p:SteamID()) end end)
				m:Open()
			end
		end
	end
end

local function open()
	local s = ScrH() / 1080
	if not IsValid(board) then
		board = vgui.Create("DPanel")
		board:SetSize(math.max(ScrW() * 0.3, 460 * s), ScrH())
		board.Paint = function(self, w, h)
			local a = closing and (1 - E.Smooth((RealTime() - closing) / 0.2)) or E.Smooth((RealTime() - openT) / 0.25)
			self:SetX(-(1 - a) * w * 0.4)
			self:SetAlpha(255 * a)
			-- тёмная подложка, к правому краю тает
			for i = 0, 15 do
				surface.SetDrawColor(4, 6, 9, 235 * (1 - (i / 16) ^ 3))
				surface.DrawRect(w * i / 16, 0, w / 16 + 1, h)
			end
			surface.SetMaterial(UI.Mat(WS.Intro.Path .. "scp_logo.png", "smooth"))
			surface.SetDrawColor(255, 255, 255, 230)
			surface.DrawTexturedRect(26 * s, 34 * s, 64 * s, 64 * s)
			draw.SimpleText("БЕЛАЯ ТИШИНА", WS.Font("menubold", 30), 104 * s, 46 * s, Color(238, 240, 244))
			draw.SimpleText(GetHostName(), WS.Font("menulight", 16), 106 * s, 84 * s, Color(170, 178, 190))
			draw.SimpleText(string.format("%d / %d", player.GetCount(), game.MaxPlayers()), WS.Font("menusemi", 18),
				w - 24 * s, 52 * s, Color(226, 190, 120), TEXT_ALIGN_RIGHT)
			surface.SetDrawColor(196, 38, 38, 220)
			surface.DrawRect(26 * s, 126 * s, 70 * s, 2 * s)
			if closing and RealTime() - closing > 0.2 then self:SetVisible(false) end
		end
		board.Think = function(self)
			if self:IsVisible() and self.Signature ~= signature() then build() end
		end
	end
	openT, closing = RealTime(), nil
	board:SetVisible(true)
	build()
	board:MakePopup()
	board:SetKeyboardInputEnabled(false)
end

hook.Add("ScoreboardShow", "ws.scoreboard", function()
	if WS.Menu and WS.Menu.IsOpen() then return true end
	open()
	return true
end)

hook.Add("ScoreboardHide", "ws.scoreboard", function()
	if IsValid(board) and board:IsVisible() then
		closing = RealTime()
		board:SetMouseInputEnabled(false)
		CloseDermaMenus()
	end
	return true
end)
