--[[
	Приложение телефона «NY Stock Exchange»: рынок (цены, мини-графики), карточка бумаги с графиком
	последних 60 минут, покупка/продажа (количество вводится на экране телефона), портфель с прибылью/убытком,
	лента новостей биржи. Управление как во всём телефоне: стрелки/Enter/Backspace или мышь (F2).
]]

NYRP.Stocks = NYRP.Stocks or {}
local ST = NYRP.Stocks
local UI = NYRP.UI

local function S(x) return UI.S(x) end

local GREEN = Color(64, 196, 104)
local RED = Color(232, 72, 64)
local BG = Color(8, 14, 24)
local ACCENT = Color(70, 200, 140)

ST.Data = ST.Data or nil

-- ------------------------------------------------------------- данные --
net.Receive("nyrp.stocks.data", function()
	local d = { prices = {}, got = RealTime() }
	for _ = 1, net.ReadUInt(8) do
		local id = net.ReadString()
		local p, tr = net.ReadFloat(), net.ReadFloat()
		local h = {}
		for i = 1, net.ReadUInt(8) do h[i] = net.ReadFloat() end
		d.prices[id] = { p = p, tr = tr, h = h }
	end
	d.pf = net.ReadTable()
	d.news = net.ReadTable()
	d.bank = net.ReadString()
	d.balance = net.ReadDouble()
	d.profit = net.ReadDouble()
	local msg = net.ReadString()
	ST.Data = d
	local P = NYRP.Phone
	if msg ~= "" and P then
		if P.Toast then P.Toast(msg) end
		surface.PlaySound("nyrp/phone/notify.wav")
	end
end)

function ST.Request()
	net.Start("nyrp.stocks.req")
	net.SendToServer()
end

local function trade(op, id, n)
	net.Start("nyrp.stocks.trade")
	net.WriteString(op)
	net.WriteString(id)
	net.WriteUInt(n, 32)
	net.SendToServer()
end

-- изменение за весь график (≈ час)
local function change(info)
	if not info or not info.h or #info.h == 0 then return 0, info and info.p or 0 end
	return info.p - info.h[1], info.h[1]
end

local function worth(d)
	local sum, cost = 0, 0
	for id, h in pairs(d and d.pf or {}) do
		local info = d.prices[id]
		if info then sum = sum + info.p * h.n cost = cost + (h.cost or 0) end
	end
	return sum, cost
end

-- ------------------------------------------------------------- график --
-- Линия с заливкой под ней; points — массив цен.
local function chart(points, x, y, w, h, col, thick)
	local n = #points
	if n < 2 then return end
	local lo, hi = math.huge, -math.huge
	for i = 1, n do lo = math.min(lo, points[i]) hi = math.max(hi, points[i]) end
	if hi - lo < 0.01 then hi = hi + 0.5 lo = lo - 0.5 end
	local pad = (hi - lo) * 0.08
	lo, hi = lo - pad, hi + pad
	local function px(i) return x + (i - 1) / (n - 1) * w end
	local function py(v) return y + h - (v - lo) / (hi - lo) * h end
	draw.NoTexture()
	surface.SetDrawColor(col.r, col.g, col.b, 34)
	for i = 1, n - 1 do
		local x1, x2 = px(i), px(i + 1)
		surface.DrawPoly({ { x = x1, y = py(points[i]) }, { x = x2, y = py(points[i + 1]) }, { x = x2, y = y + h }, { x = x1, y = y + h } })
	end
	surface.SetDrawColor(col)
	for i = 1, n - 1 do
		local x1, y1, x2, y2 = px(i), py(points[i]), px(i + 1), py(points[i + 1])
		for t = 0, (thick or 1) - 1 do surface.DrawLine(x1, y1 + t, x2, y2 + t) end
	end
	return lo, hi, px(n), py(points[n])
end

