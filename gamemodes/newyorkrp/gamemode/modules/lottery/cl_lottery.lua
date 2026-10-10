--[[
	Лотерея на клиенте: меню автомата (скретч-карта / NY Lotto) и окно стирания скретч-карты.
	Защитный слой — маска из мелких ячеек: зажмите ЛКМ и водите мышью. Когда стёрто больше половины —
	слой осыпается сам, сервер зачисляет выигрыш.
]]

NYRP.Lottery = NYRP.Lottery or {}
local L = NYRP.Lottery
local UI = NYRP.UI

local GOLD = Color(247, 198, 0)

local function timeLeft(sec)
	sec = math.max(0, math.floor(sec))
	local h, m = math.floor(sec / 3600), math.floor(sec % 3600 / 60)
	if h > 0 then return h .. " ч " .. m .. " мин" end
	if m > 0 then return m .. " мин " .. (sec % 60) .. " с" end
	return sec .. " с"
end

local function buy(kind)
	net.Start("nyrp.lottery.buy")
	net.WriteString(kind)
	net.SendToServer()
end

-- ------------------------------------------------------------ меню автомата --
net.Receive("nyrp.lottery.menu", function()
	local ent = net.ReadEntity()
	local info = {
		jackpot = net.ReadUInt(32), left = net.ReadUInt(32), sold = net.ReadUInt(16),
		mine = net.ReadTable(), last = net.ReadTable(), got = RealTime(),
	}
	L.Info = info
	if IsValid(L.Menu) then return end   -- окно уже открыто — обновится само
	L.OpenMenu(ent)
end)

