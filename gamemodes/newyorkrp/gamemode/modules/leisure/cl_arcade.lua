--[[
	Аркада на клиенте: окно автомата — выбор игры и таблицы рекордов (топ-10), сами мини-игры.
	  «Змейка»: стрелки или WASD, поле 24×16, скорость растёт с каждым яблоком.
	  «Реакция»: 5 попыток — жмите ЛКМ или ПРОБЕЛ, когда экран станет зелёным; раньше — фальстарт (+1000 мс).
	Игру оплачивает и результат проверяет сервер; Esc или крестик — выйти (результат не засчитывается).
]]

NYRP.Leisure = NYRP.Leisure or {}
local LS = NYRP.Leisure
LS.Arcade = LS.Arcade or {}
local AR = LS.Arcade
local UI = NYRP.UI

local PURPLE = Color(170, 120, 255)
local CYAN = Color(80, 230, 255)
local GOLD = Color(247, 198, 0)
local SCREEN = Color(8, 6, 20)

AR.Records = AR.Records or { snake = {}, reaction = {} }

local function readRecords()
	local rec = {}
	for _, g in ipairs(AR.Order) do
		local list = {}
		for i = 1, (tonumber(net.ReadUInt(5)) or 0) do
			local name = net.ReadString()
			local score = net.ReadUInt(16)
			list[i] = { name = name, score = score }
		end
		rec[g] = list
	end
	AR.Records = rec
end

local function beep(pitchy)
	surface.PlaySound(pitchy and "buttons/button17.wav" or "buttons/button16.wav")
end

-- нажатие клавиши «по фронту» (опрос, чтобы работало и без фокуса)
local function edge(state, key)
	local down = input.IsKeyDown(key)
	local was = state[key]
	state[key] = down
	return down and not was
end

