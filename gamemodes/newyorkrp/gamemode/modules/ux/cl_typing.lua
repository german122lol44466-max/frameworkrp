--[[
	Индикатор набора над головой: «Говорит / Шепчет / Кричит / Действие / OOC» и три прыгающие точки.
	Сервер присылает вид сообщения только тем, кто в радиусе слышимости (sv_ux). Рисуется внутри
	общей «стопки» над головой (modules/chat/cl_overhead.lua вызывает O.TypingKind и O.DrawTyping).
]]

NYRP.UX = NYRP.UX or {}
local UX = NYRP.UX
NYRP.Overhead = NYRP.Overhead or {}
local O = NYRP.Overhead
local UI = NYRP.UI

UX.Typing = UX.Typing or {}   -- [ply] = вид сообщения

net.Receive("nyrp.ux.typing", function()
	local ply, kind = net.ReadEntity(), net.ReadUInt(4)
	if not IsValid(ply) then return end
	UX.Typing[ply] = kind > 0 and kind or nil
end)

hook.Add("EntityRemoved", "nyrp.ux.typing", function(ent) UX.Typing[ent] = nil end)

function O.TypingKind(ply)
	if not ply:Alive() then return 0 end
	return UX.Typing[ply] or 0
end

local INFO
local function info(kind)
	if not INFO then
		local T = NYRP.Chat.Types
		INFO = {
			[T.IC] = { "Говорит", "message", UI.Col.accent },
			[T.WHISPER] = { "Шепчет", "ear", Color(170, 185, 215) },
			[T.YELL] = { "Кричит", "speaker", UI.Col.orange },
			[T.ME] = { "Действие", "hand", Color(196, 160, 255) },
			[T.IT] = { "Описывает", "eye", Color(196, 160, 255) },
			[T.OOC] = { "OOC", "world", Color(120, 190, 255) },
			[T.LOOC] = { "LOOC", "users", Color(120, 190, 255) },
		}
	end
	return INFO[kind] or INFO[NYRP.Chat.Types.IC]
end

-- Таблетка «Говорит • • •» (в координатах 3D2D над головой). Низ — y, возвращает высоту.
function O.DrawTyping(y, kind, a, now)
	local inf = info(kind)
	local font = NYRP.FontRaw and NYRP.FontRaw("medium", 26) or NYRP.Font("medium", 26)
	surface.SetFont(font)
	local tw, th = surface.GetTextSize(inf[1])
	local isz = th * 0.95
	local dotsW = 46
	local padX = 16
	local w = padX * 2 + isz + 10 + tw + 12 + dotsW
	local h = th + 14
	-- появление: таблетка «вырастает» из точки и поднимается
	local e = UI.Ease(a)
	local sw = w * (0.6 + 0.4 * e)
	local x = -sw / 2
	local by = y + (1 - e) * 10
	UI.RoundedRect(h / 2, x, by - h, sw, h, Color(8, 10, 16, 205 * a))
	UI.Outline(h / 2, x, by - h, sw, h, Color(inf[3].r, inf[3].g, inf[3].b, 60 * a), 2)
	local cx = x + padX + (sw - w) / 2
	UI.DrawIcon(inf[2], cx + isz / 2, by - h / 2, isz, Color(inf[3].r, inf[3].g, inf[3].b, 255 * a))
	cx = cx + isz + 10
	draw.SimpleText(inf[1], font, cx, by - h / 2, Color(214, 217, 226, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	cx = cx + tw + 14
	-- три точки прыгают волной
	for i = 0, 2 do
		local ph = (now * 2.4 - i * 0.22) % 1
		local jump = ph < 0.5 and math.sin(ph * 2 * math.pi) or 0
		local r = 5 + jump * 1.2
		UI.Circle(cx + i * 15 + 5, by - h / 2 - jump * 7, r, Color(230, 232, 240, (150 + 105 * jump) * a))
	end
	return h
end
