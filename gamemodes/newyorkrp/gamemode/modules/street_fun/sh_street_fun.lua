--[[
	Уличные развлечения (своё, не путать с modules/street — уличными объектами):
	  Граффити — «Баллончик с краской» (6 цветов) в руке: ЛКМ по стене — нанести тег, R — выбрать рисунок.
	    Стереть — «Губка» (ЛКМ, 5 с) или руками (E по рисунку, 10 с); уборщикам улиц — $10 за каждый.
	    Сохраняются для карты: data/nyrp/graffiti_<карта>.json (не больше 60, старые пропадают).
	  Кости и карты — /roll [макс], /coin, /dice; колода карт (предмет): ПКМ «Вытянуть карту».
	    Результат видят все рядом: в чате (как /me) и над головой 5 секунд.
	  Шляпа для чаевых — предмет: ПКМ «Поставить»; прохожие кладут деньги (E), владелец забирает (E).
	Админ: /graffitiwipe — стереть все граффити на карте, /graffitiremove — стереть тот, на который смотрите.
]]

NYRP.StreetFun = NYRP.StreetFun or {}
local SF = NYRP.StreetFun

if SERVER then
	for _, n in ipairs({ "nyrp.graf.full", "nyrp.graf.add", "nyrp.graf.del", "nyrp.graf.req", "nyrp.graf.spray",
		"nyrp.fun.show", "nyrp.tip.open", "nyrp.tip.give" }) do
		util.AddNetworkString(n)
	end
end

SF.MaxGraffiti = 60
SF.SprayTime = 3
SF.EraseSponge = 5
SF.EraseHands = 10
SF.CleanerPay = 10

-- цвета баллончиков (id предмета: spraycan_<цвет>)
SF.Colors = {
	red = { name = "Красный", col = Color(222, 46, 52) },
	blue = { name = "Синий", col = Color(40, 110, 230) },
	green = { name = "Зелёный", col = Color(52, 190, 80) },
	yellow = { name = "Жёлтый", col = Color(250, 206, 30) },
	white = { name = "Белый", col = Color(242, 242, 242) },
	pink = { name = "Розовый", col = Color(240, 80, 180) },
}

function SF.ColorOf(itemId)
	local c = itemId and string.match(itemId, "^spraycan_(%a+)$")
	return c and SF.Colors[c] and c or nil
end

-- рисунки: текст + оформление (рисуются на клиенте, cl_graffiti.lua)
SF.Tags = {
	{ text = "NYC", deco = "crown", font = "a" },
	{ text = "BRONX", deco = "drips", font = "a" },
	{ text = "718", deco = "bubble", font = "a" },
	{ text = "KINGS", deco = "crown", font = "b" },
	{ text = "HARLEM", deco = "arrow", font = "a" },
	{ text = "QUEENS", deco = "stars", font = "b" },
	{ text = "NO COPS", deco = "cross", font = "a" },
	{ text = "LOVE NY", deco = "heart", font = "b" },
	{ text = "212", deco = "bubble", font = "b" },
	{ text = "STREET", deco = "arrow", font = "b" },
	{ text = "ВОЛЯ", deco = "drips", font = "b" },
	{ text = "SMILE", deco = "smile", font = "a" },
}

-- ------------------------------------------------------------ карты --
SF.Suits = { { "♠", false }, { "♥", true }, { "♦", true }, { "♣", false } }
SF.SuitNames = { "пик", "червей", "бубен", "треф" }
SF.Ranks = { "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A" }
SF.RankNames = { "Двойка", "Тройка", "Четвёрка", "Пятёрка", "Шестёрка", "Семёрка", "Восьмёрка", "Девятка", "Десятка",
	"Валет", "Дама", "Король", "Туз" }

-- карта 1..52 -> ранг (1..13), масть (1..4)
function SF.CardParts(n)
	n = math.Clamp(math.floor(n), 1, 52) - 1
	return n % 13 + 1, math.floor(n / 13) + 1
end

function SF.CardName(n)
	local r, s = SF.CardParts(n)
	return SF.RankNames[r] .. " " .. SF.SuitNames[s] .. " " .. SF.Suits[s][1]
end