-- ------------------------------------------------------------- таблица рекордов --
local function paintRecords(game, x, y, w, rowH, highlight)
	local list = AR.Records[game] or {}
	if #list == 0 then
		draw.SimpleText("Рекордов пока нет", NYRP.Font("medium", 14), x, y + rowH / 2, UI.Col.faint, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		return
	end
	for i, r in ipairs(list) do
		local yy = y + (i - 1) * rowH
		if i == highlight then UI.RoundedRect(UI.S(6), x - UI.S(6), yy, w + UI.S(12), rowH, Color(247, 198, 0, 40)) end
		local col = i == 1 and GOLD or (i <= 3 and color_white or UI.Col.dim)
		draw.SimpleText(i .. ".", NYRP.Font("bold", 14), x, yy + rowH / 2, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText(r.name or "?", NYRP.Font("medium", 14), x + UI.S(30), yy + rowH / 2, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText(AR.Format(game, r.score), NYRP.Font("semibold", 14), x + w, yy + rowH / 2, col, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end
end

local function start(game)
	net.Start("nyrp.arc.start")
	net.WriteString(game)
	net.SendToServer()
end

local function finish(game, score, times)
	net.Start("nyrp.arc.finish")
	net.WriteString(game)
	net.WriteUInt(math.Clamp(math.floor(score), 0, 65535), 16)
	times = times or {}
	net.WriteUInt(#times, 4)
	for _, t in ipairs(times) do net.WriteUInt(math.Clamp(math.floor(t), 0, 65535), 16) end
	net.SendToServer()
	AR.Pending = RealTime()
end

-- ------------------------------------------------------------------ меню --
function AR.ShowMenu()
	local win = AR.Win
	if not IsValid(win) or not IsValid(win.Content) then return end
	local body = win.Content
	body:Clear()
	local cw = (body:GetWide() - UI.S(16)) / 2
	for i, g in ipairs(AR.Order) do
		local def = AR.Games[g]
		local p = vgui.Create("DPanel", body)
		p:SetPos((i - 1) * (cw + UI.S(16)), 0)
		p:SetSize(cw, body:GetTall())
		p.Paint = function(_, w, h)
			UI.RoundedRect(UI.S(12), 0, 0, w, h, Color(255, 255, 255, 8))
			UI.RoundedRect(UI.S(12), 0, 0, w, UI.S(110), Color(PURPLE.r, PURPLE.g, PURPLE.b, 30))
			UI.DrawIcon(def.icon, UI.S(40), UI.S(40), UI.S(36), CYAN)
			draw.SimpleText(def.name, NYRP.Font("title", 24), UI.S(70), UI.S(40), color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			local lines = UI.Wrap(def.desc, NYRP.Font("regular", 13), w - UI.S(32))
			for k, l in ipairs(lines) do
				draw.SimpleText(l, NYRP.Font("regular", 13), UI.S(16), UI.S(68) + (k - 1) * UI.S(17), UI.Col.dim)
			end
			draw.SimpleText("ТОП-" .. AR.Top, NYRP.Font("title", 15), UI.S(16), UI.S(124), GOLD)
			paintRecords(g, UI.S(16), UI.S(144), w - UI.S(32), UI.S(24))
		end
		local b = UI.AddButton(p, "Играть — " .. NYRP.Money.Format(AR.Price), "play", function() start(g) end,
			{ dock = false, style = "solid", accent = PURPLE, h = 44 })
		b:SetPos(UI.S(14), p:GetTall() - UI.S(58))
		b:SetWide(cw - UI.S(28))
	end
end

-- ------------------------------------------------------------------ итог --
function AR.ShowResult(game, score, place, personal)
	local win = AR.Win
	if not IsValid(win) or not IsValid(win.Content) then return end
	local body = win.Content
	body:Clear()
	local def = AR.Games[game]
	local p = vgui.Create("DPanel", body)
	p:Dock(FILL)
	p.Paint = function(_, w, h)
		UI.RoundedRect(UI.S(12), 0, 0, w, h, SCREEN)
		draw.SimpleText("ИГРА ОКОНЧЕНА", NYRP.Font("title", 34), w / 2, UI.S(40), PURPLE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		draw.SimpleText(def.name .. ": " .. AR.Format(game, score), NYRP.Font("title", 26), w / 2, UI.S(84), color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		local note = "Без рекорда — попробуйте ещё раз"
		local col = UI.Col.dim
		if place == 1 then
			note, col = "НОВЫЙ РЕКОРД АВТОМАТА!", GOLD
		elseif place > 1 then
			note, col = "Вы в таблице рекордов: " .. place .. " место", CYAN
		elseif personal then
			note = "Личный рекорд, но до топ-" .. AR.Top .. " не дотянули"
		end
		draw.SimpleText(note, NYRP.Font("semibold", 18), w / 2, UI.S(118), col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		local tw = math.min(UI.S(420), w - UI.S(40))
		paintRecords(game, w / 2 - tw / 2, UI.S(146), tw, UI.S(24), place)
	end
	local row = vgui.Create("EditablePanel", p)
	row:Dock(BOTTOM)
	row:SetTall(UI.S(44))
	row:DockMargin(UI.S(14), 0, UI.S(14), UI.S(14))
	local again = UI.AddButton(row, "Ещё раз — " .. NYRP.Money.Format(AR.Price), "refresh", function() start(game) end, { dock = LEFT, style = "solid", accent = PURPLE, h = 44 })
	again:SetWide(UI.S(240))
	local back = UI.AddButton(row, "К выбору игры", "arrow_left", function() AR.ShowMenu() end, { dock = RIGHT, style = "ghost", h = 44 })
	back:SetWide(UI.S(220))
end

-- ---------------------------------------------------------------- змейка --
local function playSnake(body)
	local GW, GH = AR.SnakeW, AR.SnakeH
	local p = vgui.Create("DPanel", body)
	p:Dock(FILL)
	p:SetKeyboardInputEnabled(true)
	local st = {
		snake = { { x = 6, y = 8 }, { x = 5, y = 8 }, { x = 4, y = 8 } },
		dir = { x = 1, y = 0 }, queue = {}, score = 0, tick = 0.13,
		startAt = RealTime() + 3, nextTick = RealTime() + 3, over = false, keys = {}, lastCount = 4,
	}
	local function occupied(x, y)
		for _, s in ipairs(st.snake) do
			if s.x == x and s.y == y then return true end
		end
		return false
	end
	local function placeFood()
		local free = {}
		for x = 1, GW do
			for y = 1, GH do
				if not occupied(x, y) then free[#free + 1] = { x = x, y = y } end
			end
		end
		st.food = #free > 0 and free[math.random(#free)] or nil
	end
	placeFood()
	local function push(dx, dy)
		local last = st.queue[#st.queue] or st.dir
		if (last.x == dx and last.y == dy) or (last.x == -dx and last.y == -dy) then return end
		if #st.queue < 2 then st.queue[#st.queue + 1] = { x = dx, y = dy } end
	end
	local function keyDir(code)
		if code == KEY_UP or code == KEY_W then push(0, -1)
		elseif code == KEY_DOWN or code == KEY_S then push(0, 1)
		elseif code == KEY_LEFT or code == KEY_A then push(-1, 0)
		elseif code == KEY_RIGHT or code == KEY_D then push(1, 0) end
	end
	p.OnKeyCodePressed = function(_, code) keyDir(code) end
	local function gameOver()
		if st.over then return end
		st.over = true
		st.overAt = RealTime()
		surface.PlaySound("nyrp/phone/game_over.wav")
		finish("snake", st.score)
	end
	p.Think = function()
		if st.over then return end
		for _, k in ipairs({ KEY_UP, KEY_W, KEY_DOWN, KEY_S, KEY_LEFT, KEY_A, KEY_RIGHT, KEY_D }) do
			if edge(st.keys, k) then keyDir(k) end
		end
		local now = RealTime()
		if now < st.startAt then
			local c = math.ceil(st.startAt - now)
			if c ~= st.lastCount then st.lastCount = c beep(false) end
			return
		end
		if st.lastCount ~= 0 then st.lastCount = 0 beep(true) end
		if now < st.nextTick then return end
		st.nextTick = now + st.tick
		if #st.queue > 0 then st.dir = table.remove(st.queue, 1) end
		local head = st.snake[1]
		local nx, ny = head.x + st.dir.x, head.y + st.dir.y
		if nx < 1 or nx > GW or ny < 1 or ny > GH then gameOver() return end
		local eat = st.food and st.food.x == nx and st.food.y == ny
		-- хвост уходит, если не съели — в него можно «въехать»
		if not eat then table.remove(st.snake) end
		if occupied(nx, ny) then gameOver() return end
		table.insert(st.snake, 1, { x = nx, y = ny })
		if eat then
			st.score = st.score + 1
			st.tick = math.max(0.07, st.tick - 0.003)
			surface.PlaySound("buttons/lightswitch2.wav")
			placeFood()
			if not st.food then gameOver() end
		end
	end
	p.Paint = function(_, w, h)
		UI.RoundedRect(UI.S(12), 0, 0, w, h, SCREEN)
		local top = UI.S(40)
		local cell = math.floor(math.min((w - UI.S(24)) / GW, (h - top - UI.S(12)) / GH))
		local fw, fh = cell * GW, cell * GH
		local ox, oy = math.floor(w / 2 - fw / 2), top
		draw.SimpleText("ЗМЕЙКА", NYRP.Font("title", 20), ox, top / 2, PURPLE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText("Яблок: " .. st.score, NYRP.Font("bold", 18), ox + fw, top / 2, GOLD, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		surface.SetDrawColor(20, 16, 44, 255)
		surface.DrawRect(ox, oy, fw, fh)
		surface.SetDrawColor(255, 255, 255, 5)
		for x = 0, GW do surface.DrawRect(ox + x * cell, oy, 1, fh) end
		for y = 0, GH do surface.DrawRect(ox, oy + y * cell, fw, 1) end
		surface.SetDrawColor(PURPLE.r, PURPLE.g, PURPLE.b, 160)
		surface.DrawOutlinedRect(ox - 1, oy - 1, fw + 2, fh + 2, 2)
		if st.food then
			local pulse = (math.sin(RealTime() * 8) + 1) / 2
			UI.Circle(ox + (st.food.x - 0.5) * cell, oy + (st.food.y - 0.5) * cell, cell * (0.34 + pulse * 0.06), Color(255, 70, 90))
		end
		local n = #st.snake
		for i, s in ipairs(st.snake) do
			local k = 1 - (i - 1) / math.max(n, 1) * 0.6
			local col = i == 1 and CYAN or Color(60 * k, 200 * k, 160 * k + 40)
			draw.RoundedBox(math.floor(cell * 0.25), ox + (s.x - 1) * cell + 1, oy + (s.y - 1) * cell + 1, cell - 2, cell - 2, col)
		end
		local now = RealTime()
		if now < st.startAt then
			draw.SimpleText(tostring(math.ceil(st.startAt - now)), NYRP.Font("title", 72), w / 2, oy + fh / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			draw.SimpleText("Стрелки или WASD", NYRP.Font("medium", 16), w / 2, oy + fh / 2 + UI.S(56), UI.Col.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		elseif st.over then
			draw.SimpleText("КОНЕЦ ИГРЫ", NYRP.Font("title", 48), w / 2, oy + fh / 2, Color(255, 90, 90), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end
	p:RequestFocus()
end

-- --------------------------------------------------------------- реакция --
local function playReaction(body, delays)
	local p = vgui.Create("DPanel", body)
	p:Dock(FILL)
	p:SetCursor("hand")
	local st = { round = 1, times = {}, phase = "wait", keys = {}, msg = "", sent = false }
	local function beginRound()
		st.phase = "wait"
		st.goAt = SysTime() + (delays[st.round] or 2)
		st.msg = ""
	end
	beginRound()
	local function nextRound(holdUntil)
		st.phase = "show"
		st.showUntil = holdUntil
	end
	local function press()
		local now = SysTime()
		if st.phase == "wait" then
			if now < st.goAt then
				st.times[st.round] = 1000
				st.msg = "Фальстарт! +1000 мс"
				surface.PlaySound("buttons/button10.wav")
				nextRound(math.max(now + 1.2, st.goAt + 0.6))
			end
		elseif st.phase == "go" then
			local ms = math.floor((now - st.goAt) * 1000)
			if ms < 100 then
				ms = 1000
				st.msg = "Слишком рано! +1000 мс"
				surface.PlaySound("buttons/button10.wav")
			else
				ms = math.min(ms, 1500)
				st.msg = ms .. " мс"
				surface.PlaySound("buttons/button17.wav")
			end
			st.times[st.round] = ms
			nextRound(now + 1.2)
		end
	end
	p.OnMousePressed = function(_, code) if code == MOUSE_LEFT then press() end end
	p.Think = function()
		if st.phase == "done" then return end
		if edge(st.keys, KEY_SPACE) then press() end
		local now = SysTime()
		if st.phase == "wait" and now >= st.goAt then
			st.phase = "go"
			surface.PlaySound("buttons/button14.wav")
		elseif st.phase == "go" and now - st.goAt > 1.5 then
			st.times[st.round] = 1500
			st.msg = "Слишком долго: 1500 мс"
			nextRound(now + 1)
		elseif st.phase == "show" and now >= st.showUntil then
			if st.round >= #delays then
				st.phase = "done"
				local sum = 0
				for _, t in ipairs(st.times) do sum = sum + t end
				st.avg = math.floor(sum / math.max(#st.times, 1) + 0.5)
				finish("reaction", st.avg, st.times)
			else
				st.round = st.round + 1
				beginRound()
			end
		end
	end
	p.Paint = function(_, w, h)
		local bg = SCREEN
		local title, sub = "ЖДИТЕ…", "Нажмите, когда экран станет зелёным"
		if st.phase == "go" then
			bg = Color(30, 170, 80)
			title, sub = "ЖМИ!", "ЛКМ или ПРОБЕЛ"
		elseif st.phase == "wait" then
			bg = Color(120, 24, 36)
		elseif st.phase == "show" then
			title, sub = st.msg, "Попытка " .. st.round .. " из " .. #delays
		elseif st.phase == "done" then
			title, sub = "Среднее: " .. (st.avg or 0) .. " мс", "Отправляем результат…"
		end
		UI.RoundedRect(UI.S(12), 0, 0, w, h, bg)
		draw.SimpleText("РЕАКЦИЯ · попытка " .. math.min(st.round, #delays) .. "/" .. #delays, NYRP.Font("title", 18), UI.S(18), UI.S(22), Color(255, 255, 255, 180), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText(title, NYRP.Font("title", 64), w / 2, h / 2 - UI.S(20), color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		draw.SimpleText(sub, NYRP.Font("medium", 18), w / 2, h / 2 + UI.S(34), Color(255, 255, 255, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		-- результаты попыток
		local x = w / 2 - (#delays * UI.S(90)) / 2
		for i = 1, #delays do
			local t = st.times[i]
			local bx = x + (i - 1) * UI.S(90)
			UI.RoundedRect(UI.S(8), bx + UI.S(4), h - UI.S(60), UI.S(82), UI.S(40), Color(0, 0, 0, 90))
			draw.SimpleText(t and (t .. " мс") or "—", NYRP.Font("semibold", 15), bx + UI.S(45), h - UI.S(40), t and color_white or Color(255, 255, 255, 90), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end
end

-- ------------------------------------------------------------------ сеть --
net.Receive("nyrp.arc.open", function()
	local ent = net.ReadEntity()
	readRecords()
	if IsValid(AR.Win) then AR.ShowMenu() return end
	AR.Pending = nil
	local win, body = UI.Window("Аркада", "p_game", 820, 600, { keyboard = true, sub = "$" .. AR.Price .. " за игру · только рекорды" })
	AR.Win = win
	AR.Ent = ent
	win.Content = body
	AR.ShowMenu()
	win.Think = function(s)
		if gui.IsGameUIVisible() and not s.Closing then gui.HideGameUI() s:Close() return end
		if not s.Closing and (not IsValid(AR.Ent) or AR.Ent:GetPos():Distance(LocalPlayer():GetPos()) > 190) then s:Close() return end
		-- сервер не ответил итогом (результат не принят) — вернуться в меню
		if AR.Pending and RealTime() - AR.Pending > 3 then
			AR.Pending = nil
			AR.ShowMenu()
		end
	end
end)

net.Receive("nyrp.arc.go", function()
	local game = net.ReadString()
	local delays = {}
	for i = 1, (tonumber(net.ReadUInt(4)) or 0) do delays[i] = net.ReadFloat() end
	local win = AR.Win
	if not IsValid(win) or not IsValid(win.Content) then return end
	win.Content:Clear()
	if game == "snake" then
		playSnake(win.Content)
	elseif game == "reaction" then
		playReaction(win.Content, delays)
	end
end)

net.Receive("nyrp.arc.result", function()
	local game = net.ReadString()
	local score = net.ReadUInt(16)
	local place = net.ReadUInt(5)
	local personal = net.ReadBool()
	readRecords()
	AR.Pending = nil
	if not AR.Games[game] then return end
	if place == 1 then surface.PlaySound("nyrp/phone/game_record.wav") end
	-- дать полюбоваться концом игры
	timer.Simple(0.8, function() AR.ShowResult(game, score, place, personal) end)
end)