function L.OpenMenu(ent)
	local win, body = UI.Window("Лотерея NY LOTTO", "coins", 640, 460, { sub = "Наличные · только для взрослых 18+" })
	L.Menu = win
	local cw = (body:GetWide() - UI.S(16)) / 2
	local function card(x, title, sub, icon, accent, paint)
		local p = vgui.Create("DPanel", body)
		p:SetPos(x, 0)
		p:SetSize(cw, body:GetTall() - UI.S(46))
		p.Paint = function(s, w, h)
			UI.RoundedRect(UI.S(12), 0, 0, w, h, Color(255, 255, 255, 8))
			UI.RoundedRect(UI.S(12), 0, 0, w, UI.S(96), UI.Alpha(accent, 34))
			UI.Glow(UI.S(50), UI.S(48), UI.S(140), UI.S(140), UI.Alpha(accent, 40))
			UI.DrawIcon(icon, UI.S(48), UI.S(48), UI.S(40), accent)
			draw.SimpleText(title, NYRP.Font("title", 22), UI.S(84), UI.S(36), color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText(sub, NYRP.Font("regular", 13), UI.S(84), UI.S(62), UI.Col.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			paint(w, h)
		end
		return p
	end
	-- моментальная лотерея
	local sc = card(0, "Liberty Luck", "моментальная лотерея", "sun", Color(255, 170, 60), function(w, h)
		local y = UI.S(116)
		draw.SimpleText("Сотрите защитный слой —", NYRP.Font("medium", 14), UI.S(16), y, UI.Col.text)
		draw.SimpleText("три одинаковых символа выигрывают:", NYRP.Font("medium", 14), UI.S(16), y + UI.S(18), UI.Col.text)
		y = y + UI.S(48)
		for _, s in ipairs(L.Symbols) do
			if s.prize > 0 then
				UI.DrawIcon(s.icon, UI.S(28), y + UI.S(9), UI.S(18), s.color)
				draw.SimpleText("× 3", NYRP.Font("semibold", 13), UI.S(44), y + UI.S(9), UI.Col.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				draw.SimpleText(NYRP.Money.Format(s.prize), NYRP.Font("bold", 15), w - UI.S(18), y + UI.S(9), s.prize >= 1000 and GOLD or color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
				y = y + UI.S(24)
			end
		end
	end)
	local b1 = UI.AddButton(sc, "Купить карту — " .. NYRP.Money.Format(L.ScratchPrice), "plus", function() buy("scratch") end,
		{ dock = false, style = "solid", accent = Color(255, 170, 60), h = 44 })
	b1:SetPos(UI.S(14), sc:GetTall() - UI.S(58))
	b1:SetWide(cw - UI.S(28))
	-- NY Lotto
	local lt = card(cw + UI.S(16), "NY Lotto", "розыгрыш раз в 2 часа", "coins", GOLD, function(w, h)
		local i = L.Info or {}
		local y = UI.S(112)
		draw.SimpleText("ДЖЕКПОТ", NYRP.Font("bold", 12), UI.S(16), y, UI.Col.dim)
		draw.SimpleText(NYRP.Money.Format(i.jackpot or 0), NYRP.Font("title", 38), UI.S(16), y + UI.S(14), GOLD)
		y = y + UI.S(64)
		local left = (i.left or 0) - (RealTime() - (i.got or RealTime()))
		draw.SimpleText("До розыгрыша: " .. timeLeft(left), NYRP.Font("medium", 14), UI.S(16), y, UI.Col.text)
		draw.SimpleText("Билетов в тираже: " .. (i.sold or 0), NYRP.Font("regular", 13), UI.S(16), y + UI.S(20), UI.Col.dim)
		y = y + UI.S(48)
		local mine = i.mine or {}
		draw.SimpleText("Ваши билеты (" .. #mine .. "):", NYRP.Font("semibold", 13), UI.S(16), y, UI.Col.text)
		local line = table.concat(mine, "  ", 1, math.min(#mine, 6)) .. (#mine > 6 and "  …" or "")
		draw.SimpleText(#mine > 0 and line or "нет", NYRP.Font("medium", 13), UI.S(16), y + UI.S(18), #mine > 0 and GOLD or UI.Col.faint)
	end)
	local b2 = UI.AddButton(lt, "Билет NY Lotto — " .. NYRP.Money.Format(L.LottoPrice), "certificate", function() buy("lotto") end,
		{ dock = false, style = "solid", accent = GOLD, h = 44 })
	b2:SetPos(UI.S(14), lt:GetTall() - UI.S(58))
	b2:SetWide(cw - UI.S(28))
	-- последний победитель
	local foot = vgui.Create("DPanel", body)
	foot:SetPos(0, body:GetTall() - UI.S(36))
	foot:SetSize(body:GetWide(), UI.S(36))
	foot.Paint = function(_, w, h)
		local last = L.Info and L.Info.last
		local text = last and last.name and ("Прошлый тираж: " .. last.name .. " выиграл(а) " .. NYRP.Money.Format(last.amount or 0) .. " (билет №" .. (last.num or "?") .. ")")
			or "Выигрыш NY Lotto зачисляется на банковскую карту победителя (или наличными)."
		UI.DrawIcon("info", UI.S(10), h / 2, UI.S(16), UI.Col.dim)
		draw.SimpleText(text, NYRP.Font("regular", 13), UI.S(26), h / 2, UI.Col.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	-- закрыть, если отошли от автомата
	win.Think = function(s)
		if gui.IsGameUIVisible() and not s.Closing then gui.HideGameUI() s:Close() end
		if not s.Closing and (not IsValid(ent) or ent:GetPos():Distance(LocalPlayer():GetPos()) > 180) then s:Close() end
	end
end

-- ----------------------------------------------------------- стирание слоя --
local scrape
local function scrapeSound(on)
	if on then
		if not scrape then
			scrape = CreateSound(LocalPlayer(), "physics/cardboard/cardboard_box_scrape_rough_loop1.wav")
			scrape:PlayEx(0.35, 140)
		end
	elseif scrape then
		scrape:Stop()
		scrape = nil
	end
end

net.Receive("nyrp.lottery.scratch", function()
	local ser = net.ReadString()
	local syms = net.ReadTable()
	local prize = net.ReadUInt(16)
	if NYRP.Inventory and NYRP.Inventory.IsOpen and NYRP.Inventory.IsOpen() and NYRP.Inventory.Close then NYRP.Inventory.Close() end
	L.OpenScratch(ser, syms, prize)
end)

function L.OpenScratch(ser, syms, prize)
	scrapeSound(false)
	if IsValid(L.ScratchWin) then L.ScratchWin:Remove() end
	local win, body = UI.Window("Скретч-карта Liberty Luck", "sun", 560, 500, { sub = "Зажмите ЛКМ и сотрите слой", onClose = function() scrapeSound(false) end })
	L.ScratchWin = win
	local bw, bh = body:GetWide(), body:GetTall()
	local card = vgui.Create("DPanel", body)
	card:SetPos(0, 0)
	card:SetSize(bw, bh - UI.S(56))
	local cw, ch = card:GetWide(), card:GetTall()
	-- поле символов (3 × 2) и маска над ним
	local fx, fy = UI.S(20), UI.S(64)
	local fw, fh = cw - UI.S(40), ch - UI.S(84)
	local g = math.max(4, UI.S(9))
	local gw, gh = math.ceil(fw / g), math.ceil(fh / g)
	local mask, total, cleared = {}, gw * gh, 0
	local done, doneT, lastX, lastY = false, nil, nil, nil
	local winSym
	local cnt = {}
	for _, id in ipairs(syms) do cnt[id] = (cnt[id] or 0) + 1 if cnt[id] >= 3 and prize > 0 then winSym = id end end

	local function finish()
		if done then return end
		done, doneT = true, RealTime()
		scrapeSound(false)
		net.Start("nyrp.lottery.claim")
		net.WriteString(ser)
		net.SendToServer()
		surface.PlaySound(prize > 0 and "nyrp/phone/game_record.wav" or "nyrp/ui/notify.wav")
	end

	local function scratchAt(px, py)
		local r = UI.S(20)
		local cx0, cx1 = math.floor((px - fx - r) / g), math.floor((px - fx + r) / g)
		local cy0, cy1 = math.floor((py - fy - r) / g), math.floor((py - fy + r) / g)
		for gx = math.max(0, cx0), math.min(gw - 1, cx1) do
			for gy = math.max(0, cy0), math.min(gh - 1, cy1) do
				local k = gy * gw + gx
				if not mask[k] then
					local dx, dy = fx + gx * g + g / 2 - px, fy + gy * g + g / 2 - py
					if dx * dx + dy * dy <= r * r then
						mask[k] = true
						cleared = cleared + 1
					end
				end
			end
		end
	end

	card.Think = function(s)
		if done then return end
		local down = input.IsMouseDown(MOUSE_LEFT) and s:IsHovered()
		if down then
			local mx, my = s:CursorPos()
			if lastX then
				-- сплошная полоса между кадрами
				local dist = math.sqrt((mx - lastX) ^ 2 + (my - lastY) ^ 2)
				local steps = math.max(1, math.ceil(dist / (g * 1.5)))
				for i = 1, steps do scratchAt(Lerp(i / steps, lastX, mx), Lerp(i / steps, lastY, my)) end
			else
				scratchAt(mx, my)
			end
			scrapeSound(lastX ~= nil and (math.abs(mx - lastX) + math.abs(my - lastY)) > 0.5)
			lastX, lastY = mx, my
			if cleared / total >= 0.55 then finish() end
		else
			lastX, lastY = nil, nil
			scrapeSound(false)
		end
	end
	card:SetCursor("hand")

	card.Paint = function(s, w, h)
		-- сама карта
		UI.RoundedRect(UI.S(14), 0, 0, w, h, Color(24, 40, 92))
		UI.Glow(w / 2, 0, w * 1.2, UI.S(180), Color(80, 140, 255, 50))
		draw.SimpleText("LIBERTY LUCK", NYRP.Font("title", 28), UI.S(20), UI.S(30), GOLD, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText("№ " .. ser, NYRP.Font("medium", 12), w - UI.S(20), UI.S(30), Color(200, 210, 240), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		-- символы
		UI.RoundedRect(UI.S(10), fx, fy, fw, fh, Color(245, 240, 225))
		local colW, rowH = fw / 3, fh / 2
		for i, id in ipairs(syms) do
			local sd = L.SymbolById[id]
			local c, r = (i - 1) % 3, math.floor((i - 1) / 3)
			local cx, cy = fx + colW * c + colW / 2, fy + rowH * r + rowH / 2
			local hl = done and winSym == id
			if hl then
				local p = (math.sin(RealTime() * 6) + 1) / 2
				UI.RoundedRect(UI.S(10), fx + colW * c + UI.S(6), fy + rowH * r + UI.S(6), colW - UI.S(12), rowH - UI.S(12), UI.Alpha(GOLD, 90 + 80 * p))
			end
			if sd then
				UI.DrawIcon(sd.icon, cx, cy - UI.S(10), UI.S(52), sd.color)
				draw.SimpleText(sd.prize > 0 and NYRP.Money.Format(sd.prize) or sd.name, NYRP.Font("bold", 14), cx, cy + UI.S(32), Color(60, 60, 80), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		end
		-- защитный слой: несколько прямоугольников на строку (слитые пробеги нестёртых ячеек)
		local fade = doneT and math.Clamp(1 - (RealTime() - doneT) / 0.5, 0, 1) or 1
		if fade > 0 then
			for gy = 0, gh - 1 do
				local run = nil
				local yy = fy + gy * g
				local hh = math.min(g, fy + fh - yy)
				local shade = 168 + ((gy % 4 < 2) and 10 or 0)
				for gx = 0, gw do
					local covered = gx < gw and not mask[gy * gw + gx]
					if covered and not run then run = gx end
					if not covered and run then
						local xx = fx + run * g
						local ww = math.min((gx - run) * g, fx + fw - xx)
						surface.SetDrawColor(shade, shade + 4, shade + 12, 255 * fade)
						surface.DrawRect(xx, yy, ww, hh)
						run = nil
					end
				end
			end
			if cleared == 0 then
				draw.SimpleText("СОТРИТЕ ЗДЕСЬ", NYRP.Font("title", 34), fx + fw / 2, fy + fh / 2 - UI.S(10), Color(120, 124, 140, 255 * fade), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				UI.DrawIcon("hand", fx + fw / 2, fy + fh / 2 + UI.S(32), UI.S(28), Color(120, 124, 140, 255 * fade))
			end
		end
		-- итог
		if done then
			local a = math.Clamp((RealTime() - doneT - 0.3) / 0.3, 0, 1)
			if a > 0 then
				local tw = UI.S(360)
				UI.RoundedRect(UI.S(12), w / 2 - tw / 2, fy + fh / 2 - UI.S(36), tw, UI.S(72), Color(10, 12, 22, 225 * a))
				local col = prize > 0 and GOLD or Color(200, 200, 215)
				draw.SimpleText(prize > 0 and ("ВЫИГРЫШ " .. NYRP.Money.Format(prize) .. "!") or "БЕЗ ВЫИГРЫША", NYRP.Font("title", 32),
					w / 2, fy + fh / 2 - UI.S(8), UI.Alpha(col, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				draw.SimpleText(prize > 0 and "Деньги зачислены наличными" or "Удачи в следующий раз", NYRP.Font("regular", 13),
					w / 2, fy + fh / 2 + UI.S(20), UI.Alpha(UI.Col.dim, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		end
		-- прогресс стирания
		local frac = math.min(1, cleared / total / 0.55)
		UI.RoundedRect(UI.S(2), fx, h - UI.S(12), fw, UI.S(4), Color(255, 255, 255, 20))
		UI.RoundedRect(UI.S(2), fx, h - UI.S(12), fw * frac, UI.S(4), GOLD)
	end

	local row = vgui.Create("DPanel", body)
	row:SetPos(0, bh - UI.S(44))
	row:SetSize(bw, UI.S(44))
	row.Paint = nil
	local all = UI.AddButton(row, "Стереть всё", "hand", function()
		if done then return end
		for k = 0, total - 1 do mask[k] = true end
		cleared = total
		finish()
	end, { dock = LEFT, style = "ghost", h = 44 })
	all:SetWide(UI.S(200))
	local close = UI.AddButton(row, "Закрыть", "close", function() win:Close() end, { dock = RIGHT, style = "solid", h = 44 })
	close:SetWide(UI.S(160))
end
