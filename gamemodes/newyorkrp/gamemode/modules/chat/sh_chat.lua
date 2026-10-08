--[[
	Типы сообщений и разбор префиксов (одинаково на клиенте и сервере).
]]

NYRP.Chat = NYRP.Chat or {}
local Chat = NYRP.Chat

Chat.Types = { IC = 1, WHISPER = 2, YELL = 3, OOC = 4, LOOC = 5, ME = 6, SYSTEM = 7, IT = 8, JOIN = 9, LEAVE = 10 }

local prefixes = {
	{ "//", Chat.Types.OOC }, { "/ooc ", Chat.Types.OOC }, { "/оос ", Chat.Types.OOC },
	{ ".//", Chat.Types.LOOC }, { "/looc ", Chat.Types.LOOC }, { "[[", Chat.Types.LOOC },
	{ "/w ", Chat.Types.WHISPER }, { "/ш ", Chat.Types.WHISPER },
	{ "/y ", Chat.Types.YELL }, { "/к ", Chat.Types.YELL },
	{ "/me ", Chat.Types.ME }, { "/я ", Chat.Types.ME },
	{ "/it ", Chat.Types.IT }, { "/IT ", Chat.Types.IT },
	{ "/W ", Chat.Types.WHISPER }, { "/Ш ", Chat.Types.WHISPER }, { "/Y ", Chat.Types.YELL }, { "/К ", Chat.Types.YELL },
	{ "/OOC ", Chat.Types.OOC }, { "/LOOC ", Chat.Types.LOOC }, { "/ME ", Chat.Types.ME },
}
-- длинные префиксы проверяем раньше (.// раньше //)
table.sort(prefixes, function(a, b) return #a[1] > #b[1] end)

-- Возвращает тип и текст без префикса.
function Chat.Parse(text)
	for _, p in ipairs(prefixes) do
		if string.sub(text, 1, #p[1]) == p[1] then
			return p[2], string.Trim(string.sub(text, #p[1] + 1))
		end
	end
	return Chat.Types.IC, text
end

function Chat.Range(kind)
	local R = NYRP.Config.Ranges
	if kind == Chat.Types.WHISPER then return R.Whisper end
	if kind == Chat.Types.YELL then return R.Yell end
	if kind == Chat.Types.LOOC then return R.LOOC end
	if kind == Chat.Types.OOC then return math.huge end
	return R.Say
end
