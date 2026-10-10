--[[
	Биржа на сервере: движение цен раз в минуту, новости-события, сделки со счёта банковской карты,
	сохранение цен (data/nyrp/stocks.json) и портфелей (c.flags.stocks).
	Данные получают только те, у кого открыто приложение (подписка обновляется запросом клиента).
]]

NYRP.Stocks = NYRP.Stocks or {}
local ST = NYRP.Stocks

ST.State = ST.State or {}   -- [тикер] = { p = цена, h = {история}, tr = тренд }
ST.News = ST.News or {}     -- { {text, t = "ЧЧ:ММ", id, up} }, новые сверху
local FILE = "nyrp/stocks.json"

-- ------------------------------------------------------------- события --
-- {текст, изменение цены (доля), сдвиг тренда}
local EVENTS = {
	up = {
		{ "%s отчиталась о рекордной квартальной прибыли", 0.09, 0.004 },
		{ "%s заключила крупный контракт с мэрией Нью-Йорка", 0.07, 0.003 },
		{ "Аналитики Уолл-стрит повысили прогноз по акциям %s", 0.05, 0.002 },
		{ "%s объявила о выкупе собственных акций", 0.06, 0.002 },
		{ "%s выходит на рынок Нью-Джерси", 0.045, 0.003 },
		{ "Инвесторы скупают бумаги %s после слухов о слиянии", 0.11, 0.0 },
	},
	down = {
		{ "%s: прибыль за квартал оказалась ниже ожиданий", -0.08, -0.003 },
		{ "Налоговая инспекция начала проверку в офисе %s", -0.07, -0.004 },
		{ "Профсоюз объявил забастовку на предприятиях %s", -0.06, -0.003 },
		{ "Директор %s неожиданно ушёл в отставку", -0.09, -0.002 },
		{ "%s отзывает партию продукции — акции падают", -0.05, -0.002 },
		{ "Скандал в совете директоров %s", -0.1, 0.0 },
	},
}

-- ------------------------------------------------------------ сохранение --
function ST.Save()
	file.CreateDir("nyrp")
	file.Write(FILE, util.TableToJSON({ state = ST.State, news = ST.News }))
end

