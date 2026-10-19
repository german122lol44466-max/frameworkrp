--[[
	Чат — общая часть. Режимы:
	  local  — «Рядом»: слышно в радиусе ChatRange (в меню — своему отряду);
	  squad  — «Отряд»: по рации своему отряду, где бы ни были;
	  ooc    — «Всем»: всем на сервере (вне игры);
	  me     — действие «/me …» рядом;
	  phrase — голосовая фраза (G) рядом;
  dead   — павший в бою: видят только павшие и те, кто в меню.
	Команды в тексте: /me, /r (отряд), // или /ooc (всем).
]]

WS.Chat = WS.Chat or {}
local CH = WS.Chat

CH.Modes = { "local", "squad", "ooc" }          -- что можно выбрать в строке ввода (Tab — переключить)
CH.ModeId = { ["local"] = 1, squad = 2, ooc = 3, me = 4, phrase = 5, dead = 6 }
CH.ModeName = { "local", "squad", "ooc", "me", "phrase", "dead" }
CH.Label = { ["local"] = "Рядом", squad = "Отряд", ooc = "Всем" }
CH.MaxLen = 200

-- Убрать управляющие и «невидимые» символы, обрезать до MaxLen символов
function CH.Clean(s)
	if not isstring(s) then return "" end
	local out, n = {}, 0
	for _, c in utf8.codes(s) do
		if c >= 32 and not (c >= 0x7F and c < 0xA0) and c ~= 0x200B and c ~= 0x200E and c ~= 0x200F and c ~= 0xFEFF
			and not (c >= 0x202A and c <= 0x202E) then
			n = n + 1
			if n > CH.MaxLen then break end
			out[#out + 1] = utf8.char(c)
		end
	end
	return string.Trim(table.concat(out))
end

-- Разобрать команду в начале строки: возвращает режим и текст без команды
function CH.Parse(mode, text)
	local low = string.lower(text)
	if string.StartWith(low, "/me ") then return "me", string.sub(text, 5) end
	if string.StartWith(low, "/r ") then return "squad", string.sub(text, 4) end
	if string.StartWith(low, "/ooc ") then return "ooc", string.sub(text, 6) end
	if string.StartWith(text, "//") then return "ooc", string.sub(text, 3) end
	return mode, text
end
