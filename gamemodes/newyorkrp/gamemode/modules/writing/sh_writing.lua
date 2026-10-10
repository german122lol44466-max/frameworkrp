--[[
	Записки и письма.
	  • «Блокнот» (10 листов): ПКМ → «Написать записку» — бумажное окно, до 1000 символов, заголовок, подпись
	    (своё имя, свой текст или без подписи). Получается предмет «Записка» с текстом, автором и датой.
	  • «Записка» / «Письмо»: ПКМ → «Прочитать», «Передать» (человеку перед вами), бросить — как любой предмет.
	  • «Конверт с маркой»: ПКМ → «Написать письмо» рядом с почтовыми ящиками или синим ящиком USPS —
	    выбрать квартиру-адресата; письмо приходит в её почтовый ящик через минуту. Жильцы квартиры получают
	    уведомление и забирают письмо у любой стены почтовых ящиков (кнопка «Письма» в окне ящика).
	Очередь писем — data/nyrp/letters_<карта>.json. Предметы — framework/items/writing/.
]]

NYRP.Writing = NYRP.Writing or {}
local W = NYRP.Writing

W.MaxText = 1000
W.MaxTitle = 40
W.MaxSign = 40
W.Pages = 10
W.DeliveryDelay = 60          -- через сколько секунд письмо оказывается в ящике
W.LetterLife = 7 * 24 * 3600  -- непрочитанные письма хранятся неделю (реального времени)
W.MaxPerHome = 20
W.PostRange = 170             -- насколько близко к ящику нужно стоять

W.PostClasses = { nyrp_mailbox = true, nyrp_street_usps = true }

if SERVER then
	for _, n in ipairs({ "nyrp.writing.write", "nyrp.writing.give", "nyrp.writing.addr",
		"nyrp.writing.send", "nyrp.writing.box", "nyrp.writing.take" }) do
		util.AddNetworkString(n)
	end
end

-- Очистка текста: переносы строк сохраняем (не больше 2 подряд), остальные управляющие символы — убираем.
function W.Clean(s, maxLen, multiline)
	s = tostring(s or "")
	s = string.gsub(s, "\r", "")
	if multiline then
		s = string.gsub(s, "[\1-\9\11-\31]", " ")
		s = string.gsub(s, "\n\n\n+", "\n\n")
	else
		s = string.gsub(s, "[%c]", " ")
	end
	s = string.Trim(s)
	local len = utf8.len(s)
	if not len then
		-- битый UTF-8: отрезаем всё после первой ошибки
		local _, bad = utf8.len(s)
		s = string.sub(s, 1, (bad or 1) - 1)
		len = utf8.len(s) or 0
	end
	if maxLen and len > maxLen then s = string.sub(s, 1, utf8.offset(s, maxLen + 1) - 1) end
	return s
end

-- Рядом с почтовыми ящиками?
function W.NearPost(ply)
	local pos = ply:GetPos()
	for cls in pairs(W.PostClasses) do
		for _, e in ipairs(ents.FindByClass(cls)) do
			if e:GetPos():DistToSqr(pos) <= W.PostRange * W.PostRange then return e end
		end
	end
end
