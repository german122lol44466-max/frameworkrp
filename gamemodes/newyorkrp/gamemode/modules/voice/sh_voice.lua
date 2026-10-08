--[[
	Режимы голосового чата: шёпот / обычный голос / крик — разная дальность.
	Меняется в круговом меню G (по центру), после смены 5 секунд виден радиус слышимости.
]]

NYRP.Voice = NYRP.Voice or {}
local V = NYRP.Voice

V.Modes = {
	{ id = "whisper", name = "Шёпот", icon = "v_whisper", range = 140, col = Color(150, 190, 235) },
	{ id = "normal", name = "Обычный голос", icon = "v_normal", range = 650, col = Color(236, 237, 242) },
	{ id = "yell", name = "Крик", icon = "v_yell", range = 1300, col = Color(255, 150, 60) },
}

function V.ModeOf(ply) return V.Modes[ply:GetNW2Int("nyrp.voiceMode", 2)] or V.Modes[2] end
function V.Range(ply) return V.ModeOf(ply).range end
