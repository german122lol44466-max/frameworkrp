--[[
	Главное меню и лобби отряда.

	Главное: тёмная картина-фон с медленным наездом, метель, искры с мачты, мигающий прожектор, угольки.
	Слева сверху — знак Фонда и название, по центру — «Играть» и «Отключиться».
	«Играть» → лобби: слева столбик отряда (аватар Steam, имя или позывной, у своей строки — смена позывного,
	пустые места — пригласить игрока с сервера), справа — изображение отряда, снизу — «Выдвигаться» (командир),
	«Покинуть отряд», «Назад». Музыка и звуки — из SCP – Containment Breach (CC BY-SA 3.0).

	ws_menu — открыть меню (если вы ещё не в игре).
]]

local M = WS.Menu
local L = WS.Lobby
local UI = WS.UI
local E = WS.Ease

local PATH = "whitesilence/menu/"
local panel, lobbyPanel, invitePanel
local openTime, state, stateTime = 0, "main", 0
local sounds = {}
local toasts = {}

-- Точка на фоновой картине, откуда сыплются искры (доли экрана), и картины
M.BackgroundImage = "menu_bg"
M.SquadImage = "squad"
M.SparkSource = { 0.81, 0.15 }   -- вершина правой мачты на фоне

local function snd(name, vol)
	WS.Audio.Play(PATH .. name .. ".ogg", { volume = vol or 0.7 })
end

local function mat(name)
	return UI.Mat(PATH .. name, "smooth")
end

local function sc()
	return ScrH() / 1080
end

-- ---------------------------------------------------------------- уведомления (тосты сверху)