-- ---------------------------------------------------------- регистрация --
local function setup()
	local P = NYRP.Phone
	if not P or not P.Register or not P.BaseApps then return false end
	local C = P.Col

	local has = false
	for _, a in ipairs(P.BaseApps) do if a.id == "nyse" then has = true end end
	if not has then
		table.insert(P.BaseApps, { id = "nyse", name = "NY Stocks", icon = "coins", color = Color(20, 120, 80) })
	end

	-- общая шапка со счётом
	local function summary(x, y, w)
		local d = ST.Data
		local val, cost = worth(d)
		local pl = val - cost
		UI.RoundedRect(S(14), x + S(12), y, w - S(24), S(66), Color(20, 120, 80, 70))
		P.Text("Портфель", "medium", 11, x + S(24), y + S(9), C.dim)
		P.Text(d and ST.Price(val) or "…", "title", 20, x + S(24), y + S(24), color_white)
		local plCol = pl >= 0 and GREEN or RED
		P.Text((pl >= 0 and "+" or "") .. ST.Price(pl), "semibold", 11, x + S(24), y + S(48), plCol)
		local bank = d and NYRP.Bank and NYRP.Bank.Banks and NYRP.Bank.Banks[d.bank]
		P.Text(bank and bank.name or "Нет карты", "medium", 11, x + w - S(24), y + S(9), C.dim, TEXT_ALIGN_RIGHT)
		P.Text(d and (d.bank ~= "" and NYRP.Money.Format(d.balance) or "—") or "…", "bold", 15, x + w - S(24), y + S(26), color_white, TEXT_ALIGN_RIGHT)
		P.Text("на счёте", "regular", 10, x + w - S(24), y + S(46), C.faint, TEXT_ALIGN_RIGHT)
		return y + S(76)
	end

	local function tabs(st, x, y, w)
		st.tab = st.tab or 1
		local list = { "Рынок", "Портфель", "Новости" }
		local tw = (w - S(24)) / #list
		UI.RoundedRect(S(10), x + S(12), y, w - S(24), S(32), Color(255, 255, 255, 12))
		for i, t in ipairs(list) do
			local bx = x + S(12) + (i - 1) * tw
			local f = P.Btn("nyse.tab." .. i, bx, y, tw, S(32), function() st.tab = i st.scroll = 0 end)
			if st.tab == i then UI.RoundedRect(S(8), bx + S(3), y + S(3), tw - S(6), S(26), Color(255, 255, 255, 34)) end
			if f then UI.Outline(S(8), bx + S(3), y + S(3), tw - S(6), S(26), C.yellow, S(2)) end
			P.Text(t, "semibold", 12, bx + tw / 2, y + S(16), st.tab == i and color_white or C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		return y + S(42)
	end

	local function keepAlive(st)
		if RealTime() >= (st.nextReq or 0) then
			st.nextReq = RealTime() + 45
			ST.Request()
		end
	end

	local function loading(x, y, w)
		P.Icon("refresh", x + w / 2, y + S(60), S(34), C.faint)
		P.Text("Подключение к бирже…", "medium", 12, x + w / 2, y + S(96), C.faint, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	-- строка компании: тикер, название, мини-график, цена и изменение
	local function companyRow(c, info, rx, ry, rw, rh, f, extra)
		UI.RoundedRect(S(10), rx, ry, rw - S(6), rh, f and C.cardHi or C.card)
		if f then UI.Outline(S(10), rx, ry, rw - S(6), rh, UI.Alpha(C.yellow, 200), S(2)) end
		UI.RoundedRect(S(2), rx + S(6), ry + S(10), S(3), rh - S(20), c.color)
		P.Text(c.id, "bold", 14, rx + S(14), ry + S(9), color_white)
		P.Text(extra or c.sector, "regular", 10, rx + S(14), ry + S(29), C.dim)
		local diff, base = change(info)
		local col = diff >= 0 and GREEN or RED
		if info and #info.h > 1 then chart(info.h, rx + rw * 0.36, ry + S(10), rw * 0.25, rh - S(20), col, 1) end
		P.Text(info and ST.Price(info.p) or "…", "semibold", 13, rx + rw - S(16), ry + S(9), color_white, TEXT_ALIGN_RIGHT)
		local pct = info and ST.Pct(info.p, base) or ""
		surface.SetFont(NYRP.Font("bold", 10))
		local tw = surface.GetTextSize(pct) + S(10)
		UI.RoundedRect(S(4), rx + rw - S(16) - tw, ry + S(28), tw, S(16), UI.Alpha(col, 50))
		P.Text(pct, "bold", 10, rx + rw - S(16) - tw / 2, ry + S(36), col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	-- ------------------------------------------------------ главный экран --
	P.Register("nyse", {
		enter = function(st) st.nextReq = 0 end,
		draw = function(st, x, y, w, h)
			surface.SetDrawColor(BG)
			surface.DrawRect(x, y - S(28), w, h + S(28))
			keepAlive(st)
			local cy = P.Header("NY Stock Exchange", x, y, w, ACCENT)
			local d = ST.Data
			cy = summary(x, cy, w)
			cy = tabs(st, x, cy, w)
			if not d then loading(x, cy, w) return end
			local areaH = y + h - cy - S(14)
			if st.tab == 1 then
				P.List(st, "nyse.c.", #ST.Companies, x + S(12), cy, w - S(18), areaH, S(58), function(i, rx, ry, rw, rh, f)
					local c = ST.Companies[i]
					companyRow(c, d.prices[c.id], rx, ry, rw, rh, f)
				end, function(i)
					P.Push("nyse_stock", { id = ST.Companies[i].id, from = "nyse.c." .. i })
				end)
			elseif st.tab == 2 then
				local list = {}
				for _, c in ipairs(ST.Companies) do
					if d.pf[c.id] and d.pf[c.id].n > 0 then list[#list + 1] = c end
				end
				if #list == 0 then
					P.Icon("briefcase", x + w / 2, cy + S(70), S(44), C.faint)
					P.Text("Портфель пуст", "semibold", 14, x + w / 2, cy + S(112), C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					P.Text("Купите акции на вкладке «Рынок»", "regular", 11, x + w / 2, cy + S(132), C.faint, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					P.Text("Итог закрытых сделок: " .. ST.Price(d.profit or 0), "medium", 11, x + w / 2, cy + S(160), (d.profit or 0) >= 0 and GREEN or RED, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					return
				end
				P.Text("Закрытые сделки: " .. ((d.profit or 0) >= 0 and "+" or "") .. ST.Price(d.profit or 0), "medium", 11, x + S(18), cy - S(4), (d.profit or 0) >= 0 and GREEN or RED)
				cy = cy + S(16)
				P.List(st, "nyse.p.", #list, x + S(12), cy, w - S(18), y + h - cy - S(14), S(58), function(i, rx, ry, rw, rh, f)
					local c = list[i]
					local hold, info = d.pf[c.id], d.prices[c.id]
					local val = info and info.p * hold.n or 0
					local pl = val - (hold.cost or 0)
					UI.RoundedRect(S(10), rx, ry, rw - S(6), rh, f and C.cardHi or C.card)
					if f then UI.Outline(S(10), rx, ry, rw - S(6), rh, UI.Alpha(C.yellow, 200), S(2)) end
					UI.RoundedRect(S(2), rx + S(6), ry + S(10), S(3), rh - S(20), c.color)
					P.Text(c.id .. "  ×" .. hold.n, "bold", 14, rx + S(14), ry + S(9), color_white)
					P.Text("ср. " .. ST.Price((hold.cost or 0) / hold.n), "regular", 10, rx + S(14), ry + S(29), C.dim)
					P.Text(ST.Price(val), "semibold", 13, rx + rw - S(16), ry + S(9), color_white, TEXT_ALIGN_RIGHT)
					P.Text((pl >= 0 and "+" or "") .. ST.Price(pl) .. "  " .. ST.Pct(val, hold.cost or 0), "bold", 10, rx + rw - S(16), ry + S(30), pl >= 0 and GREEN or RED, TEXT_ALIGN_RIGHT)
				end, function(i)
					P.Push("nyse_stock", { id = list[i].id, from = "nyse.p." .. i })
				end)
			else
				local news = d.news or {}
				if #news == 0 then
					P.Icon("message", x + w / 2, cy + S(70), S(40), C.faint)
					P.Text("Новостей пока нет", "medium", 13, x + w / 2, cy + S(110), C.faint, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					return
				end
				local font = NYRP.Font("medium", 12)
				P.List(st, "nyse.n.", #news, x + S(12), cy, w - S(18), areaH, S(74), function(i, rx, ry, rw, rh, f)
					local n = news[i]
					UI.RoundedRect(S(10), rx, ry, rw - S(6), rh, f and C.cardHi or C.card)
					local col = n.up and GREEN or RED
					P.Icon(n.up and "p_up" or "p_down", rx + S(18), ry + S(18), S(14), col)
					P.Text((n.id or "") .. " · " .. (n.t or ""), "bold", 11, rx + S(32), ry + S(11), col)
					local lines = UI.Wrap(n.text or "", font, rw - S(30))
					for k = 1, math.min(3, #lines) do
						P.Text(lines[k], "medium", 12, rx + S(12), ry + S(28) + (k - 1) * S(14), color_white)
					end
				end, function(i)
					local n = news[i]
					if n and ST.ById[n.id or ""] then P.Push("nyse_stock", { id = n.id, from = "nyse.n." .. i }) end
				end)
			end
		end,
	})

	-- ------------------------------------------------------ карточка бумаги --
	local function ask(st, op)
		local d = ST.Data
		local info = d and d.prices[st.id]
		if not info then return end
		local title = (op == "buy" and "Купить " or "Продать ") .. st.id .. " · " .. ST.Price(info.p) .. " (комиссия 1%)"
		P.Ask(title, "", { numeric = true, max = 6, hint = "Количество акций" }, function(v)
			local n = tonumber(P.Digits(v))
			if not n or n < 1 then return end
			trade(op, st.id, math.floor(n))
		end)
	end

	P.Register("nyse_stock", {
		enter = function(st) st.nextReq = 0 end,
		draw = function(st, x, y, w, h)
			surface.SetDrawColor(BG)
			surface.DrawRect(x, y - S(28), w, h + S(28))
			keepAlive(st)
			local c = ST.ById[st.id]
			local cy = P.Header(c.id, x, y, w, c.color)
			local d = ST.Data
			local info = d and d.prices[c.id]
			P.Text(c.name, "semibold", 13, x + S(18), cy - S(4), color_white)
			P.Text(c.sector, "regular", 11, x + S(18), cy + S(13), C.dim)
			cy = cy + S(34)
			if not info then loading(x, cy, w) return end
			local diff, base = change(info)
			local col = diff >= 0 and GREEN or RED
			P.Text(ST.Price(info.p), "title", 30, x + S(18), cy, color_white)
			P.Text((diff >= 0 and "+" or "") .. ST.Price(diff) .. "  (" .. ST.Pct(info.p, base) .. ") за час", "semibold", 11, x + S(18), cy + S(36), col)
			cy = cy + S(58)
			-- график
			local gx, gy, gw, gh = x + S(12), cy, w - S(24), S(150)
			UI.RoundedRect(S(10), gx, gy, gw, gh, Color(255, 255, 255, 8))
			surface.SetDrawColor(255, 255, 255, 10)
			for i = 1, 3 do surface.DrawRect(gx + S(6), gy + gh * i / 4, gw - S(12), 1) end
			local lo, hi, lx, ly = chart(info.h, gx + S(8), gy + S(10), gw - S(16), gh - S(20), col, 2)
			if lo then
				local pulse = (math.sin(RealTime() * 4) + 1) / 2
				UI.Circle(lx, ly, S(4) + pulse * S(3), UI.Alpha(col, 60))
				UI.Circle(lx, ly, S(3), col)
				P.Text(ST.Price(hi), "regular", 9, gx + S(8), gy + S(4), C.faint)
				P.Text(ST.Price(lo), "regular", 9, gx + S(8), gy + gh - S(4), C.faint, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
			end
			P.Text("60 мин", "regular", 9, gx + gw - S(8), gy + gh - S(4), C.faint, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
			cy = cy + gh + S(10)
			-- позиция
			local hold = d.pf[c.id]
			UI.RoundedRect(S(10), x + S(12), cy, w - S(24), S(52), C.card)
			if hold and hold.n > 0 then
				local val = info.p * hold.n
				local pl = val - (hold.cost or 0)
				P.Text("У вас " .. hold.n .. " шт. · ср. " .. ST.Price((hold.cost or 0) / hold.n), "semibold", 12, x + S(22), cy + S(8), color_white)
				P.Text("Стоимость " .. ST.Price(val), "regular", 11, x + S(22), cy + S(28), C.dim)
				P.Text((pl >= 0 and "+" or "") .. ST.Price(pl), "bold", 12, x + w - S(22), cy + S(28), pl >= 0 and GREEN or RED, TEXT_ALIGN_RIGHT)
			else
				P.Text("У вас нет акций " .. c.id, "semibold", 12, x + S(22), cy + S(8), C.dim)
				P.Text("Деньги спишутся со счёта карты", "regular", 11, x + S(22), cy + S(28), C.faint)
			end
			cy = cy + S(62)
			local bw = (w - S(24) - S(8)) / 2
			P.Pill("nyse.buy", x + S(12), cy, bw, S(44), "Купить", function() ask(st, "buy") end, { solid = true, color = GREEN, icon = "plus" })
			P.Pill("nyse.sell", x + S(12) + bw + S(8), cy, bw, S(44), "Продать", function()
				if not (hold and hold.n > 0) then P.Toast("Нечего продавать") return end
				ask(st, "sell")
			end, { solid = true, color = RED, icon = "minus" })
			cy = cy + S(52)
			if hold and hold.n > 0 then
				P.Pill("nyse.sellall", x + S(12), cy, w - S(24), S(36), "Продать всё (" .. hold.n .. ") ≈ " .. NYRP.Money.Format(ST.SellGain(info.p, hold.n)), function()
					trade("sell", c.id, hold.n)
				end, { size = 12 })
				cy = cy + S(44)
			end
			P.Text("Комиссия брокера 1% · цена меняется раз в минуту", "regular", 10, x + w / 2, math.min(cy + S(4), y + h - S(18)), C.faint, TEXT_ALIGN_CENTER)
		end,
	})
	return true
end

if not setup() then
	timer.Simple(0, function() setup() end)
end
