--[[
	Биржа «NY Stock Exchange» (общая часть): вымышленные компании Нью-Йорка, комиссия, форматирование цен.
	Цена каждой бумаги меняется раз в минуту: случайное блуждание с трендом + новости-события (попадают в газету).
	Торговля — в приложении телефона «NY Stock Exchange» (предустановлено), деньги — со счёта банковской карты.
	Сохранение: цены и история — data/nyrp/stocks.json, портфель — c.flags.stocks = { [тикер] = { n, cost } }.
	Админ: /stocknews <тикер> <+/-процент> [текст] — выпустить новость вручную, /stockreset — сбросить цены.
]]

NYRP.Stocks = NYRP.Stocks or {}
local ST = NYRP.Stocks

ST.Fee = 0.01          -- комиссия брокера 1% от суммы сделки
ST.Tick = 60           -- секунд между изменениями цены
ST.History = 60        -- сколько точек графика храним
ST.MaxShares = 100000  -- предел бумаг одной компании у одного персонажа

-- base — «справедливая» цена (к ней цена медленно тянется), vol — волатильность за минуту
ST.Companies = {
	{ id = "LBTY", name = "Liberty Steel Works", sector = "Металлургия", base = 42, vol = 0.010, color = Color(90, 140, 220) },
	{ id = "HDSN", name = "Hudson River Shipping", sector = "Грузоперевозки", base = 27, vol = 0.012, color = Color(40, 170, 150) },
	{ id = "BKLN", name = "Brooklyn Brewing Co.", sector = "Напитки", base = 18, vol = 0.014, color = Color(230, 150, 50) },
	{ id = "QNST", name = "Queens Tech Systems", sector = "Технологии", base = 115, vol = 0.022, color = Color(150, 100, 240) },
	{ id = "EMPR", name = "Empire Realty Group", sector = "Недвижимость", base = 76, vol = 0.009, color = Color(200, 170, 90) },
	{ id = "YCAB", name = "Yellow Cab Holdings", sector = "Такси", base = 12, vol = 0.018, color = Color(247, 198, 0) },
	{ id = "BRDW", name = "Broadway Entertainment", sector = "Шоу-бизнес", base = 34, vol = 0.016, color = Color(232, 72, 100) },
	{ id = "MTRO", name = "Metro Transit Corp", sector = "Транспорт", base = 23, vol = 0.008, color = Color(70, 180, 90) },
	{ id = "WLST", name = "Wall Street Capital", sector = "Финансы", base = 158, vol = 0.013, color = Color(64, 196, 104) },
	{ id = "FBEN", name = "Five Boroughs Energy", sector = "Энергетика", base = 55, vol = 0.011, color = Color(255, 120, 60) },
}
ST.ById = {}
for i, c in ipairs(ST.Companies) do c.idx = i ST.ById[c.id] = c end

if SERVER then
	util.AddNetworkString("nyrp.stocks.data")   -- сервер -> клиент: цены, история, портфель, новости
	util.AddNetworkString("nyrp.stocks.req")    -- клиент -> сервер: «приложение открыто, пришли данные»
	util.AddNetworkString("nyrp.stocks.trade")  -- клиент -> сервер: купить/продать
end

-- $1 234.56
function ST.Price(n)
	n = tonumber(n) or 0
	local neg = n < 0
	n = math.abs(n)
	local whole = math.floor(n)
	local cents = math.floor((n - whole) * 100 + 0.5)
	if cents >= 100 then whole, cents = whole + 1, cents - 100 end
	local s = tostring(whole):reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (neg and "-$" or "$") .. string.Trim(s) .. "." .. string.format("%02d", cents)
end

-- +1.25%
function ST.Pct(a, b)
	if not b or b == 0 then return "0.00%" end
	local p = (a - b) / b * 100
	return (p >= 0 and "+" or "") .. string.format("%.2f", p) .. "%"
end

-- Итог сделки в целых долларах (как списывается со счёта): покупка — с комиссией вверх, продажа — за вычетом вниз.
function ST.BuyCost(price, n) return math.ceil(price * n * (1 + ST.Fee)) end
function ST.SellGain(price, n) return math.floor(price * n * (1 - ST.Fee)) end
