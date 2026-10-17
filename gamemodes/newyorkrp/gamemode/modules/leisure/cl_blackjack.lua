--[[
	Блэкджек на клиенте: окно стола — сукно, карты дилера и ваши (рисуются вручную: рубашка,
	ранг, масть), анимация раздачи из «башмака», звуки. Кнопки: ставка (фишки $5/$25/$100/$500),
	«Ещё», «Хватит», «Удвоить», «Встать». Закрыли окно — место за вами, E по столу — вернуться.
]]

NYRP.Leisure = NYRP.Leisure or {}
local LS = NYRP.Leisure
LS.BJ = LS.BJ or {}
local BJ = LS.BJ
local UI = NYRP.UI

local GOLD = Color(247, 198, 0)
local RED = Color(200, 30, 40)
local INK = Color(24, 24, 30)
local DEAL_GAP = 0.22    -- задержка между картами при раздаче
local FLY = 0.28         -- время полёта карты

-- ---------------------------------------------------------- рисование карт --
local function poly(pts)
	-- рисуем в обоих направлениях обхода: одно из них всегда видно
	surface.DrawPoly(pts)
	local rev = {}
	for i = #pts, 1, -1 do rev[#rev + 1] = pts[i] end
	surface.DrawPoly(rev)
end

local function drawSuit(suit, cx, cy, s, col)
	draw.NoTexture()
	surface.SetDrawColor(col)
	if suit == 3 then          -- бубны
		poly({ { x = cx, y = cy - s }, { x = cx + s * 0.72, y = cy }, { x = cx, y = cy + s }, { x = cx - s * 0.72, y = cy } })
	elseif suit == 2 then      -- черви
		UI.Circle(cx - s * 0.47, cy - s * 0.3, s * 0.52, col)
		UI.Circle(cx + s * 0.47, cy - s * 0.3, s * 0.52, col)
		draw.NoTexture()
		surface.SetDrawColor(col)
		poly({ { x = cx - s * 0.98, y = cy - s * 0.15 }, { x = cx + s * 0.98, y = cy - s * 0.15 }, { x = cx, y = cy + s * 0.95 } })
	elseif suit == 1 then      -- пики
		UI.Circle(cx - s * 0.45, cy + s * 0.22, s * 0.48, col)
		UI.Circle(cx + s * 0.45, cy + s * 0.22, s * 0.48, col)
		draw.NoTexture()
		surface.SetDrawColor(col)
		poly({ { x = cx, y = cy - s * 0.95 }, { x = cx + s * 0.92, y = cy + s * 0.12 }, { x = cx - s * 0.92, y = cy + s * 0.12 } })
		poly({ { x = cx, y = cy + s * 0.25 }, { x = cx + s * 0.32, y = cy + s * 0.95 }, { x = cx - s * 0.32, y = cy + s * 0.95 } })
	else                       -- трефы
		UI.Circle(cx, cy - s * 0.42, s * 0.42, col)
		UI.Circle(cx - s * 0.48, cy + s * 0.12, s * 0.42, col)
		UI.Circle(cx + s * 0.48, cy + s * 0.12, s * 0.42, col)
		draw.NoTexture()
		surface.SetDrawColor(col)
		poly({ { x = cx, y = cy }, { x = cx + s * 0.3, y = cy + s * 0.95 }, { x = cx - s * 0.3, y = cy + s * 0.95 } })
	end
end
BJ.DrawSuit = drawSuit

