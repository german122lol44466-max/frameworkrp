--[[
	Чат на клиенте: своя лента и строка ввода (стандартный чат скрыт).

	Enter (messagemode) — «Рядом», U (messagemode2) — «Отряд»; Tab в строке — сменить режим, ↑/↓ — история,
	Esc — закрыть. Лента внизу слева над HUD: сообщения гаснут через 12 с, при открытом чате видна история
	(колесо — прокрутка). Сообщения других аддонов (chat.AddText) и системные (вход/выход) тоже попадают сюда.
]]

local CH = WS.Chat
local L = WS.Lobby
local UI = WS.UI
local E = WS.Ease

local lines = {}          -- { t, markup-исходник, кэш }
local MAX_LINES = 120
local history, histPos = {}, 0
local box, entry, mode = nil, nil, "local"
local scroll = 0

function CH.IsOpen()
	return IsValid(box) and box:IsVisible()
end

local function esc(s)
	return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function colTag(c, s)
	return string.format("<color=%d,%d,%d>%s</color>", c.r, c.g, c.b, s)
end

local function push(src, snd)
	lines[#lines + 1] = { t = RealTime(), src = src }
	if #lines > MAX_LINES then table.remove(lines, 1) end
	if not CH.IsOpen() then scroll = 0 end
	if snd then WS.Audio.Play(snd, { volume = 0.35 }) end
end

local GOLD, WHITE, GREY = Color(226, 190, 120), Color(236, 239, 244), Color(160, 168, 180)

-- Сообщение игрока
net.Receive("ws.chat.msg", function()
	local ply = net.ReadEntity()
	local m = CH.ModeName[net.ReadUInt(3)] or "local"
	local text = net.ReadString()
	if not IsValid(ply) then return end
	local me = LocalPlayer()
	local mate = L.Id(ply) ~= 0 and L.Id(ply) == L.Id(me)
	local nameCol = mate and GOLD or WHITE
	local name = esc(L.Name(ply))
	local src
	if m == "me" then
		src = colTag(Color(190, 160, 230), "* " .. name .. " " .. esc(text))
	elseif m == "squad" then
		src = colTag(GOLD, "[ОТРЯД] ") .. colTag(nameCol, name) .. colTag(GREY, ": ") .. colTag(Color(240, 226, 196), esc(text))
	elseif m == "ooc" then
		src = colTag(GREY, "[ВСЕМ] ") .. colTag(nameCol, name) .. colTag(GREY, ": " .. esc(text))
	elseif m == "phrase" then
		src = colTag(Color(196, 38, 38), "[ГОЛОС] ") .. colTag(nameCol, name) .. colTag(GREY, ": ") .. colTag(WHITE, "«" .. esc(text) .. "»")
	else
		src = colTag(nameCol, name) .. colTag(GREY, ": ") .. colTag(WHITE, esc(text))
	end
	push(src, m == "squad" and "whitesilence/game/radio.ogg" or "whitesilence/game/tick.ogg")
	MsgC(nameCol, L.Name(ply), GREY, " [" .. m .. "]: ", WHITE, text, "\n")
end)

-- chat.AddText других аддонов → в нашу ленту (и, как раньше, в консоль)
local origAddText = CH.OrigAddText or chat.AddText
CH.OrigAddText = origAddText
function chat.AddText(...)
	local src, col = {}, WHITE
	for _, v in ipairs({ ... }) do
		if istable(v) and v.r then col = v
		elseif isentity(v) and IsValid(v) and v:IsPlayer() then src[#src + 1] = colTag(GOLD, esc(L.Name(v)))
		elseif v ~= nil then src[#src + 1] = colTag(col, esc(tostring(v))) end
	end
	if #src > 0 then push(table.concat(src), "whitesilence/game/tick.ogg") end
	return origAddText(...)
end

-- системные сообщения (вход/выход, смена ника и т.п.)
hook.Add("ChatText", "ws.chat", function(index, name, text, kind)
	if kind == "chat" then return end
	push(colTag(GREY, esc(text)))
	return true
end)

-- ---------------------------------------------------------------- строка ввода

local function send()
	local text = CH.Clean(entry:GetValue() or "")
	if text ~= "" then
		net.Start("ws.chat.say")
		net.WriteUInt(CH.ModeId[mode], 3)
		net.WriteString(text)
		net.SendToServer()
		table.insert(history, 1, text)
		if #history > 30 then table.remove(history) end
	end
	histPos = 0
	CH.Close()
end

local function placeholder()
	return mode == "squad" and "Отряду по рации…" or mode == "ooc" and "Всем на сервере…" or "Сказать рядом…  (/me — действие)"
end

function CH.Open(m)
	mode = m or "local"
	local s = ScrH() / 1080
	if not IsValid(box) then
		box = vgui.Create("EditablePanel")
		box.Paint = nil
		entry = vgui.Create("DTextEntry", box)
		entry:SetFont(WS.Font("menu", 19))
		entry:SetUpdateOnType(true)
		entry:SetDrawLanguageID(false)
		entry.AllowInput = function(self, ch)
			-- лимит по символам, а не байтам
			return utf8.len(self:GetValue() or "") >= CH.MaxLen
		end
		entry.Paint = function(self, w, h)
			draw.RoundedBox(4, 0, 0, w, h, Color(6, 8, 12, 225))
			local c = mode == "squad" and GOLD or mode == "ooc" and GREY or WHITE
			surface.SetDrawColor(c.r, c.g, c.b, 160)
			surface.DrawRect(0, 0, 3 * s, h)
			-- метка режима слева
			draw.SimpleText(CH.Label[mode], WS.Font("menusemi", 15), 12 * s, h / 2, c, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			if (self:GetValue() or "") == "" then
				draw.SimpleText(placeholder(), WS.Font("menulight", 17), 84 * s, h / 2, Color(130, 138, 150), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
			self:DrawTextEntryText(Color(240, 242, 246), Color(196, 38, 38, 160), Color(255, 255, 255))
			draw.SimpleText(utf8.len(self:GetValue() or "") .. "/" .. CH.MaxLen, WS.Font("menulight", 13), w - 8 * s, h / 2,
				Color(120, 128, 140), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
		entry:SetTextInset(84 * s, 0)
		entry.OnEnter = send
		entry.OnKeyCodeTyped = function(self, code)
			if code == KEY_ESCAPE then
				CH.Close()
				gui.HideGameUI()
				return true
			elseif code == KEY_TAB then
				local i = (CH.ModeId[mode] % #CH.Modes) + 1
				mode = CH.Modes[i]
				return true
			elseif code == KEY_UP or code == KEY_DOWN then
				histPos = math.Clamp(histPos + (code == KEY_UP and 1 or -1), 0, #history)
				self:SetText(history[histPos] or "")
				self:SetCaretPos(utf8.len(self:GetValue()) or 0)
				return true
			elseif code == KEY_ENTER or code == KEY_PAD_ENTER then
				send()
				return true
			end
		end
		box.OnMouseWheeled = function(_, d) scroll = math.max(0, scroll + d * 3) end
	end
	local w = 600 * s
	box:SetSize(w, 300 * s)
	box:SetPos(26 * s, ScrH() - 548 * s)
	entry:SetSize(w, 38 * s)
	entry:SetPos(0, 262 * s)
	entry:SetTextInset(84 * s, 0)
	box:SetVisible(true)
	box:MakePopup()
	entry:SetText("")
	entry:RequestFocus()
	scroll = 0
end

function CH.Close()
	if IsValid(box) then
		box:SetVisible(false)
		box:KillFocus()
	end
end

hook.Add("PlayerBindPress", "ws.chat", function(ply, bind, pressed)
	if not pressed then return end
	if bind == "messagemode" or bind:find("^messagemode$") then CH.Open("local") return true end
	if bind == "messagemode2" or bind:find("^messagemode2$") then CH.Open("squad") return true end
end)

-- ---------------------------------------------------------------- лента

local function parsed(line, width)
	if line.w ~= width then
		line.mk = markup.Parse("<font=" .. WS.Font("menu", 18) .. ">" .. line.src .. "</font>", width)
		line.w = width
	end
	return line.mk
end

hook.Add("HUDPaint", "ws.chat", function()
	local s = ScrH() / 1080
	local x, bottom = 26 * s, ScrH() - 292 * s
	local w = 600 * s
	local open = CH.IsOpen()
	if open then
		draw.RoundedBox(4, x - 8 * s, bottom - 252 * s, w + 16 * s, 262 * s, Color(4, 6, 9, 150))
	end
	local y = bottom
	local now = RealTime()
	local skipped = 0
	for i = #lines, 1, -1 do
		local line = lines[i]
		local age = now - line.t
		local a = open and 1 or (1 - E.Smooth((age - 11) / 1.5))
		if a > 0 then
			if open and skipped < scroll then
				skipped = skipped + 1
			else
				local mk = parsed(line, w)
				local h = mk:GetHeight()
				y = y - h - 4 * s
				if y < bottom - 250 * s then break end
				if not open then
					-- мягкая тёмная подложка под строкой, чтобы читалось на светлом снегу
					draw.RoundedBox(3, x - 6 * s, y - 2 * s, mk:GetWidth() + 12 * s, h + 4 * s, Color(0, 0, 0, 110 * a))
				end
				mk:Draw(x, y, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 255 * a)
			end
		elseif not open then
			break
		end
	end
end)