local function fresh(c)
	local p = c.base * (0.9 + math.random() * 0.2)
	local h = {}
	-- стартовая история, чтобы график не был пустым
	local x = p
	for i = ST.History, 1, -1 do
		x = x * math.exp((math.random() - 0.5) * c.vol * 2)
		h[i] = math.Round(x, 2)
	end
	h[#h] = math.Round(p, 2)
	return { p = math.Round(p, 2), h = h, tr = 0 }
end

function ST.Load()
	local raw = file.Exists(FILE, "DATA") and util.JSONToTable(file.Read(FILE, "DATA") or "") or nil
	ST.State = {}
	for _, c in ipairs(ST.Companies) do
		local s = raw and raw.state and raw.state[c.id]
		if s and tonumber(s.p) and istable(s.h) and #s.h > 0 then
			ST.State[c.id] = { p = tonumber(s.p), h = s.h, tr = tonumber(s.tr) or 0 }
		else
			ST.State[c.id] = fresh(c)
		end
	end
	ST.News = raw and istable(raw.news) and raw.news or {}
end
ST.Load()

-- ---------------------------------------------------------------- рынок --
local function gauss()
	local u1, u2 = math.max(math.random(), 1e-6), math.random()
	return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end

local function push(s, p)
	s.p = math.Round(math.max(0.5, p), 2)
	s.h[#s.h + 1] = s.p
	while #s.h > ST.History do table.remove(s.h, 1) end
end

-- новость двигает цену и тренд; попадает в ленту приложения и в газету
function ST.Event(id, change, text, trendShift)
	local c, s = ST.ById[id], ST.State[id]
	if not c or not s then return end
	s.p = math.max(0.5, s.p * (1 + change))
	s.tr = math.Clamp((s.tr or 0) + (trendShift or 0), -0.01, 0.01)
	table.insert(ST.News, 1, { text = text, t = NYRP.Time and NYRP.Time.Format and NYRP.Time.Format() or os.date("%H:%M"), id = id, up = change >= 0 })
	while #ST.News > 12 do table.remove(ST.News) end
	if NYRP.Street and NYRP.Street.AddNews then
		NYRP.Street.AddNews("Биржа: " .. text .. " (" .. id .. " " .. (change >= 0 and "+" or "") .. math.Round(change * 100, 1) .. "%)")
	end
end

local function randomEvent()
	local c = ST.Companies[math.random(#ST.Companies)]
	local up = math.random() < 0.5
	local list = up and EVENTS.up or EVENTS.down
	local e = list[math.random(#list)]
	local mag = e[2] * (0.7 + math.random() * 0.6)
	ST.Event(c.id, mag, string.format(e[1], c.name), e[3])
end

function ST.Step()
	for _, c in ipairs(ST.Companies) do
		local s = ST.State[c.id]
		-- тренд медленно «плывёт» и затухает
		s.tr = math.Clamp((s.tr or 0) * 0.93 + gauss() * 0.0012, -0.01, 0.01)
		-- возврат к справедливой цене (чтобы бумаги не улетали в бесконечность)
		local pull = (math.log(c.base) - math.log(s.p)) * 0.015
		local ret = s.tr + pull + gauss() * c.vol
		push(s, s.p * math.exp(ret))
	end
	if math.random() < 0.14 then
		randomEvent()
		-- событие сразу в последнюю точку графика
		for _, c in ipairs(ST.Companies) do
			local s = ST.State[c.id]
			s.h[#s.h] = math.Round(s.p, 2)
		end
	end
	ST.Save()
	ST.Broadcast()
end

timer.Create("nyrp.stocks.tick", ST.Tick, 0, function() ST.Step() end)

-- ------------------------------------------------------------- портфель --
local function portfolio(ply)
	local c = ply.nyrpChar
	if not c then return {} end
	c.flags = c.flags or {}
	c.flags.stocks = c.flags.stocks or {}
	return c.flags.stocks
end
ST.Portfolio = portfolio

-- Стоимость портфеля по текущим ценам
function ST.Worth(ply)
	local sum = 0
	for id, h in pairs(portfolio(ply)) do
		local s = ST.State[id]
		if s then sum = sum + s.p * (h.n or 0) end
	end
	return sum
end

-- ------------------------------------------------------------ отправка --
local function send(ply, msg)
	if not NYRP.HasCharacter(ply) then return end
	local card = NYRP.Bank and NYRP.Bank.FindCard and NYRP.Bank.FindCard(ply)
	local bank = card and card.data.bank or ""
	net.Start("nyrp.stocks.data")
	net.WriteUInt(#ST.Companies, 8)
	for _, c in ipairs(ST.Companies) do
		local s = ST.State[c.id]
		net.WriteString(c.id)
		net.WriteFloat(s.p)
		net.WriteFloat(s.tr or 0)
		net.WriteUInt(#s.h, 8)
		for i = 1, #s.h do net.WriteFloat(s.h[i]) end
	end
	local pf = {}
	for id, h in pairs(portfolio(ply)) do
		if (h.n or 0) > 0 then pf[id] = { n = h.n, cost = h.cost or 0 } end
	end
	net.WriteTable(pf)
	net.WriteTable(ST.News)
	net.WriteString(bank)
	net.WriteDouble(bank ~= "" and NYRP.Bank.Balance(ply, bank) or 0)
	net.WriteDouble((ply.nyrpChar.flags.stocksProfit or 0))
	net.WriteString(msg or "")
	net.Send(ply)
end
ST.Send = send

function ST.Broadcast()
	for _, p in ipairs(player.GetAll()) do
		if (p.nyrpStocksSub or 0) > CurTime() then send(p) end
	end
end

net.Receive("nyrp.stocks.req", function(_, ply)
	if (ply.nyrpStocksReq or 0) > CurTime() then return end
	ply.nyrpStocksReq = CurTime() + 1
	ply.nyrpStocksSub = CurTime() + 150
	send(ply)
end)

-- ------------------------------------------------------------------ сделки --
net.Receive("nyrp.stocks.trade", function(_, ply)
	if (ply.nyrpStocksTrade or 0) > CurTime() then return end
	ply.nyrpStocksTrade = CurTime() + 0.7
	local op, id, n = net.ReadString(), net.ReadString(), net.ReadUInt(32)
	if not NYRP.HasCharacter(ply) or not ply:Alive() then return end
	local c, s = ST.ById[id], ST.State[id]
	if not c or not s or n < 1 or n > ST.MaxShares then return end
	-- торговать можно только с телефона с SIM-картой
	if NYRP.Phone and NYRP.Phone.Number and not NYRP.Phone.Number(ply) then
		NYRP.Notify(ply, "Нужен телефон с SIM-картой", "error")
		return
	end
	local B = NYRP.Bank
	local card = B and B.FindCard(ply)
	if not card then send(ply, "Нужна банковская карта в сумке") return end
	local bank = card.data.bank
	local pf = portfolio(ply)
	local h = pf[id] or { n = 0, cost = 0 }
	local ch = ply.nyrpChar
	if op == "buy" then
		if h.n + n > ST.MaxShares then send(ply, "Слишком большой пакет") return end
		local cost = ST.BuyCost(s.p, n)
		if not B.Add(ply, bank, -cost, "NYSE: покупка " .. n .. " " .. id) then
			send(ply, "Недостаточно средств: нужно " .. NYRP.Money.Format(cost))
			return
		end
		h.n = h.n + n
		h.cost = (h.cost or 0) + cost
		pf[id] = h
		NYRP.Chars.Save(ply)
		ply:EmitSound("nyrp/fx/cash.wav", 45)
		hook.Run("NYRP.StockTrade", ply, "buy", id, n, cost, 0)
		send(ply, "Куплено " .. n .. " " .. id .. " за " .. NYRP.Money.Format(cost))
	elseif op == "sell" then
		if h.n < n then send(ply, "У вас только " .. h.n .. " акций " .. id) return end
		local gain = ST.SellGain(s.p, n)
		local basis = (h.cost or 0) * n / h.n
		local profit = gain - basis
		B.Add(ply, bank, gain, "NYSE: продажа " .. n .. " " .. id)
		h.n = h.n - n
		h.cost = math.max(0, (h.cost or 0) - basis)
		if h.n <= 0 then pf[id] = nil else pf[id] = h end
		ch.flags.stocksProfit = (ch.flags.stocksProfit or 0) + profit
		NYRP.Chars.Save(ply)
		ply:EmitSound("nyrp/fx/cash.wav", 45)
		hook.Run("NYRP.StockTrade", ply, "sell", id, n, gain, profit)
		send(ply, "Продано " .. n .. " " .. id .. ": " .. (profit >= 0 and "прибыль " or "убыток ") .. NYRP.Money.Format(math.abs(profit)))
	end
end)

-- ------------------------------------------------------------- админ --
local function cmd(name, fn)
	if NYRP.Chat and NYRP.Chat.AddCommand then NYRP.Chat.AddCommand(name, fn) return end
	timer.Simple(0, function() NYRP.Chat.AddCommand(name, fn) end)
end

-- /stocknews LBTY +8 Текст новости
cmd("/stocknews", function(ply, raw)
	if not ply:IsAdmin() then return end
	local id, pct, text = string.match(raw, "^%S+%s+(%S+)%s+([%+%-]?[%d%.]+)%s*(.*)$")
	id = id and string.upper(id)
	if not id or not ST.ById[id] or not tonumber(pct) then
		NYRP.Notify(ply, "Формат: /stocknews <тикер> <+/-процент> [текст]", "warning", 6)
		return
	end
	local change = math.Clamp(tonumber(pct) / 100, -0.5, 1)
	if text == "" then text = ST.ById[id].name .. (change >= 0 and ": акции резко выросли" or ": акции резко упали") end
	ST.Event(id, change, text, change * 0.03)
	local s = ST.State[id]
	s.h[#s.h] = math.Round(s.p, 2)
	ST.Save()
	ST.Broadcast()
	NYRP.Notify(ply, "Новость выпущена: " .. id .. " " .. ST.Price(s.p), "success")
end)

cmd("/stockreset", function(ply)
	if not ply:IsSuperAdmin() then return end
	for _, c in ipairs(ST.Companies) do ST.State[c.id] = fresh(c) end
	ST.News = {}
	ST.Save()
	ST.Broadcast()
	NYRP.Notify(ply, "Цены на бирже сброшены", "success")
end)
