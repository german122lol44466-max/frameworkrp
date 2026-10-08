--[[
	Чат: окно с заголовком «Чат» — перетаскивается за заголовок и растягивается за угол
	(положение/размер сохраняются). Внизу строка ввода: слева — выбор типа чата,
	при «/» всплывает список команд.
	IC:   Имя сказал: 'сообщение'      (/w — шепнул, /y — крикнул)
	/me:  ** Имя действие              /it:  ** описание окружения
	OOC:  [OOC] Ник Steam (Имя): сообщение      LOOC: [LOOC] Ник Steam (Имя): 'сообщение'
]]

local UI = NYRP.UI
local Chat = NYRP.Chat
local T = Chat.Types

Chat.Messages = Chat.Messages or {}
Chat.History = Chat.History or {}
local MAX = 150
local HEADER, INPUT = 36, 46

local COL = {
	name = Color(120, 214, 110), text = Color(236, 237, 242), whisper = Color(170, 180, 200),
	yell = Color(255, 236, 200), me = Color(196, 160, 255), it = Color(232, 204, 140),
	ooc = Color(255, 138, 36), looc = Color(96, 190, 232), steam = Color(200, 205, 220), system = Color(150, 155, 170),
}

Chat.Modes = {
	{ id = "ic", label = "Сказать", icon = "message", prefix = "", desc = "Обычная речь", kind = T.IC },
	{ id = "w", label = "Шёпот", icon = "ear", prefix = "/w ", desc = "Слышно совсем рядом", kind = T.WHISPER },
	{ id = "y", label = "Крик", icon = "speaker", prefix = "/y ", desc = "Слышно далеко", kind = T.YELL },
	{ id = "me", label = "Действие", icon = "hand", prefix = "/me ", desc = "Выполняет действие: ** Имя …", kind = T.ME },
	{ id = "it", label = "Окружение", icon = "eye", prefix = "/it ", desc = "** описание обстановки", kind = T.IT },
	{ id = "looc", label = "LOOC", icon = "users", prefix = ".// ", desc = "Вне роли — только рядом", kind = T.LOOC },
	{ id = "ooc", label = "OOC", icon = "world", prefix = "// ", desc = "Вне роли — весь сервер", kind = T.OOC },
}
Chat.Mode = Chat.Mode or 1

Chat.Commands = {
	{ "/w", "Шёпот — слышно совсем рядом" },
	{ "/y", "Крик — слышно далеко" },
	{ "/me", "Выполняет действие: ** Имя действие" },
	{ "/it", "Окружение: ** описание обстановки" },
	{ "/looc", "Локальный OOC (вне роли, рядом)" },
	{ "/ooc", "Глобальный OOC (вне роли, всем)" },
	{ "//", "Глобальный OOC — коротко" },
	{ ".//", "Локальный OOC — коротко" },
	{ "/познакомиться", "Представиться тому, на кого смотрите" },
	{ "/introduce", "То же, что /познакомиться" },
}

-- msg = { segs = { {Color, "текст"}, ... }, time }
function Chat.AddMessage(segs)
	table.insert(Chat.Messages, { segs = segs, time = RealTime() })
	if #Chat.Messages > MAX then table.remove(Chat.Messages, 1) end
	Chat.Scroll = 0
end

local function nameOf(ply)
	if not IsValid(ply) then return "?" end
	if NYRP.Config.ChatUseRecognition and NYRP.Recog and not NYRP.Recog.Knows(ply) then return "Неизвестный" end
	return NYRP.CharName(ply)
end

