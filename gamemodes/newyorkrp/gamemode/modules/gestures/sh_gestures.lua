--[[
	Жесты: круговое меню на G (modules/gestures/cl_gestures.lua) и случайные «микро»-жесты,
	когда персонаж говорит в чат. Анимации — жесты верхней части тела стандартных моделей игроков.
	Список ниже — временный: его можно дополнять (id, название, иконка, ACT_*).
]]

NYRP.Gestures = NYRP.Gestures or {}
local G = NYRP.Gestures

G.List = {
	{ id = "wave", name = "Помахать", icon = "g_wave", act = ACT_GMOD_GESTURE_WAVE },
	{ id = "agree", name = "Кивнуть", icon = "g_agree", act = ACT_GMOD_GESTURE_AGREE },
	{ id = "disagree", name = "Покачать головой", icon = "g_disagree", act = ACT_GMOD_GESTURE_DISAGREE },
	{ id = "beckon", name = "Подозвать", icon = "g_beckon", act = ACT_GMOD_GESTURE_BECON },
	{ id = "halt", name = "Стоп", icon = "g_halt", act = ACT_SIGNAL_HALT },
	{ id = "forward", name = "Вперёд", icon = "g_forward", act = ACT_SIGNAL_FORWARD },
	{ id = "salute", name = "Отдать честь", icon = "g_salute", act = ACT_GMOD_TAUNT_SALUTE },
	{ id = "bow", name = "Поклон", icon = "g_bow", act = ACT_GMOD_GESTURE_BOW },
	{ id = "laugh", name = "Смеяться", icon = "g_laugh", act = ACT_GMOD_TAUNT_LAUGH },
	{ id = "cheer", name = "Радоваться", icon = "g_cheer", act = ACT_GMOD_TAUNT_CHEER },
	{ id = "give", name = "Протянуть руку", icon = "g_give", act = ACT_GMOD_GESTURE_ITEM_GIVE },
	{ id = "dance", name = "Танцевать", icon = "g_dance", act = ACT_GMOD_TAUNT_DANCE },
}
G.ById = {}
for i, g in ipairs(G.List) do g.index = i G.ById[g.id] = g end

-- Микро-жесты при сообщениях в чат: по словам, иначе случайный с шансом.
G.ChatChance = 0.4
G.ChatWords = {
	{ { "привет", "здаров", "здравствуй", "хай", "пока", "до встречи", "бывай" }, ACT_GMOD_GESTURE_WAVE },
	{ { "нет", "неа", "никогда", "отказываюсь" }, ACT_GMOD_GESTURE_DISAGREE },
	{ { "да", "ага", "угу", "конечно", "ок", "хорошо", "согласен", "точно" }, ACT_GMOD_GESTURE_AGREE },
	{ { "иди сюда", "сюда", "подойди", "за мной" }, ACT_GMOD_GESTURE_BECON },
	{ { "стой", "стоп", "подожди", "тихо" }, ACT_SIGNAL_HALT },
	{ { "держи", "возьми", "бери" }, ACT_GMOD_GESTURE_ITEM_GIVE },
}
G.ChatRandom = { ACT_GMOD_GESTURE_AGREE, ACT_GMOD_GESTURE_BECON, ACT_GMOD_GESTURE_ITEM_GIVE, ACT_GMOD_GESTURE_DISAGREE }

-- string.lower не трогает кириллицу — переводим сами.
local RU = { ["А"] = "а", ["Б"] = "б", ["В"] = "в", ["Г"] = "г", ["Д"] = "д", ["Е"] = "е", ["Ё"] = "ё", ["Ж"] = "ж", ["З"] = "з", ["И"] = "и", ["Й"] = "й", ["К"] = "к", ["Л"] = "л", ["М"] = "м", ["Н"] = "н", ["О"] = "о", ["П"] = "п", ["Р"] = "р", ["С"] = "с", ["Т"] = "т", ["У"] = "у", ["Ф"] = "ф", ["Х"] = "х", ["Ц"] = "ц", ["Ч"] = "ч", ["Ш"] = "ш", ["Щ"] = "щ", ["Ъ"] = "ъ", ["Ы"] = "ы", ["Ь"] = "ь", ["Э"] = "э", ["Ю"] = "ю", ["Я"] = "я" }
local function lowerRu(s)
	return (string.gsub(string.lower(s), "[\208\209][\128-\191]", function(c) return RU[c] or c end))
end

function G.ForText(text)
	local low = lowerRu(text)
	local words = {}
	for w in string.gmatch(low, "[^%s%p]+") do words[w] = true end
	for _, row in ipairs(G.ChatWords) do
		for _, w in ipairs(row[1]) do
			-- фраза из нескольких слов — поиском, одно слово — целиком (чтобы «да» не находилось в «когда»)
			if (string.find(w, " ", 1, true) and string.find(low, w, 1, true)) or words[w] then return row[2], true end
		end
	end
	return G.ChatRandom[math.random(#G.ChatRandom)], false
end
