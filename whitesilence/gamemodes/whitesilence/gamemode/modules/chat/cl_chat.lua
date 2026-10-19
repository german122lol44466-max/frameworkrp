--[[
	Чат на клиенте: своя лента и строка ввода (стандартный чат скрыт).

	Лента (слева, над микро-слотами): каждое сообщение — карточка: цветная полоса канала, метка канала
	(РЯДОМ / ОТРЯД / ВСЕМ / ГОЛОС / ПАВШИЕ / СИСТЕМА), аватар Steam, время, имя и текст. Новое сообщение
	выезжает слева; через 12 с лента гаснет, при открытом чате видна история (колесо — прокрутка).
	Строка ввода — стеклянная панель с вкладками каналов: Enter (messagemode) — «Рядом», U (messagemode2) —
	«Отряд»; Tab — сменить канал, стрелки вверх/вниз — история, Esc — закрыть, счётчик символов полосой.
	Пока пишешь — над головой у других видно «печатает…».
	Сообщения других аддонов (chat.AddText) и системные (вход/выход) тоже попадают сюда.
]]

local CH = WS.Chat
local L = WS.Lobby
local UI = WS.UI
local E = WS.Ease

local lines = {}          -- { t, kind, ply, src (markup), time }
local MAX_LINES = 120
local history, histPos = {}, 0
local box, entry, mode = nil, nil, "local"
local scroll = 0

local GOLD, WHITE, GREY = Color(226, 190, 120), Color(236, 239, 244), Color(160, 168, 180)
local KIND = {
	["local"] = { "РЯДОМ", Color(200, 206, 214) },
	squad = { "ОТРЯД", Color(226, 190, 120) },
	ooc = { "ВСЕМ", Color(130, 160, 200) },
	me = { "ДЕЙСТВИЕ", Color(190, 160, 230) },
	phrase = { "ГОЛОС", Color(214, 92, 84) },
	dead = { "ПАВШИЕ", Color(150, 110, 110) },
	system = { "СИСТЕМА", Color(130, 138, 150) },
}

function CH.IsOpen()
	return IsValid(box) and box:IsVisible()
end

local function esc(s)
	return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function colTag(c, s)
	return string.format("<color=%d,%d,%d>%s</color>", c.r, c.g, c.b, s)
end

local function push(kind, ply, src, snd)
	lines[#lines + 1] = { t = RealTime(), kind = kind, ply = ply, src = src, time = os.date("%H:%M") }
	if #lines > MAX_LINES then table.remove(lines, 1) end
	if not CH.IsOpen() then scroll = 0 end
	if snd then WS.Audio.Play(snd, { volume = 0.35 }) end
end

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
		src = colTag(Color(200, 176, 236), name .. " " .. esc(text))
	elseif m == "squad" then
		src = colTag(nameCol, name) .. colTag(GREY, "  ") .. colTag(Color(240, 228, 200), esc(text))
	elseif m == "phrase" then
		src = colTag(nameCol, name) .. colTag(GREY, "  ") .. colTag(WHITE, "«" .. esc(text) .. "»")
	elseif m == "dead" then
		src = colTag(Color(190, 150, 150), name) .. colTag(GREY, "  " .. esc(text))
	else
		src = colTag(nameCol, name) .. colTag(GREY, "  ") .. colTag(WHITE, esc(text))
	end
	push(m, ply, src, m == "squad" and "whitesilence/game/radio.ogg" or "whitesilence/game/tick.ogg")
	MsgC(nameCol, L.Name(ply), GREY, " [" .. m .. "]: ", WHITE, text, "\n")
end)