-- карта: card 0 — рубашкой вверх
function BJ.DrawCard(x, y, w, h, card, alpha)
	alpha = alpha or 255
	local r = math.max(4, w * 0.08)
	UI.RoundedRect(r, x + UI.S(3), y + UI.S(4), w, h, Color(0, 0, 0, 90 * alpha / 255))
	if not card or card <= 0 then
		UI.RoundedRect(r, x, y, w, h, Color(250, 250, 250, alpha))
		UI.RoundedRect(r * 0.7, x + w * 0.07, y + w * 0.07, w * 0.86, h - w * 0.14, Color(150, 26, 40, alpha))
		surface.SetDrawColor(255, 255, 255, 40 * alpha / 255)
		for i = 1, 6 do
			local yy = y + h * i / 7
			surface.DrawRect(x + w * 0.12, yy, w * 0.76, 2)
		end
		drawSuit(1, x + w / 2, y + h / 2, w * 0.16, Color(255, 255, 255, 110 * alpha / 255))
		return
	end
	local rank, suit = BJ.Parts(card)
	local col = BJ.SuitRed[suit] and Color(RED.r, RED.g, RED.b, alpha) or Color(INK.r, INK.g, INK.b, alpha)
	UI.RoundedRect(r, x, y, w, h, Color(252, 252, 248, alpha))
	UI.Outline(r, x, y, w, h, Color(0, 0, 0, 40 * alpha / 255), 1)
	local rk = BJ.Ranks[rank] or "?"
	local f = w >= UI.S(80) and NYRP.Font("title", 28) or NYRP.Font("title", 18)
	draw.SimpleText(rk, f, x + w * 0.1, y + h * 0.03, col)
	drawSuit(suit, x + w * 0.19, y + h * 0.33, w * 0.08, col)
	draw.SimpleText(rk, f, x + w * 0.9, y + h * 0.97, col, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
	drawSuit(suit, x + w / 2, y + h * 0.55, w * 0.2, col)
end

-- ------------------------------------------------------------------ состояние --
BJ.State = BJ.State or nil
BJ.Anim = BJ.Anim or { player = {}, dealer = {} }

local function cardSound()
	surface.PlaySound("physics/cardboard/cardboard_box_impact_soft1.wav")
end

-- новые карты получают время «вылета» по очереди (игрок, дилер, игрок, дилер…)
local function updateAnim(old, st)
	local now = RealTime()
	local newHand = not old or old.hand ~= st.hand
	if newHand then BJ.Anim = { player = {}, dealer = {} } end
	local A = BJ.Anim
	local q = 0
	local last = now
	for _, a in pairs(A.player) do last = math.max(last, a.t) end
	for _, a in pairs(A.dealer) do last = math.max(last, a.t) end
	local base = math.max(now, last - DEAL_GAP + 0.05)
	local function touch(list, i, card)
		local a = list[i]
		if not a then
			list[i] = { card = card, t = base + q * DEAL_GAP }
			q = q + 1
		elseif a.card ~= card then
			-- открыли скрытую карту дилера — переворот
			list[i] = { card = card, t = base + q * DEAL_GAP, flip = true, prev = a.card }
			q = q + 1
		end
	end
	local n = math.max(#st.player, 2)
	for i = 1, n do
		if st.player[i] then touch(A.player, i, st.player[i]) end
		if i <= 2 and st.dealer[i] then touch(A.dealer, i, st.dealer[i]) end
	end
	for i = 3, #st.dealer do touch(A.dealer, i, st.dealer[i]) end
	for i = #st.player + 1, 32 do A.player[i] = nil end
	for i = #st.dealer + 1, 32 do A.dealer[i] = nil end
	BJ.AnimEnd = base + math.max(q - 1, 0) * DEAL_GAP + FLY
end

local function animating()
	return (BJ.AnimEnd or 0) > RealTime()
end

-- сумма только по уже прилетевшим картам
local function landedValue(list)
	local cards = {}
	for i = 1, #list do
		local a = list[i]
		if a and a.t + FLY <= RealTime() then cards[#cards + 1] = a.card end
	end
	return BJ.Value(cards), #cards
end

local function act(name, amount)
	net.Start("nyrp.bj.act")
	net.WriteString(name)
	net.WriteUInt(math.Clamp(math.floor(tonumber(amount) or 0), 0, 65535), 16)
	net.SendToServer()
end

-- ------------------------------------------------------------------ окно --
local RESULT = {
	win = { "ВЫИГРЫШ", Color(104, 220, 120) },
	bj = { "БЛЭКДЖЕК!", GOLD },
	push = { "НИЧЬЯ", Color(200, 205, 220) },
	lose = { "ПРОИГРЫШ", Color(230, 80, 70) },
	bust = { "ПЕРЕБОР", Color(230, 80, 70) },
}

local function buildControls(win)
	local ctl = win.Controls
	if not IsValid(ctl) then return end
	ctl:Clear()
	local st = BJ.State
	if not st then return end
	local h = 46
	local leave = UI.AddButton(ctl, "Встать", "door_exit", function() act("leave") end, { dock = RIGHT, style = "ghost", h = h, accent = UI.Col.red })
	leave:SetWide(UI.S(130))
	leave:DockMargin(UI.S(8), 0, 0, 0)
	if st.phase == "play" then
		local function add(text, icon, name, accent, enabled)
			local b = UI.AddButton(ctl, text, icon, function()
				if animating() then return end
				act(name)
			end, { dock = LEFT, style = "solid", h = h, accent = accent })
			b:SetWide(UI.S(170))
			b:DockMargin(0, 0, UI.S(10), 0)
			if enabled == false then b:SetEnabled(false) end
			return b
		end
		add("Ещё", "plus", "hit", GOLD)
		add("Хватит", "hand", "stand", Color(96, 164, 232))
		local canDouble = #st.player == 2 and NYRP.Money.Get(LocalPlayer()) >= st.bet
		add("Удвоить", "coins", "double", Color(104, 200, 120), canDouble)
		return
	end
	-- ставка
	local entry = vgui.Create("NYRP.TextEntry", ctl)
	entry:Dock(LEFT)
	entry:SetWide(UI.S(120))
	entry:DockMargin(0, 0, UI.S(10), 0)
	if entry.SetNumeric then entry:SetNumeric(true) end
	if entry.SetPlaceholderText then entry:SetPlaceholderText("Ставка, $") end
	entry:SetText(tostring(st.lastBet or BJ.MinBet))
	win.BetEntry = entry
	for _, v in ipairs({ 5, 25, 100, 500 }) do
		local b = UI.AddButton(ctl, "$" .. v, nil, function()
			entry:SetText(tostring(v))
			surface.PlaySound("ambient/levels/labs/coinslot1.wav")
		end, { dock = LEFT, h = h })
		b:SetWide(UI.S(66))
		b:DockMargin(0, 0, UI.S(6), 0)
	end
	local function bet()
		if animating() then return end
		local n = math.floor(tonumber(entry:GetText()) or 0)
		if n < BJ.MinBet or n > BJ.MaxBet then
			UI.Sound("error")
			NYRP.Notify("Ставка — от $" .. BJ.MinBet .. " до $" .. BJ.MaxBet, "warning", 2)
			return
		end
		if NYRP.Money.Get(LocalPlayer()) < n then
			UI.Sound("error")
			NYRP.Notify("Не хватает наличных", "warning", 2)
			return
		end
		act("bet", n)
	end
	entry.OnEnter = bet
	local go = UI.AddButton(ctl, st.phase == "done" and "Ещё раздача" or "Раздать", "play", bet, { dock = FILL, style = "solid", h = h, accent = GOLD })
	go:DockMargin(UI.S(4), 0, 0, 0)
end

local function paintTable(pnl, w, h)
	local st = BJ.State
	UI.RoundedRect(UI.S(16), 0, 0, w, h, Color(16, 86, 48))
	UI.Glow(w / 2, h * 0.45, w * 1.1, h * 0.9, Color(60, 170, 100, 60))
	UI.Outline(UI.S(16), UI.S(10), UI.S(10), w - UI.S(20), h - UI.S(20), Color(247, 198, 0, 70), 2)
	draw.SimpleText("BLACKJACK PAYS 3 TO 2", NYRP.Font("title", 22), w / 2, h * 0.5, Color(247, 198, 0, 90), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText("Дилер добирает до 17", NYRP.Font("medium", 13), w / 2, h * 0.5 + UI.S(22), Color(255, 255, 255, 70), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	if not st then return end
	local cw = UI.S(96)
	local ch = math.floor(cw * 1.42)
	local gap = UI.S(30)
	-- «башмак» дилера
	local shoeX, shoeY = w - UI.S(80), UI.S(30)
	UI.RoundedRect(UI.S(6), shoeX - UI.S(6), shoeY - UI.S(6), cw * 0.6 + UI.S(12), ch * 0.6 + UI.S(12), Color(10, 40, 24))
	BJ.DrawCard(shoeX, shoeY, cw * 0.6, ch * 0.6, 0)
	local now = RealTime()
	local function row(list, y, label)
		local n = #list
		local total = (n > 0) and (cw + (n - 1) * gap) or cw
		local x0 = w / 2 - total / 2
		for i = 1, n do
			local a = list[i]
			if a and a.flip and now < a.t then
				BJ.DrawCard(x0 + (i - 1) * gap, y, cw, ch, a.prev or 0)
			elseif a and now >= a.t then
				local f = math.Clamp((now - a.t) / FLY, 0, 1)
				local e = UI.Ease(f)
				local tx, ty = x0 + (i - 1) * gap, y
				local x = Lerp(e, shoeX, tx)
				local yy = Lerp(e, shoeY, ty)
				local cww = Lerp(e, cw * 0.6, cw)
				local chh = Lerp(e, ch * 0.6, ch)
				if a.flip and f < 1 then
					-- переворот: сжимаем по ширине
					local k = math.abs(f * 2 - 1)
					local shown = f < 0.5 and 0 or a.card
					BJ.DrawCard(tx + cw * (1 - k) / 2, ty, cw * math.max(k, 0.05), ch, shown)
				else
					BJ.DrawCard(x, yy, cww, chh, a.card)
				end
				if not a.played and f > 0 then
					a.played = true
					cardSound()
				end
			end
		end
		local v, landed = landedValue(list)
		if landed > 0 then
			local tx = x0 + (n - 1) * gap + cw + UI.S(16)
			UI.RoundedRect(UI.S(14), tx, y + ch / 2 - UI.S(16), UI.S(56), UI.S(32), Color(0, 0, 0, 150))
			draw.SimpleText(tostring(v), NYRP.Font("title", 22), tx + UI.S(28), y + ch / 2, v > 21 and Color(255, 110, 100) or color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		draw.SimpleText(label, NYRP.Font("semibold", 13), UI.S(26), y + ch / 2, Color(255, 255, 255, 140), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	row(BJ.Anim.dealer, UI.S(30), "ДИЛЕР")
	row(BJ.Anim.player, h - ch - UI.S(30), "ВЫ")
	-- ставка
	if st.bet > 0 then
		local cx, cy = UI.S(70), h - ch - UI.S(30) - UI.S(34)
		UI.Circle(cx, cy, UI.S(18), Color(220, 40, 50))
		UI.Circle(cx, cy, UI.S(12), Color(250, 250, 250))
		UI.Circle(cx, cy, UI.S(9), Color(220, 40, 50))
		draw.SimpleText("Ставка " .. NYRP.Money.Format(st.bet), NYRP.Font("bold", 16), cx + UI.S(26), cy, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	-- итог / подсказка
	if not animating() then
		if st.phase == "done" and RESULT[st.result] then
			local r = RESULT[st.result]
			local bw, bh = UI.S(420), UI.S(84)
			local bx, by = w / 2 - bw / 2, h / 2 - bh / 2
			UI.RoundedRect(UI.S(14), bx, by, bw, bh, Color(8, 10, 16, 230))
			UI.Outline(UI.S(14), bx, by, bw, bh, UI.Alpha(r[2], 120), 2)
			local gain = (st.payout or 0) - st.bet
			local title = r[1] .. (gain > 0 and ("  +" .. NYRP.Money.Format(gain)) or "")
			draw.SimpleText(title, NYRP.Font("title", 30), w / 2, by + UI.S(28), r[2], TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			draw.SimpleText(st.msg or "", NYRP.Font("medium", 14), w / 2, by + UI.S(60), UI.Col.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		elseif st.phase == "bet" then
			draw.SimpleText("Сделайте ставку и нажмите «Раздать»", NYRP.Font("semibold", 16), w / 2, h / 2 - UI.S(40), color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end
end

function BJ.OpenWindow()
	if IsValid(BJ.Win) then return BJ.Win end
	local win, body = UI.Window("Блэкджек", "coins", 860, 640, { keyboard = true, sub = "Ставки $" .. BJ.MinBet .. "–$" .. BJ.MaxBet .. " · блэкджек 3:2" })
	BJ.Win = win
	local info = vgui.Create("DPanel", body)
	info:Dock(TOP)
	info:SetTall(UI.S(28))
	info:DockMargin(0, 0, 0, UI.S(8))
	info.Paint = function(_, w, h)
		local st = BJ.State
		draw.SimpleText("Место " .. (st and st.seat or "?") .. " из " .. BJ.Seats, NYRP.Font("semibold", 15), 0, h / 2, UI.Col.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText("Наличные: " .. NYRP.Money.Format(NYRP.Money.Get(LocalPlayer())), NYRP.Font("bold", 16), w, h / 2, GOLD, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		if st and st.phase == "play" and st.msg ~= "" and not animating() then
			draw.SimpleText(st.msg, NYRP.Font("semibold", 15), w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end
	local ctl = vgui.Create("EditablePanel", body)
	ctl:Dock(BOTTOM)
	ctl:SetTall(UI.S(46))
	ctl:DockMargin(0, UI.S(12), 0, 0)
	win.Controls = ctl
	local tbl = vgui.Create("DPanel", body)
	tbl:Dock(FILL)
	tbl.Paint = function(s, w, h) paintTable(s, w, h) end
	buildControls(win)
	-- закрыть, если отошли
	win.Think = function(s)
		if gui.IsGameUIVisible() and not s.Closing then gui.HideGameUI() s:Close() return end
		local st = BJ.State
		if s.Closing then return end
		if not st or not IsValid(st.ent) or st.ent:GetPos():Distance(LocalPlayer():GetPos()) > BJ.Range + 20 then s:Close() end
	end
	return win
end

net.Receive("nyrp.bj.state", function()
	local st = { ent = net.ReadEntity(), seat = net.ReadUInt(3), hand = net.ReadUInt(16), phase = net.ReadString(), bet = net.ReadUInt(16), lastBet = net.ReadUInt(16) }
	st.player = {}
	for i = 1, net.ReadUInt(5) do st.player[i] = net.ReadUInt(6) end
	st.dealer = {}
	for i = 1, net.ReadUInt(5) do st.dealer[i] = net.ReadUInt(6) end
	st.result = net.ReadString()
	st.payout = net.ReadUInt(16)
	st.msg = net.ReadString()
	local old = BJ.State
	BJ.State = st
	updateAnim(old, st)
	if st.phase == "done" and RESULT[st.result] then
		local good = st.result == "win" or st.result == "bj"
		local delay = math.max(0, (BJ.AnimEnd or 0) - RealTime())
		timer.Simple(delay, function()
			surface.PlaySound(good and "nyrp/phone/game_record.wav" or (st.result == "push" and "nyrp/ui/notify.wav" or "nyrp/phone/game_over.wav"))
		end)
	end
	local win = BJ.OpenWindow()
	buildControls(win)
end)

net.Receive("nyrp.bj.close", function()
	BJ.State = nil
	BJ.Anim = { player = {}, dealer = {} }
	if IsValid(BJ.Win) then BJ.Win:Close() end
end)