net.Receive("nyrp.chat.msg", function()
	local kind, ply, text = net.ReadUInt(4), net.ReadEntity(), net.ReadString()
	local segs
	if kind == T.IC then
		segs = { { COL.name, nameOf(ply) }, { COL.text, " сказал: " }, { COL.text, "'" .. text .. "'" } }
	elseif kind == T.WHISPER then
		segs = { { COL.name, nameOf(ply) }, { COL.whisper, " шепнул: " }, { COL.whisper, "'" .. text .. "'" } }
	elseif kind == T.YELL then
		segs = { { COL.name, nameOf(ply) }, { COL.yell, " крикнул: " }, { COL.yell, "'" .. text .. "'" } }
	elseif kind == T.ME then
		segs = { { COL.me, "** " }, { COL.name, nameOf(ply) }, { COL.me, " " .. text } }
	elseif kind == T.IT then
		segs = { { COL.it, "** " .. text } }
	elseif kind == T.OOC then
		segs = { { COL.ooc, "[OOC] " }, { COL.steam, IsValid(ply) and ply:Nick() or "?" }, { COL.name, " (" .. nameOf(ply) .. ")" }, { COL.text, ": " .. text } }
	elseif kind == T.LOOC then
		segs = { { COL.looc, "[LOOC] " }, { COL.steam, IsValid(ply) and ply:Nick() or "?" }, { COL.name, " (" .. nameOf(ply) .. ")" }, { COL.text, ": '" .. text .. "'" } }
	else
		segs = { { COL.system, text } }
	end
	Chat.AddMessage(segs)
	if (kind == T.IC or kind == T.WHISPER or kind == T.YELL or kind == T.ME) and IsValid(ply) and NYRP.Overhead.AddBubble then
		NYRP.Overhead.AddBubble(ply, kind, text)
	end
	if kind ~= T.SYSTEM then UI.Sound("hover") end
	local out = {}
	for _, s in ipairs(segs) do out[#out + 1] = s[1] out[#out + 1] = s[2] end
	out[#out + 1] = "\n"
	MsgC(unpack(out))
end)

-- chat.AddText от других аддонов — тоже в наш чат.
local origAddText = chat.NYRPOrigAddText or chat.AddText
chat.NYRPOrigAddText = origAddText
function chat.AddText(...)
	local segs, col = {}, COL.text
	for _, v in ipairs({ ... }) do
		if IsColor(v) or (istable(v) and v.r) then col = Color(v.r, v.g, v.b)
		elseif isentity(v) and v:IsPlayer() then segs[#segs + 1] = { COL.name, NYRP.CharName(v) }
		else segs[#segs + 1] = { col, tostring(v) } end
	end
	Chat.AddMessage(segs)
	return origAddText(...)
end

function GM:ChatText(index, name, text, kind)
	if kind == "joinleave" or kind == "none" or kind == "servermsg" or kind == "namechange" or kind == "teamchange" then
		Chat.AddMessage({ { COL.system, text } })
	end
	return true
end

function GM:OnPlayerChat(ply, text)
	Chat.AddMessage({ { COL.name, IsValid(ply) and ply:Nick() or "Консоль" }, { COL.text, ": " .. text } })
	return true
end

-- ------------------------------------------------------- геометрия окна --
function Chat.Rect()
	local sw, sh = ScrW(), ScrH()
	local w = math.Clamp(GetConVar("nyrp_chat_w"):GetFloat() * sw, UI.S(360), sw)
	local h = math.Clamp(GetConVar("nyrp_chat_h"):GetFloat() * sh, UI.S(220), sh)
	local x = math.Clamp(GetConVar("nyrp_chat_x"):GetFloat() * sw, 0, sw - w)
	local y = math.Clamp(GetConVar("nyrp_chat_y"):GetFloat() * sh, 0, sh - h)
	return x, y, w, h
end

local function saveRect(x, y, w, h)
	RunConsoleCommand("nyrp_chat_x", tostring(x / ScrW()))
	RunConsoleCommand("nyrp_chat_y", tostring(y / ScrH()))
	if w then
		RunConsoleCommand("nyrp_chat_w", tostring(w / ScrW()))
		RunConsoleCommand("nyrp_chat_h", tostring(h / ScrH()))
	end
end

function chat.GetChatBoxPos()
	local x, y = Chat.Rect()
	return x, y
end
function chat.GetChatBoxSize()
	local _, _, w, h = Chat.Rect()
	return w, h
end

-- --------------------------------------------------------- сообщения --
local function wrapMessage(m, font, width)
	if m.wrapW == width and m.wrapF == font then return m.lines end
	surface.SetFont(font)
	local lines, line, lineW = {}, {}, 0
	for _, seg in ipairs(m.segs) do
		local col, text = seg[1], seg[2]
		for word, sp in string.gmatch(text, "(%S*)(%s*)") do
			if word == "" and sp == "" then break end
			local piece = word .. (sp ~= "" and " " or "")
			local pw = surface.GetTextSize(piece)
			if lineW + pw > width and lineW > 0 then
				lines[#lines + 1] = line
				line, lineW = {}, 0
			end
			line[#line + 1] = { col, piece, lineW }
			lineW = lineW + pw
		end
	end
	if #line > 0 then lines[#lines + 1] = line end
	m.lines, m.wrapW, m.wrapF = lines, width, font
	return lines
end

Chat.Scroll = 0
local open = false

-- Рисует сообщения в прямоугольнике (координаты текущего контекста; sx, sy — его экранный сдвиг).
local function drawMessages(x, y, w, h, sx, sy, isOpen)
	local font = NYRP.Font("medium", 17)
	local lineH = UI.S(22)
	local by = y + h
	local width = w - UI.S(28)
	local now = RealTime()
	render.SetScissorRect(sx + x, sy + y, sx + x + w, sy + y + h, true)
	local skip = Chat.Scroll
	for i = #Chat.Messages, 1, -1 do
		local m = Chat.Messages[i]
		local a = isOpen and 1 or math.Clamp(1 - (now - m.time - 10) / 1.5, 0, 1)
		if a <= 0 then break end
		local lines = wrapMessage(m, font, width)
		for li = #lines, 1, -1 do
			if skip > 0 then
				skip = skip - 1
			else
				by = by - lineH
				if by < y - lineH then break end
				for _, seg in ipairs(lines[li]) do
					local col = seg[1]
					draw.SimpleText(seg[2], font, x + UI.S(14) + seg[3] + 1, by + 1, Color(0, 0, 0, 170 * a))
					draw.SimpleText(seg[2], font, x + UI.S(14) + seg[3], by, Color(col.r, col.g, col.b, 255 * a))
				end
			end
		end
		if by < y then break end
	end
	render.SetScissorRect(0, 0, 0, 0, false)
end

-- ----------------------------------------------------------- набор --
local function typingKind(text)
	local kind = Chat.Parse(text)
	if string.sub(text, 1, 1) ~= "/" and string.sub(text, 1, 1) ~= "." then kind = Chat.Modes[Chat.Mode].kind end
	if text == "" or kind == T.OOC or kind == T.LOOC then return 0 end
	return kind
end

local lastTyping = -1
local function sendTyping(k)
	if k == lastTyping then return end
	lastTyping = k
	net.Start("nyrp.chat.typing")
	net.WriteUInt(k, 4)
	net.SendToServer()
end

local function closePopups()
	if IsValid(Chat.ModeList) then Chat.ModeList:Remove() end
	if IsValid(Chat.Suggest) then Chat.Suggest:Remove() end
end

-- Список типов чата над кнопкой выбора.
local function openModeList(btn)
	if IsValid(Chat.ModeList) then Chat.ModeList:Remove() return end
	local pnl = Chat.Panel
	local rowH = UI.S(46)
	local list = vgui.Create("DPanel", pnl)
	Chat.ModeList = list
	local w, h = UI.S(250), #Chat.Modes * rowH + UI.S(46)
	list:SetSize(w, h)
	local bx, by = btn:GetPos()
	list:SetPos(bx, by - h - UI.S(6))
	list.Born = RealTime()
	list.Paint = function(s, pw, ph)
		s:SetAlpha(255 * UI.Ease((RealTime() - s.Born) / 0.15))
		UI.RoundedRect(UI.S(12), 0, 0, pw, ph, Color(14, 16, 24, 248))
		UI.Outline(UI.S(12), 0, 0, pw, ph, Color(255, 255, 255, 20), 1)
		draw.SimpleText("ТИП СООБЩЕНИЯ", NYRP.Font("title", 14), UI.S(14), UI.S(20), UI.Col.faint, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	for i, m in ipairs(Chat.Modes) do
		local b = vgui.Create("DButton", list)
		b:SetText("")
		b:SetPos(UI.S(6), UI.S(38) + (i - 1) * rowH)
		b:SetSize(w - UI.S(12), rowH - UI.S(4))
		b.Hover = 0
		b.Paint = function(s, bw, bh)
			local sel = Chat.Mode == i
			s.Hover = UI.Approach(s.Hover, (s:IsHovered() or sel) and 1 or 0, 14)
			UI.RoundedRect(UI.S(8), 0, 0, bw, bh, sel and UI.Alpha(UI.Col.accent, 34) or Color(255, 255, 255, 10 * s.Hover))
			UI.Circle(UI.S(20), bh / 2, UI.S(14), sel and UI.Col.accent or Color(255, 255, 255, 16))
			UI.DrawIcon(m.icon, UI.S(20), bh / 2, UI.S(15), sel and UI.Col.black or UI.Col.dim)
			draw.SimpleText(m.label, NYRP.Font("semibold", 15), UI.S(44), bh / 2 - UI.S(1), UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
			draw.SimpleText(m.desc, NYRP.Font("regular", 12), UI.S(44), bh / 2 + UI.S(1), UI.Col.faint, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
			return true
		end
		b.OnCursorEntered = function() UI.Sound("hover") end
		b.DoClick = function()
			UI.Sound("click")
			Chat.Mode = i
			list:Remove()
			if IsValid(Chat.Entry) then
				Chat.Entry:RequestFocus()
				sendTyping(typingKind(Chat.Entry:GetText()))
			end
		end
	end
end

-- Подсказка команд при «/».
local function updateSuggest()
	local entry = Chat.Entry
	if not IsValid(entry) then return end
	local text = entry:GetText()
	local first = string.sub(text, 1, 1)
	local word = string.match(text, "^(%S*)$")
	if not word or (first ~= "/" and first ~= ".") then
		if IsValid(Chat.Suggest) then Chat.Suggest:Remove() end
		return
	end
	local found = {}
	for _, c in ipairs(Chat.Commands) do
		if string.sub(c[1], 1, #word) == word then found[#found + 1] = c end
	end
	if #found == 0 then
		if IsValid(Chat.Suggest) then Chat.Suggest:Remove() end
		return
	end
	if not IsValid(Chat.Suggest) then
		Chat.Suggest = vgui.Create("DPanel", Chat.Panel)
		Chat.Suggest.Paint = function(s, pw, ph)
			UI.RoundedRect(UI.S(10), 0, 0, pw, ph, Color(14, 16, 24, 248))
			UI.Outline(UI.S(10), 0, 0, pw, ph, Color(255, 255, 255, 20), 1)
		end
	end
	local sug = Chat.Suggest
	sug:Clear()
	local rowH = UI.S(30)
	local ex, ey = entry:GetPos()
	local w = math.min(Chat.Panel:GetWide() - ex - UI.S(10), UI.S(420))
	sug:SetSize(w, #found * rowH + UI.S(10))
	sug:SetPos(ex, ey - sug:GetTall() - UI.S(8))
	for i, c in ipairs(found) do
		local b = vgui.Create("DButton", sug)
		b:SetText("")
		b:SetPos(UI.S(5), UI.S(5) + (i - 1) * rowH)
		b:SetSize(w - UI.S(10), rowH)
		b.Paint = function(s, bw, bh)
			if s:IsHovered() or i == 1 then UI.RoundedRect(UI.S(6), 0, 0, bw, bh, Color(255, 255, 255, s:IsHovered() and 16 or 8)) end
			draw.SimpleText(c[1], NYRP.Font("bold", 15), UI.S(10), bh / 2, UI.Col.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText(c[2], NYRP.Font("regular", 14), UI.S(130), bh / 2, UI.Col.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			return true
		end
		b.DoClick = function()
			entry:SetText(c[1] .. " ")
			entry:SetCaretPos(#entry:GetText())
			entry:RequestFocus()
			sug:Remove()
		end
	end
	Chat.SuggestFirst = found[1][1]
end

function Chat.Open(prefix)
	if open or NYRP.State ~= "playing" then return end
	open = true
	Chat.Scroll = 0
	local x, y, w, h = Chat.Rect()
	local pnl = vgui.Create("EditablePanel")
	Chat.Panel = pnl
	pnl:SetPos(x, y)
	pnl:SetSize(w, h)
	pnl:MakePopup()
	pnl.Born = RealTime()

	pnl.Paint = function(s, pw, ph)
		local t = UI.Ease((RealTime() - s.Born) / 0.15)
		UI.RoundedBlurPanel(s, UI.S(14), 3 * t)
		UI.RoundedRect(UI.S(14), 0, 0, pw, ph, Color(10, 12, 20, 185 * t))
		UI.Outline(UI.S(14), 0, 0, pw, ph, Color(255, 255, 255, 16), 1)
		-- заголовок
		local hh = UI.S(HEADER)
		UI.DrawIcon("message", UI.S(22), hh / 2 + UI.S(2), UI.S(17), UI.Col.accent)
		draw.SimpleText("ЧАТ", NYRP.Font("title", 18), UI.S(38), hh / 2 + UI.S(2), UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText("перетащите заголовок · угол — размер", NYRP.Font("regular", 12), pw - UI.S(14), hh / 2 + UI.S(2), UI.Col.faint, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		surface.SetDrawColor(255, 255, 255, 18)
		surface.DrawRect(UI.S(12), hh, pw - UI.S(24), 1)
		-- сообщения
		local sx, sy = s:LocalToScreen(0, 0)
		local ih = UI.S(INPUT)
		drawMessages(0, hh + UI.S(6), pw, ph - hh - ih - UI.S(20), sx, sy, true)
		-- линия над полем ввода и поле
		surface.SetDrawColor(255, 255, 255, 22)
		surface.DrawRect(UI.S(12), ph - ih - UI.S(12), pw - UI.S(24), 1)
		UI.RoundedRect(UI.S(10), UI.S(8), ph - ih - UI.S(4), pw - UI.S(16), ih - UI.S(4), Color(0, 0, 0, 80))
		-- уголок изменения размера
		for i = 0, 2 do
			surface.SetDrawColor(255, 255, 255, 50)
			surface.DrawLine(pw - UI.S(4) - i * UI.S(4), ph - UI.S(3), pw - UI.S(3), ph - UI.S(4) - i * UI.S(4))
		end
	end
	pnl.OnMouseWheeled = function(_, d) Chat.Scroll = math.max(0, Chat.Scroll + d * 2) end

	-- перетаскивание за заголовок
	local drag = vgui.Create("DPanel", pnl)
	drag.Paint = function() end
	drag:SetCursor("sizeall")
	drag.OnMousePressed = function(s, code)
		if code ~= MOUSE_LEFT then return end
		local px, py = pnl:GetPos()
		s.Grab = { gui.MouseX() - px, gui.MouseY() - py }
		s:MouseCapture(true)
	end
	drag.OnMouseReleased = function(s)
		s.Grab = nil
		s:MouseCapture(false)
		local px, py = pnl:GetPos()
		saveRect(px, py)
	end
	drag.Think = function(s)
		if not s.Grab then return end
		local pw, ph = pnl:GetSize()
		pnl:SetPos(math.Clamp(gui.MouseX() - s.Grab[1], 0, ScrW() - pw), math.Clamp(gui.MouseY() - s.Grab[2], 0, ScrH() - ph))
	end

	-- изменение размера за правый нижний угол
	local grip = vgui.Create("DPanel", pnl)
	grip.Paint = function() end
	grip:SetCursor("sizenwse")
	grip.OnMousePressed = function(s, code)
		if code ~= MOUSE_LEFT then return end
		s.Start = { gui.MouseX(), gui.MouseY(), pnl:GetWide(), pnl:GetTall() }
		s:MouseCapture(true)
	end
	grip.OnMouseReleased = function(s)
		s.Start = nil
		s:MouseCapture(false)
		local px, py = pnl:GetPos()
		saveRect(px, py, pnl:GetWide(), pnl:GetTall())
	end
	grip.Think = function(s)
		if not s.Start then return end
		local px, py = pnl:GetPos()
		local nw = math.Clamp(s.Start[3] + gui.MouseX() - s.Start[1], UI.S(360), ScrW() - px)
		local nh = math.Clamp(s.Start[4] + gui.MouseY() - s.Start[2], UI.S(220), ScrH() - py)
		pnl:SetSize(nw, nh)
		closePopups()
	end

	-- кнопка выбора типа чата
	local modeBtn = vgui.Create("DButton", pnl)
	modeBtn:SetText("")
	modeBtn.Hover = 0
	modeBtn.Paint = function(s, bw, bh)
		local m = Chat.Modes[Chat.Mode]
		s.Hover = UI.Approach(s.Hover, s:IsHovered() and 1 or 0, 14)
		UI.RoundedRect(UI.S(8), 0, 0, bw, bh, UI.LerpColor(s.Hover, Color(255, 255, 255, 12), UI.Alpha(UI.Col.accent, 50)))
		UI.DrawIcon(m.icon, UI.S(16), bh / 2, UI.S(15), UI.Col.accent)
		draw.SimpleText(m.label, NYRP.Font("semibold", 14), UI.S(30), bh / 2, UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		UI.DrawIcon("chevron_right", bw - UI.S(12), bh / 2, UI.S(12), UI.Col.faint)
		return true
	end
	modeBtn.DoClick = function(s) UI.Sound("click") openModeList(s) end

	local entry = vgui.Create("DTextEntry", pnl)
	Chat.Entry = entry
	entry:SetFont(NYRP.Font("medium", 17))
	entry:SetPaintBackground(false)
	entry:SetHistoryEnabled(false)
	entry:SetText(prefix or "")
	entry:SetCaretPos(#(prefix or ""))
	entry:RequestFocus()
	local histPos = 0
	entry.Paint = function(s, ew, eh)
		if s:GetText() == "" then
			draw.SimpleText("Введите сообщение...", s:GetFont(), UI.S(3), eh / 2, Color(105, 110, 125), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		s:DrawTextEntryText(UI.Col.text, UI.Alpha(UI.Col.accent, 90), UI.Col.accent)
		local len = utf8.len(s:GetText()) or 0
		if len > NYRP.Config.ChatLimit * 0.8 then
			draw.SimpleText(len .. "/" .. NYRP.Config.ChatLimit, NYRP.Font("medium", 12), ew, eh / 2, UI.Col.faint, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
	end
	entry.OnChange = function(s)
		local txt = s:GetText()
		if utf8.len(txt) and utf8.len(txt) > NYRP.Config.ChatLimit then
			s:SetText(string.sub(txt, 1, utf8.offset(txt, NYRP.Config.ChatLimit + 1) - 1))
			s:SetCaretPos(#s:GetText())
		end
		sendTyping(typingKind(s:GetText()))
		updateSuggest()
	end
	entry.OnEnter = function(s)
		local txt = string.Trim(s:GetText())
		if txt ~= "" then
			local first = string.sub(txt, 1, 1)
			if first ~= "/" and first ~= "." then txt = Chat.Modes[Chat.Mode].prefix .. txt end
			net.Start("nyrp.chat.say")
			net.WriteString(txt)
			net.SendToServer()
			table.insert(Chat.History, 1, s:GetText())
			if #Chat.History > 30 then table.remove(Chat.History) end
		end
		Chat.Close()
	end
	entry.OnKeyCodeTyped = function(s, key)
		if key == KEY_ESCAPE then Chat.Close() return true end
		if key == KEY_TAB and IsValid(Chat.Suggest) and Chat.SuggestFirst then
			s:SetText(Chat.SuggestFirst .. " ")
			s:SetCaretPos(#s:GetText())
			Chat.Suggest:Remove()
			return true
		end
		if key == KEY_UP or key == KEY_DOWN then
			histPos = math.Clamp(histPos + (key == KEY_UP and 1 or -1), 0, #Chat.History)
			s:SetText(Chat.History[histPos] or "")
			s:SetCaretPos(#s:GetText())
			return true
		end
		if key == KEY_ENTER or key == KEY_PAD_ENTER then s:OnEnter() return true end
	end

	pnl.PerformLayout = function(s, pw, ph)
		local ih = UI.S(INPUT)
		drag:SetPos(0, 0)
		drag:SetSize(pw, UI.S(HEADER))
		grip:SetSize(UI.S(18), UI.S(18))
		grip:SetPos(pw - UI.S(18), ph - UI.S(18))
		modeBtn:SetPos(UI.S(14), ph - ih + UI.S(2))
		modeBtn:SetSize(UI.S(132), ih - UI.S(16))
		entry:SetPos(UI.S(156), ph - ih + UI.S(2))
		entry:SetSize(pw - UI.S(156) - UI.S(24), ih - UI.S(16))
	end
	sendTyping(typingKind(prefix or ""))
	updateSuggest()
end

function Chat.Close()
	open = false
	closePopups()
	if IsValid(Chat.Panel) then Chat.Panel:Remove() end
	sendTyping(0)
end

function Chat.IsOpen() return open end

hook.Add("PlayerBindPress", "nyrp.chat", function(ply, bind, pressed)
	if not pressed then return end
	if string.find(bind, "messagemode2", 1, true) then
		Chat.Open("// ")
		return true
	elseif string.find(bind, "messagemode", 1, true) then
		Chat.Open()
		return true
	end
end)

-- Закрытый чат: последние сообщения на месте окна, без фона, постепенно гаснут.
hook.Add("HUDPaint", "nyrp.chat", function()
	if NYRP.State ~= "playing" or open then return end
	local x, y, w, h = Chat.Rect()
	drawMessages(x, y + UI.S(HEADER) + UI.S(6), w, h - UI.S(HEADER) - UI.S(INPUT) - UI.S(20), 0, 0, false)
end)

hook.Add("NYRP.StateChanged", "nyrp.chat", function(state)
	if state ~= "playing" then Chat.Close() end
end)