function M.Toast(text, sound)
	toasts[#toasts + 1] = { text = text, t = RealTime() }
	if #toasts > 4 then table.remove(toasts, 1) end
	if sound and sound ~= "" then snd(sound, 0.6) end
end

local function drawToasts()
	local w = ScrW()
	local y = 26 * sc()
	local font = WS.Font("menu", 20)
	for i = #toasts, 1, -1 do
		local t = toasts[i]
		local age = RealTime() - t.t
		if age > 4.5 then table.remove(toasts, i) end
	end
	for _, t in ipairs(toasts) do
		local age = RealTime() - t.t
		local a = E.Smooth(age / 0.25) * (1 - E.Smooth((age - 3.8) / 0.6))
		surface.SetFont(font)
		local tw, th = surface.GetTextSize(t.text)
		local pw, ph = tw + 40 * sc(), th + 16 * sc()
		local x = w / 2 - pw / 2
		draw.RoundedBox(4, x, y, pw, ph, Color(8, 10, 14, 220 * a))
		surface.SetDrawColor(196, 38, 38, 220 * a)
		surface.DrawRect(x, y, 3 * sc(), ph)
		draw.SimpleText(t.text, font, w / 2, y + ph / 2, Color(232, 236, 242, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		y = y + ph + 8 * sc()
	end
end

-- ---------------------------------------------------------------- кнопки в стиле меню

-- Текстовая кнопка: белый текст, при наведении — свечение, красные засечки по бокам, звук
local function menuButton(parent, text, size, onClick)
	local b = vgui.Create("DButton", parent)
	b:SetText("")
	b.Label = text
	b.Size = size or 46
	b.Hover = 0
	b.Enabled = true
	b.Paint = function(self, w, h)
		self.Hover = WS.Approach(self.Hover, (self:IsHovered() and self.Enabled) and 1 or 0, 6)
		local font = WS.Font("menu", self.Size)
		local glow = WS.Font("menu", self.Size, 8)
		local a = self.Enabled and 1 or 0.35
		local k = self.Hover
		local cx, cy = w / 2, h / 2
		draw.SimpleText(self.Label, glow, cx, cy, Color(170, 200, 235, 90 * k * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		draw.SimpleText(self.Label, font, cx + 1, cy + 2, Color(0, 0, 0, 160 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		local c = Lerp(k, 215, 255)
		draw.SimpleText(self.Label, font, cx, cy, Color(c, c, c, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		if k > 0.01 then
			surface.SetFont(font)
			local tw = surface.GetTextSize(self.Label)
			local s = sc()
			local off = tw / 2 + Lerp(k, 6, 18) * s
			surface.SetDrawColor(196, 38, 38, 230 * k)
			surface.DrawRect(cx - off - 12 * s, cy - 1 * s, 12 * s * k, 2 * s)
			surface.DrawRect(cx + off, cy - 1 * s, 12 * s * k, 2 * s)
		end
		return true
	end
	b.OnCursorEntered = function(self) if self.Enabled then snd("hover", 0.5) end end
	b.DoClick = function(self)
		if not self.Enabled then snd("error", 0.4) return end
		snd("click", 0.7)
		if onClick then onClick(self) end
	end
	return b
end

-- Небольшая кнопка-надпись (в строках лобби)
local function smallButton(parent, text, onClick, color)
	local b = vgui.Create("DButton", parent)
	b:SetText("")
	b.Label = text
	b.Hover = 0
	b.Paint = function(self, w, h)
		self.Hover = WS.Approach(self.Hover, self:IsHovered() and 1 or 0, 8)
		local col = color or Color(196, 204, 216)
		draw.RoundedBox(3, 0, 0, w, h, Color(255, 255, 255, 10 + 22 * self.Hover))
		draw.SimpleText(self.Label, WS.Font("menu", 16), w / 2, h / 2,
			Color(col.r, col.g, col.b, 170 + 85 * self.Hover), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		return true
	end
	b.OnCursorEntered = function() snd("hover", 0.35) end
	b.DoClick = function(self) snd("click", 0.6) onClick(self) end
	return b
end

-- ---------------------------------------------------------------- фон

local function drawBackground(t, w, h)
	surface.SetDrawColor(0, 0, 0, 255)
	surface.DrawRect(0, 0, w, h)
	local bg = mat(M.BackgroundImage .. ".jpg")
	local base = math.max(w / 2560, h / 1440)
	local z = 1.04 + 0.03 * math.sin(t * 0.05)                     -- очень медленное «дыхание» камеры
	local dw, dh = 2560 * base * z, 1440 * base * z
	local ox = (w - dw) / 2 + math.sin(t * 0.07) * 10 * sc()
	local oy = (h - dh) / 2 + math.cos(t * 0.05) * 6 * sc()
	local fl = M.FX.Flicker
	surface.SetMaterial(bg)
	surface.SetDrawColor(255 * Lerp(fl, 0.75, 1), 255 * Lerp(fl, 0.75, 1), 255 * Lerp(fl, 0.78, 1), 255)
	surface.DrawTexturedRect(ox, oy, dw, dh)
	-- метель и туман
	local FX = WS.Intro.FX
	FX.Fog(t, 0.08, 25, Color(160, 175, 195))
	FX.Snow(t, FrameTime(), "blizzard", 0.45, 0.7, 0.05)
end

local function drawLogo(a, title)
	local s = sc()
	local logo = UI.Mat(WS.Intro.Path .. "scp_logo.png", "smooth")
	local size = 200 * s
	local x, y = 60 * s, 48 * s
	WS.Intro.FX.Glow(x + size / 2, y + size / 2, size * 0.9, Color(140, 170, 210), 0.1 * a)
	surface.SetMaterial(logo)
	surface.SetDrawColor(255, 255, 255, 240 * a)
	surface.DrawTexturedRect(x, y, size, size)
	if not title then return end
	local tx, ty = x - 4 * s, y + size + 14 * s
	draw.SimpleText("БЕЛАЯ ТИШИНА", WS.Font("menubold", 58, 10), tx, ty, Color(170, 200, 235, 70 * a))
	draw.SimpleText("БЕЛАЯ ТИШИНА", WS.Font("menubold", 58), tx + 2, ty + 3, Color(0, 0, 0, 180 * a))
	draw.SimpleText("БЕЛАЯ ТИШИНА", WS.Font("menubold", 58), tx, ty, Color(238, 240, 244, 255 * a))
	draw.SimpleText("SCP · МОГ «ДЕЛЬТА-14»", WS.Font("menulight", 20), tx + 3, ty + 66 * s, Color(196, 204, 216, 200 * a))
end

-- ---------------------------------------------------------------- лобби

local function rowName(ply)
	local n = L.Name(ply)
	if utf8.len(n) and utf8.len(n) > 24 then n = utf8.sub and utf8.sub(n, 1, 24) or n end
	return n
end

-- Всплывающий список игроков, которых можно пригласить
local function openInviteList(anchor)
	if IsValid(M.InviteList) then M.InviteList:Remove() end
	local s = sc()
	local list = vgui.Create("DPanel", panel)
	M.InviteList = list
	local ax, ay = anchor:LocalToScreen(0, 0)
	local w = 380 * s
	list:SetPos(ax + anchor:GetWide() + 10 * s, ay)
	list.Paint = function(self, pw, ph)
		draw.RoundedBox(4, 0, 0, pw, ph, Color(8, 10, 14, 245))
		surface.SetDrawColor(255, 255, 255, 20)
		surface.DrawOutlinedRect(0, 0, pw, ph, 1)
		draw.SimpleText("ПРИГЛАСИТЬ В ОТРЯД", WS.Font("menusemi", 16), 14 * s, 10 * s, Color(226, 190, 120))
	end
	local players = L.Invitable(L.Id(LocalPlayer()))
	local rowH = 44 * s
	local scroll = vgui.Create("DScrollPanel", list)
	scroll:SetPos(6 * s, 34 * s)
	local shown = math.min(#players, 7)
	list:SetSize(w, 40 * s + math.max(shown, 1) * (rowH + 4 * s))
	scroll:SetSize(w - 12 * s, math.max(shown, 1) * (rowH + 4 * s))
	if #players == 0 then
		local lbl = vgui.Create("DLabel", list)
		lbl:SetPos(14 * s, 40 * s)
		lbl:SetFont(WS.Font("menu", 17))
		lbl:SetTextColor(Color(160, 168, 180))
		lbl:SetText("Нет свободных игроков на сервере")
		lbl:SizeToContents()
	end
	for _, p in ipairs(players) do
		local row = vgui.Create("DButton", scroll)
		row:SetText("")
		row:Dock(TOP)
		row:DockMargin(0, 0, 0, 4 * s)
		row:SetTall(rowH)
		row.Paint = function(self, pw, ph)
			draw.RoundedBox(3, 0, 0, pw, ph, Color(255, 255, 255, self:IsHovered() and 26 or 8))
			if IsValid(p) then
				draw.SimpleText(rowName(p), WS.Font("menu", 18), ph + 10 * s, ph / 2, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
			draw.SimpleText("Пригласить", WS.Font("menulight", 15), pw - 10 * s, ph / 2, Color(226, 190, 120), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
			return true
		end
		local av = vgui.Create("AvatarImage", row)
		av:SetPos(4 * s, 4 * s)
		av:SetSize(rowH - 8 * s, rowH - 8 * s)
		av:SetPlayer(p, 64)
		av:SetMouseInputEnabled(false)
		row.DoClick = function()
			if not IsValid(p) then return end
			snd("click", 0.6)
			net.Start("ws.lobby.invite")
			net.WriteEntity(p)
			net.SendToServer()
			list:Remove()
		end
	end
	-- клик мимо закрывает список
	list.Think = function(self)
		if input.IsMouseDown(MOUSE_LEFT) and not self:IsChildHovered() and not self:IsHovered() then
			if not self.armed then return end
			self:Remove()
		else
			self.armed = true
		end
	end
end

-- Смена позывного: строка ввода поверх своей строки
local function editCallsign(row)
	if IsValid(M.Edit) then M.Edit:Remove() end
	local s = sc()
	local e = vgui.Create("DTextEntry", row)
	M.Edit = e
	e:SetPos(row:GetTall() + 8 * s, 8 * s)
	e:SetSize(row:GetWide() - row:GetTall() - 120 * s, row:GetTall() - 16 * s)
	e:SetFont(WS.Font("menu", 20))
	e:SetText(LocalPlayer():GetNW2String("ws_callsign", ""))
	e:SetPlaceholderText("Позывной (пусто — ник Steam)")
	e:SetUpdateOnType(false)
	e.Paint = function(self, pw, ph)
		draw.RoundedBox(3, 0, 0, pw, ph, Color(0, 0, 0, 200))
		surface.SetDrawColor(226, 190, 120, 160)
		surface.DrawOutlinedRect(0, 0, pw, ph, 1)
		self:DrawTextEntryText(Color(240, 240, 240), Color(196, 38, 38), Color(255, 255, 255))
	end
	e.OnEnter = function(self)
		net.Start("ws.lobby.callsign")
		net.WriteString(self:GetValue() or "")
		net.SendToServer()
		snd("click", 0.6)
		self:Remove()
	end
	e.OnLoseFocus = function(self) timer.Simple(0, function() if IsValid(self) then self:Remove() end end) end
	e:RequestFocus()
	e:SelectAllText()
end

local function lobbySignature()
	local id = L.Id(LocalPlayer())
	local parts = { tostring(id) }
	for _, p in ipairs(L.Members(id)) do
		parts[#parts + 1] = p:EntIndex() .. (L.IsLeader(p) and "*" or "") .. (L.InGame(p) and "!" or "") .. L.Name(p)
	end
	return table.concat(parts, "|")
end

local function buildLobby()
	if IsValid(lobbyPanel) then lobbyPanel:Remove() end
	local s = sc()
	local w, h = ScrW(), ScrH()
	local me = LocalPlayer()
	local id = L.Id(me)
	local members = L.Members(id)
	local lead = L.IsLeader(me)

	lobbyPanel = vgui.Create("DPanel", panel)
	lobbyPanel:SetPos(0, 0)
	lobbyPanel:SetSize(w, h)
	lobbyPanel.Paint = nil
	lobbyPanel.Signature = lobbySignature()

	-- левая колонка: отряд
	local colX, colY, colW = 70 * s, 400 * s, 560 * s
	local rowH, gap = 62 * s, 8 * s
	local title = vgui.Create("DPanel", lobbyPanel)
	title:SetPos(colX, colY - 70 * s)
	title:SetSize(colW, 60 * s)
	title.Paint = function(_, pw, ph)
		draw.SimpleText("ОТРЯД", WS.Font("menubold", 34), 0, 0, Color(238, 240, 244))
		draw.SimpleText(string.format("%d / %d", #members, WS.Config.SquadSize), WS.Font("menulight", 22),
			pw, ph * 0.3, Color(196, 204, 216), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		surface.SetDrawColor(196, 38, 38, 220)
		surface.DrawRect(0, ph - 4 * s, 70 * s, 2 * s)
	end

	for i = 1, WS.Config.SquadSize do
		local p = members[i]
		local row = vgui.Create("DPanel", lobbyPanel)
		row:SetPos(colX, colY + (i - 1) * (rowH + gap))
		row:SetSize(colW, rowH)
		local born = RealTime() + i * 0.05
		if IsValid(p) then
			row.Paint = function(self, pw, ph)
				local a = E.Smooth((RealTime() - born) / 0.3)
				draw.RoundedBox(4, 0, 0, pw, ph, Color(10, 12, 16, 200 * a))
				surface.SetDrawColor(255, 255, 255, 18 * a)
				surface.DrawOutlinedRect(0, 0, pw, ph, 1)
				if p == me then
					surface.SetDrawColor(226, 190, 120, 200 * a)
					surface.DrawRect(0, 0, 3 * s, ph)
				end
				if not IsValid(p) then return end
				local nx = ph + 12 * s
				draw.SimpleText(rowName(p), WS.Font("menusemi", 22), nx, ph * 0.38, Color(238, 240, 244, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				local sub = L.IsLeader(p) and "Командир" or "Боец"
				if p:GetNW2String("ws_callsign", "") ~= "" then sub = sub .. " · " .. p:Nick() end
				draw.SimpleText(sub, WS.Font("menulight", 15), nx, ph * 0.72,
					L.IsLeader(p) and Color(226, 190, 120, 230 * a) or Color(160, 168, 180, 230 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
			local av = vgui.Create("AvatarImage", row)
			av:SetPos(8 * s, 8 * s)
			av:SetSize(rowH - 16 * s, rowH - 16 * s)
			av:SetPlayer(p, 64)
			if p == me then
				local b = smallButton(row, "Позывной", function() editCallsign(row) end, Color(226, 190, 120))
				b:SetSize(120 * s, 30 * s)
				b:SetPos(colW - 130 * s, rowH / 2 - 15 * s)
			elseif lead then
				local b = smallButton(row, "Исключить", function()
					net.Start("ws.lobby.kick")
					net.WriteEntity(p)
					net.SendToServer()
				end, Color(220, 120, 110))
				b:SetSize(110 * s, 30 * s)
				b:SetPos(colW - 120 * s, rowH / 2 - 15 * s)
			end
		else
			-- пустое место: пригласить игрока с сервера
			local b = vgui.Create("DButton", row)
			b:SetText("")
			b:Dock(FILL)
			b.Hover = 0
			b.Paint = function(self, pw, ph)
				self.Hover = WS.Approach(self.Hover, self:IsHovered() and 1 or 0, 8)
				local a = E.Smooth((RealTime() - born) / 0.3)
				draw.RoundedBox(4, 0, 0, pw, ph, Color(255, 255, 255, (4 + 14 * self.Hover) * a))
				-- пунктирная рамка
				surface.SetDrawColor(255, 255, 255, (40 + 60 * self.Hover) * a)
				for x = 0, pw, 14 * s do surface.DrawRect(x, 0, 7 * s, 1) surface.DrawRect(x, ph - 1, 7 * s, 1) end
				for y = 0, ph, 14 * s do surface.DrawRect(0, y, 1, 7 * s) surface.DrawRect(pw - 1, y, 1, 7 * s) end
				draw.SimpleText("+  Пригласить игрока", WS.Font("menu", 19), ph * 0.4, ph / 2,
					Color(196, 204, 216, (140 + 115 * self.Hover) * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				return true
			end
			b.OnCursorEntered = function() snd("hover", 0.35) end
			b.DoClick = function(self) snd("click", 0.6) openInviteList(self) end
		end
	end

	-- кнопки снизу
	local by = colY + WS.Config.SquadSize * (rowH + gap) + 30 * s
	local fighting = false
	for _, p in ipairs(members) do if L.InGame(p) then fighting = true end end
	local go = menuButton(lobbyPanel, fighting and "К ОТРЯДУ" or (lead and "ВЫДВИГАТЬСЯ" or "ЖДЁМ КОМАНДИРА"), 34, function()
		net.Start("ws.lobby.start")
		net.SendToServer()
	end)
	go.Enabled = lead or fighting
	go:SetSize(colW, 54 * s)
	go:SetPos(colX, by)
	local nextY = by + 58 * s
	if #members > 1 then
		local leave = menuButton(lobbyPanel, "ПОКИНУТЬ ОТРЯД", 24, function()
			net.Start("ws.lobby.leave")
			net.SendToServer()
		end)
		leave:SetSize(colW, 40 * s)
		leave:SetPos(colX, nextY)
		nextY = nextY + 42 * s
	end
	local back = menuButton(lobbyPanel, "НАЗАД", 24, function() M.SetState("main") end)
	back:SetSize(colW, 40 * s)
	back:SetPos(colX, nextY)

	-- правая панель: изображение отряда
	local pw, ph = 600 * s, 772 * s
	local img = vgui.Create("DPanel", lobbyPanel)
	img:SetPos(w - pw - 80 * s, h / 2 - ph / 2 + 20 * s)
	img:SetSize(pw, ph)
	img.Paint = function(_, iw, ih)
		local a = E.Smooth((RealTime() - stateTime) / 0.6)
		surface.SetMaterial(mat(M.SquadImage .. ".jpg"))
		surface.SetDrawColor(255, 255, 255, 255 * a)
		surface.DrawTexturedRect(0, 0, iw, ih)
		-- затемнение снизу под подписью
		surface.SetMaterial(UI.Mat(WS.Intro.Path .. "vignette.png", "smooth"))
		surface.SetDrawColor(255, 255, 255, 200 * a)
		surface.DrawTexturedRect(0, 0, iw, ih)
		surface.SetDrawColor(255, 255, 255, 30 * a)
		surface.DrawOutlinedRect(0, 0, iw, ih, 1)
		surface.SetDrawColor(196, 38, 38, 220 * a)
		surface.DrawRect(0, 0, 60 * s, 3 * s)
		draw.SimpleText("ОТРЯД №" .. id, WS.Font("menubold", 30), 20 * s, ih - 78 * s, Color(238, 240, 244, 255 * a))
		draw.SimpleText("Спецподразделение Фонда · задача: нейтрализация", WS.Font("menulight", 17), 20 * s, ih - 38 * s,
			Color(196, 204, 216, 230 * a))
	end
end

-- ---------------------------------------------------------------- приглашение (всплывает у приглашённого)

local function showInvite(from, time)
	if IsValid(invitePanel) then invitePanel:Remove() end
	if not IsValid(from) then return end
	local s = sc()
	local parent = IsValid(panel) and panel or nil
	local p = vgui.Create("DPanel", parent)
	invitePanel = p
	local w, h = 520 * s, 128 * s
	p:SetSize(w, h)
	p:SetPos(ScrW() / 2 - w / 2, 130 * s)
	if not parent then p:MakePopup() end
	local born, dead = RealTime(), RealTime() + time
	p.Paint = function(self, pw, ph)
		local a = E.Smooth((RealTime() - born) / 0.25)
		draw.RoundedBox(5, 0, 0, pw, ph, Color(8, 10, 14, 240 * a))
		surface.SetDrawColor(226, 190, 120, 200 * a)
		surface.DrawRect(0, 0, pw * math.Clamp((dead - RealTime()) / time, 0, 1), 3 * s)
		if IsValid(from) then
			draw.SimpleText(L.Name(from), WS.Font("menusemi", 22), 96 * s, 22 * s, Color(238, 240, 244, 255 * a))
		end
		draw.SimpleText("приглашает вас в свой отряд", WS.Font("menulight", 18), 96 * s, 50 * s, Color(196, 204, 216, 255 * a))
		if RealTime() > dead then self:Remove() end
	end
	local av = vgui.Create("AvatarImage", p)
	av:SetPos(16 * s, 18 * s)
	av:SetSize(64 * s, 64 * s)
	av:SetPlayer(from, 64)
	local function answer(yes)
		net.Start("ws.lobby.answer")
		net.WriteBool(yes)
		net.SendToServer()
		p:Remove()
	end
	local ok = smallButton(p, "Принять", function() answer(true) end, Color(226, 190, 120))
	ok:SetSize(150 * s, 32 * s)
	ok:SetPos(96 * s, h - 44 * s)
	local no = smallButton(p, "Отклонить", function() answer(false) end, Color(220, 120, 110))
	no:SetSize(150 * s, 32 * s)
	no:SetPos(256 * s, h - 44 * s)
end

net.Receive("ws.lobby.invited", function()
	local from = net.ReadEntity()
	local time = net.ReadFloat()
	snd("invite", 0.8)
	showInvite(from, time)
end)

net.Receive("ws.lobby.notify", function()
	local text, sound = net.ReadString(), net.ReadString()
	M.Toast(text, sound)
end)

-- ---------------------------------------------------------------- состояния и отрисовка

function M.SetState(st)
	if st == state then return end
	state = st
	stateTime = RealTime()
	if IsValid(M.InviteList) then M.InviteList:Remove() end
	if IsValid(lobbyPanel) then lobbyPanel:Remove() end
	if IsValid(M.Buttons) then M.Buttons:SetVisible(st == "main") end
	if st == "lobby" then
		net.Start("ws.lobby.open")
		net.SendToServer()
		snd("open", 0.7)
		timer.Simple(0.15, function() if IsValid(panel) and state == "lobby" then buildLobby() end end)
	end
end

local lastT
local function paint(self, w, h)
	local now = RealTime()
	local t = now - openTime
	local dt = math.Clamp(now - (lastT or now), 0, 0.1)
	lastT = now
	M.FX.Think(dt)

	drawBackground(t, w, h)
	M.FX.Draw(1)
	WS.Intro.FX.Vignette(0.9)
	WS.Intro.FX.Grain(0.8)

	local main = state == "main" and E.Smooth((now - stateTime) / 0.6) or 0
	-- в лобби — только знак (под ним колонка отряда), в главном — знак и название
	drawLogo(state == "main" and 1 or 0.55, state == "main")
	if state == "lobby" then
		-- пересобрать, если состав или имена изменились
		if IsValid(lobbyPanel) and lobbyPanel.Signature ~= lobbySignature() then buildLobby() end
	end
	draw.SimpleText("v" .. WS.Version, WS.Font("menulight", 14), w - 14 * sc(), h - 10 * sc(), Color(150, 158, 170, 160),
		TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
	self.MainAlpha = main
end

local function paintOver(self, w, h)
	drawToasts()
	-- вход из черноты и выход в игру
	local a = 1 - E.Smooth((RealTime() - openTime) / 1.2)
	if M.Closing then a = E.Smooth((RealTime() - M.Closing) / 1.4) end
	if a > 0 then
		surface.SetDrawColor(0, 0, 0, 255 * a)
		surface.DrawRect(0, 0, w, h)
	end
end

function M.IsOpen()
	return IsValid(panel)
end

function M.Open()
	if IsValid(panel) or L.InGame(LocalPlayer()) then return end
	WS.Intro.FX.Init()
	M.FX.Source = M.SparkSource
	M.FX.Reset()
	openTime = RealTime()
	state, stateTime = "main", RealTime()
	M.Closing = nil
	lastT = nil

	panel = vgui.Create("EditablePanel")
	panel:SetSize(ScrW(), ScrH())
	panel:SetPos(0, 0)
	panel:MakePopup()
	panel:SetKeyboardInputEnabled(true)
	panel.Paint = paint
	panel.PaintOver = paintOver

	local s = sc()
	local box = vgui.Create("DPanel", panel)
	M.Buttons = box
	box:SetSize(520 * s, 150 * s)
	box:SetPos(ScrW() / 2 - 260 * s, ScrH() * 0.47)
	box.Paint = nil
	local play = menuButton(box, "ИГРАТЬ", 46, function() M.SetState("lobby") end)
	play:Dock(TOP)
	play:SetTall(66 * s)
	local quit = menuButton(box, "ОТКЛЮЧИТЬСЯ", 46, function()
		M.Closing = RealTime()
		timer.Simple(0.6, function() RunConsoleCommand("disconnect") end)
	end)
	quit:Dock(TOP)
	quit:SetTall(66 * s)

	sounds.music = WS.Audio.Play(PATH .. "music.ogg", { volume = 0.55, fade = 3, loop = true })
	sounds.drone = WS.Audio.Play(PATH .. "drone.ogg", { volume = 0.35, fade = 3, loop = true })
	sounds.wind = WS.Audio.Play(WS.Intro.Path .. "blizzard.ogg", { volume = 0.18, fade = 4, loop = true })
end

function M.Close()
	for _, h in pairs(sounds) do h:Stop(1.5) end
	sounds = {}
	if IsValid(invitePanel) then invitePanel:Remove() end
	if IsValid(panel) then panel:Remove() end
	panel = nil
end

-- Отряд выдвинулся: объявление МОГ, затемнение, вход в игру
net.Receive("ws.lobby.started", function()
	snd("deploy", 0.9)
	hook.Run("WSDeployed")
	if not IsValid(panel) then return end
	M.Closing = RealTime()
	for _, h in pairs(sounds) do h:Stop(1.4) end
	timer.Simple(1.5, M.Close)
end)

hook.Add("HUDShouldDraw", "ws.menu", function()
	if IsValid(panel) then return false end
end)

hook.Add("OnScreenSizeChanged", "ws.menu", function()
	if IsValid(panel) then
		M.Close()
		M.Open()
	end
end)

-- После интро (или сразу, если интро не показывается) — главное меню
hook.Add("WSIntroFinished", "ws.menu", function() M.Open() end)

hook.Add("InitPostEntity", "ws.menu", function()
	timer.Simple(1.0, function()
		if not WS.Intro.IsPlaying() and not L.InGame(LocalPlayer()) then M.Open() end
	end)
end)

-- Если сервер вернул игрока в меню (ws_lobby_reset) — открыть снова
timer.Create("ws.menu.watch", 1, 0, function()
	local me = LocalPlayer()
	if not IsValid(me) or IsValid(panel) or WS.Intro.IsPlaying() then return end
	if me.wsWasInGame and not L.InGame(me) then M.Open() end
	me.wsWasInGame = L.InGame(me)
end)

concommand.Add("ws_menu", function() M.Open() end)
