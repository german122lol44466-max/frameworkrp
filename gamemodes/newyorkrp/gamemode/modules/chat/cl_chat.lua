--[[
	Чат: скруглённая, слегка размытая тёмная панель; снизу линия и поле «Введите сообщение...».
	IC:   Имя сказал: 'сообщение'      (/w — шепнул, /y — крикнул, /me — действие)
	OOC:  [OOC] Ник Steam (Имя): сообщение      (//текст или /ooc)
	LOOC: [LOOC] Ник Steam (Имя): 'сообщение'   (.//текст или /looc)
]]

local UI = NYRP.UI
local Chat = NYRP.Chat
local T = Chat.Types

Chat.Messages = Chat.Messages or {}
Chat.History = Chat.History or {}
local MAX = 120

local COL = {
	name = Color(120, 214, 110),
	text = Color(236, 237, 242),
	whisper = Color(170, 180, 200),
	yell = Color(255, 236, 200),
	me = Color(196, 160, 255),
	ooc = Color(255, 138, 36),
	looc = Color(96, 190, 232),
	steam = Color(200, 205, 220),
	system = Color(150, 155, 170),
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
		segs = { { COL.me, "* " .. nameOf(ply) .. " " .. text } }
	elseif kind == T.OOC then
		segs = { { COL.ooc, "[OOC] " }, { COL.steam, IsValid(ply) and ply:Nick() or "?" }, { COL.name, " (" .. nameOf(ply) .. ")" }, { COL.text, ": " .. text } }
	elseif kind == T.LOOC then
		segs = { { COL.looc, "[LOOC] " }, { COL.steam, IsValid(ply) and ply:Nick() or "?" }, { COL.name, " (" .. nameOf(ply) .. ")" }, { COL.text, ": '" .. text .. "'" } }
	else
		segs = { { COL.system, text } }
	end
	Chat.AddMessage(segs)
	if kind ~= T.OOC and kind ~= T.LOOC and kind ~= T.SYSTEM and IsValid(ply) and NYRP.Overhead then
		NYRP.Overhead.AddBubble(ply, kind, text)
	end
	if kind ~= T.SYSTEM then UI.Sound("hover") end
	MsgC(unpack((function()
		local out = {}
		for _, s in ipairs(segs) do out[#out + 1] = s[1] out[#out + 1] = s[2] end
		out[#out + 1] = "\n"
		return out
	end)()))
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

function chat.GetChatBoxPos()
	return UI.S(24), ScrH() - UI.S(24) - UI.S(340)
end
function chat.GetChatBoxSize()
	return UI.S(620), UI.S(340)
end

-- -------------------------------------------------------------- отрисовка --
local function wrapMessage(m, font, width)
	if m.wrapW == width then return m.lines end
	surface.SetFont(font)
	local lines, line, lineW = {}, {}, 0
	local spaceW = surface.GetTextSize(" ")
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
	m.lines, m.wrapW = lines, width
	return lines
end

local open = false
local openAnim = 0
Chat.Scroll = 0

local function typingKind(text)
	if text == "" then return 0 end
	local kind = Chat.Parse(text)
	if kind == T.OOC or kind == T.LOOC then return 0 end
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

function Chat.Open(prefix)
	if open or NYRP.State ~= "playing" then return end
	open = true
	Chat.Scroll = 0
	local x, y = chat.GetChatBoxPos()
	local w, h = chat.GetChatBoxSize()
	local pnl = vgui.Create("EditablePanel")
	Chat.Panel = pnl
	pnl:SetPos(x, y)
	pnl:SetSize(w, h)
	pnl:MakePopup()
	pnl.Paint = function() end
	pnl.OnMouseWheeled = function(_, d)
		Chat.Scroll = math.max(0, Chat.Scroll + d * 2)
	end
	local entry = vgui.Create("DTextEntry", pnl)
	Chat.Entry = entry
	entry:SetPos(UI.S(16), h - UI.S(44))
	entry:SetSize(w - UI.S(32), UI.S(36))
	entry:SetFont(NYRP.Font("medium", 17))
	entry:SetPaintBackground(false)
	entry:SetPlaceholderText("Введите сообщение...")
	entry:SetHistoryEnabled(false)
	entry:SetText(prefix or "")
	entry:SetCaretPos(#(prefix or ""))
	entry:RequestFocus()
	local histPos = 0
	entry.Paint = function(s, ew, eh)
		if s:GetText() == "" then
			draw.SimpleText("Введите сообщение...", s:GetFont(), UI.S(3), eh / 2, Color(110, 115, 130), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
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
	end
	entry.OnEnter = function(s)
		local txt = string.Trim(s:GetText())
		if txt ~= "" then
			net.Start("nyrp.chat.say")
			net.WriteString(txt)
			net.SendToServer()
			table.insert(Chat.History, 1, txt)
			if #Chat.History > 30 then table.remove(Chat.History) end
		end
		Chat.Close()
	end
	entry.OnKeyCodeTyped = function(s, key)
		if key == KEY_ESCAPE then Chat.Close() return true end
		if key == KEY_UP or key == KEY_DOWN then
			histPos = math.Clamp(histPos + (key == KEY_UP and 1 or -1), 0, #Chat.History)
			s:SetText(Chat.History[histPos] or "")
			s:SetCaretPos(#s:GetText())
			return true
		end
		if key == KEY_ENTER or key == KEY_PAD_ENTER then s:OnEnter() return true end
	end
	sendTyping(typingKind(prefix or ""))
end

function Chat.Close()
	open = false
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

-- Сам чат рисуется в HUD (видно и без открытого поля ввода).
hook.Add("HUDPaint", "nyrp.chat", function()
	if NYRP.State ~= "playing" then return end
	local x, y = chat.GetChatBoxPos()
	local w, h = chat.GetChatBoxSize()
	openAnim = UI.Approach(openAnim, open and 1 or 0, 14)
	if openAnim > 0.01 then
		surface.SetAlphaMultiplier(openAnim)
		UI.BlurRect(x, y, w, h, 3)
		UI.RoundedRect(UI.S(14), x, y, w, h, Color(10, 12, 20, 170))
		UI.Outline(UI.S(14), x, y, w, h, Color(255, 255, 255, 14), 1)
		surface.SetDrawColor(255, 255, 255, 22)
		surface.DrawRect(x + UI.S(16), y + h - UI.S(52), w - UI.S(32), 1)
		UI.RoundedRect(UI.S(10), x + UI.S(8), y + h - UI.S(46), w - UI.S(16), UI.S(40), Color(0, 0, 0, 70))
		surface.SetAlphaMultiplier(1)
	end

	local font = NYRP.Font("medium", 17)
	local lineH = UI.S(22)
	local areaTop = y + UI.S(12)
	local by = y + h - UI.S(60)
	local width = w - UI.S(32)
	local now = RealTime()
	render.SetScissorRect(x, areaTop, x + w, by + UI.S(4), true)
	local skip = Chat.Scroll
	for i = #Chat.Messages, 1, -1 do
		local m = Chat.Messages[i]
		local age = now - m.time
		local a = open and 1 or math.Clamp(1 - (age - 10) / 1.5, 0, 1)
		if a <= 0 and not open then break end
		local lines = wrapMessage(m, font, width)
		for li = #lines, 1, -1 do
			if skip > 0 then
				skip = skip - 1
			else
				by = by - lineH
				if by < areaTop - lineH then break end
				for _, seg in ipairs(lines[li]) do
					local col = seg[1]
					draw.SimpleText(seg[2], font, x + UI.S(16) + seg[3] + 1, by + 1, Color(0, 0, 0, 170 * a))
					draw.SimpleText(seg[2], font, x + UI.S(16) + seg[3], by, Color(col.r, col.g, col.b, 255 * a))
				end
			end
		end
		if by < areaTop then break end
	end
	render.SetScissorRect(0, 0, 0, 0, false)
end)

hook.Add("NYRP.StateChanged", "nyrp.chat", function(state)
	if state ~= "playing" then Chat.Close() end
end)