-- chat.AddText других аддонов → в нашу ленту (и, как раньше, в консоль)
local origAddText = CH.OrigAddText or chat.AddText
CH.OrigAddText = origAddText
function chat.AddText(...)
	local src, col, who = {}, WHITE, nil
	for _, v in ipairs({ ... }) do
		if istable(v) and v.r then col = v
		elseif isentity(v) and IsValid(v) and v:IsPlayer() then src[#src + 1] = colTag(GOLD, esc(L.Name(v))) who = who or v
		elseif v ~= nil then src[#src + 1] = colTag(col, esc(tostring(v))) end
	end
	if #src > 0 then push(who and "local" or "system", who, table.concat(src), "whitesilence/game/tick.ogg") end
	return origAddText(...)
end

-- системные сообщения (вход/выход, смена ника и т.п.)
hook.Add("ChatText", "ws.chat", function(index, name, text, kind)
	if kind == "chat" then return end
	push("system", nil, colTag(GREY, esc(text)))
	return true
end)

-- ---------------------------------------------------------------- «печатает…»

local function setTyping(on)
	net.Start("ws.chat.typing")
	net.WriteBool(on)
	net.SendToServer()
end

hook.Add("PostDrawTranslucentRenderables", "ws.chat.typing", function(depth, sky)
	if depth or sky then return end
	local me = LocalPlayer()
	local eye = EyePos()
	for _, p in ipairs(player.GetAll()) do
		if p ~= me and p:Alive() and p:GetNW2Bool("ws_typing", false) and L.InGame(p) == L.InGame(me) then
			local pos = p:EyePos() + Vector(0, 0, 16)
			if pos:DistToSqr(eye) < 600 * 600 then
				local ang = EyeAngles()
				ang:RotateAroundAxis(ang:Up(), -90)
				ang:RotateAroundAxis(ang:Forward(), 90)
				cam.Start3D2D(pos, Angle(0, ang.y, ang.r), 0.08)
					local dots = string.rep(".", math.floor(RealTime() * 3) % 4)
					draw.RoundedBox(12, -110, -24, 220, 48, Color(8, 10, 14, 200))
					draw.SimpleText("печатает" .. dots, WS.Font("menusemi", 28), -78, 0, Color(236, 239, 244), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				cam.End3D2D()
			end
		end
	end
end)

-- ---------------------------------------------------------------- строка ввода

local function layout()
	local s = ScrH() / 1080
	return 26 * s, ScrH() - 450 * s, 620 * s, s    -- x, низ ленты, ширина, масштаб
end

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
	local me = LocalPlayer()
	if WS.Lobby.InGame(me) and not me:Alive() then return "Павшим… (живые не слышат)" end
	return mode == "squad" and "Отряду по рации…" or mode == "ooc" and "Всем на сервере…" or "Сказать рядом…  (/me — действие)"
end

function CH.Open(m)
	mode = m or "local"
	local x, bottom, w, s = layout()
	if not IsValid(box) then
		box = vgui.Create("EditablePanel")
		box.Paint = function(self, pw, ph)
			-- вкладки каналов над строкой
			local tx = 0
			for _, md in ipairs(CH.Modes) do
				local k = KIND[md]
				surface.SetFont(WS.Font("menusemi", 14))
				local tw = surface.GetTextSize(k[1]) + 22 * s
				local on = md == mode
				draw.RoundedBoxEx(4, tx, 0, tw, 24 * s, Color(on and k[2].r * 0.3 or 8, on and k[2].g * 0.3 or 10, on and k[2].b * 0.3 or 14, on and 230 or 170), true, true, false, false)
				draw.SimpleText(k[1], WS.Font("menusemi", 14), tx + tw / 2, 12 * s, on and k[2] or Color(140, 146, 156), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				tx = tx + tw + 4 * s
			end
			draw.SimpleText("Tab — канал · стрелки — история · Esc — закрыть", WS.Font("menulight", 13), pw, 12 * s, Color(120, 128, 140), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
		entry = vgui.Create("DTextEntry", box)
		entry:SetFont(WS.Font("menu", 19))
		entry:SetUpdateOnType(true)
		entry:SetDrawLanguageID(false)
		entry.AllowInput = function(self, ch)
			return utf8.len(self:GetValue() or "") >= CH.MaxLen          -- лимит по символам, а не байтам
		end
		entry.Paint = function(self, pw, ph)
			local k = KIND[mode] or KIND["local"]
			draw.RoundedBoxEx(5, 0, 0, pw, ph, Color(6, 8, 12, 235), false, true, true, true)
			surface.SetDrawColor(k[2].r, k[2].g, k[2].b, 200)
			surface.DrawRect(0, 0, 3 * s, ph)
			surface.SetDrawColor(255, 255, 255, 14)
			surface.DrawOutlinedRect(0, 0, pw, ph, 1)
			if (self:GetValue() or "") == "" then
				draw.SimpleText(placeholder(), WS.Font("menulight", 17), 16 * s, ph / 2, Color(130, 138, 150), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
			self:DrawTextEntryText(Color(240, 242, 246), Color(196, 38, 38, 160), Color(255, 255, 255))
			-- заполненность — тонкой полосой снизу
			local n = utf8.len(self:GetValue() or "") or 0
			local f = n / CH.MaxLen
			surface.SetDrawColor(f > 0.9 and 220 or k[2].r, f > 0.9 and 90 or k[2].g, f > 0.9 and 80 or k[2].b, 160)
			surface.DrawRect(3 * s, ph - 2 * s, (pw - 3 * s) * f, 2 * s)
			if n > CH.MaxLen * 0.7 then
				draw.SimpleText(n .. "/" .. CH.MaxLen, WS.Font("menulight", 13), pw - 8 * s, ph / 2, Color(150, 158, 170), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
			end
		end
		entry.OnEnter = send
		entry.OnKeyCodeTyped = function(self, code)
			if code == KEY_ESCAPE then
				CH.Close()
				gui.HideGameUI()
				return true
			elseif code == KEY_TAB then
				local i = (CH.ModeId[mode] % #CH.Modes) + 1
				mode = CH.Modes[i]
				surface.PlaySound("ui/buttonrollover.wav")
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
	box:SetSize(w, 66 * s)
	box:SetPos(x, bottom + 14 * s)
	entry:SetSize(w, 40 * s)
	entry:SetPos(0, 24 * s)
	entry:SetTextInset(16 * s, 0)
	box:SetVisible(true)
	box:MakePopup()
	entry:SetText("")
	entry:RequestFocus()
	scroll = 0
	setTyping(true)
end

function CH.Close()
	if IsValid(box) then
		box:SetVisible(false)
		box:KillFocus()
		setTyping(false)
	end
end

hook.Add("PlayerBindPress", "ws.chat", function(ply, bind, pressed)
	if not pressed then return end
	if bind == "messagemode" or bind:find("^messagemode$") then CH.Open("local") return true end
	if bind == "messagemode2" or bind:find("^messagemode2$") then CH.Open("squad") return true end
end)

-- ---------------------------------------------------------------- лента

local avatars = {}
local function avatar(i)
	local a = avatars[i]
	if not IsValid(a) then
		a = vgui.Create("AvatarImage")
		a:SetPaintedManually(true)
		a:SetMouseInputEnabled(false)
		avatars[i] = a
	end
	return a
end

local function parsed(line, width)
	if line.w ~= width then
		line.mk = markup.Parse("<font=" .. WS.Font("menu", 18) .. ">" .. line.src .. "</font>", width)
		line.w = width
	end
	return line.mk
end

hook.Add("HUDPaint", "ws.chat", function()
	local x, bottom, w, s = layout()
	local open = CH.IsOpen()
	if open then
		draw.RoundedBox(6, x - 8 * s, bottom - 262 * s, w + 16 * s, 270 * s, Color(4, 6, 9, 160))
	end
	local y = bottom
	local now = RealTime()
	local skipped, shown = 0, 0
	local av = 22 * s
	local textX = x + 12 * s + av + 8 * s
	local chipW = 72 * s
	local textW = w - (textX - x) - chipW - 46 * s
	for i = #lines, 1, -1 do
		local line = lines[i]
		local age = now - line.t
		local a = open and 1 or (1 - E.Smooth((age - 11) / 1.5))
		if a > 0 then
			if open and skipped < scroll then
				skipped = skipped + 1
			else
				local mk = parsed(line, textW)
				local h = math.max(mk:GetHeight(), av) + 10 * s
				y = y - h - 4 * s
				if y < bottom - 258 * s then break end
				local k = KIND[line.kind] or KIND.system
				local slide = (1 - E.OutCubic(age / 0.35)) * 24 * s
				local lx = x - slide
				a = a * E.Smooth(age / 0.2)
				-- карточка
				draw.RoundedBox(4, lx, y, w, h, Color(6, 8, 12, (open and 200 or 150) * a))
				surface.SetDrawColor(k[2].r, k[2].g, k[2].b, 220 * a)
				surface.DrawRect(lx, y, 3 * s, h)
				if age < 1.2 then
					surface.SetDrawColor(k[2].r, k[2].g, k[2].b, 40 * (1 - age / 1.2) * a)
					surface.DrawRect(lx, y, w, h)
				end
				-- аватар
				if IsValid(line.ply) and shown < 12 then
					shown = shown + 1
					local ai = avatar(shown)
					if ai.wsPly ~= line.ply then ai:SetPlayer(line.ply, 32) ai.wsPly = line.ply end
					ai:SetSize(av, av)
					ai:SetPos(lx + 12 * s, y + 5 * s)
					ai:SetAlpha(255 * a)
					ai:PaintManual()
				else
					surface.SetMaterial(UI.Mat("whitesilence/icons/" .. (line.kind == "system" and "alert" or "radio") .. ".png", "smooth"))
					surface.SetDrawColor(k[2].r, k[2].g, k[2].b, 200 * a)
					surface.DrawTexturedRect(lx + 12 * s, y + 5 * s, av, av)
				end
				mk:Draw(lx + (textX - x), y + 6 * s, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 255 * a)
				-- метка канала и время справа
				draw.RoundedBox(3, lx + w - chipW - 44 * s, y + 6 * s, chipW, 18 * s, Color(k[2].r * 0.25, k[2].g * 0.25, k[2].b * 0.25, 220 * a))
				draw.SimpleText(k[1], WS.Font("menusemi", 12), lx + w - chipW / 2 - 44 * s, y + 15 * s, Color(k[2].r, k[2].g, k[2].b, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				draw.SimpleText(line.time, WS.Font("menulight", 12), lx + w - 8 * s, y + 15 * s, Color(130, 138, 150, 220 * a), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
			end
		elseif not open then
			break
		end
	end
end)
