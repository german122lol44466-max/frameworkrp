--[[
	Интерфейс смартфона: окно справа снизу (над водяным знаком). Открывается только когда телефон
	в руках и в нём есть SIM-карта. Управление: стрелки — выбор, Enter — открыть/нажать, Backspace — назад,
	ПКМ — убрать телефон от лица, F2 — свободная мышь (клик — нажать).
	Экраны рисуются в HUDPaint «немедленным режимом»: каждый кадр экран регистрирует кнопки (P.Btn),
	стрелки двигают фокус к ближайшей кнопке в нужную сторону.
]]

local UI = NYRP.UI
local P = NYRP.Phone

P.Screens = P.Screens or {}
P.Stack = P.Stack or {}
P.Call = P.Call or nil
P.Open = false
P.Mouse = false
P.Focus = nil
P.Btns = {}
local born, closing = 0, nil

local YELLOW = Color(247, 198, 0)
local WHITE = Color(244, 245, 248)
local DIM = Color(170, 175, 190)
local FAINT = Color(110, 115, 130)
P.Col = { yellow = YELLOW, white = WHITE, dim = DIM, faint = FAINT, red = Color(232, 72, 64), green = Color(64, 196, 104),
	card = Color(255, 255, 255, 14), cardHi = Color(255, 255, 255, 34), bg = Color(12, 13, 20, 235) }
local C = P.Col

-- ------------------------------------------------------------- данные --
function P.Item() return P.Equipped(LocalPlayer()) end
function P.Data()
	local it = P.Item()
	return it and it.data or {}
end
function P.Settings()
	local d = P.Data()
	d.settings = d.settings or { wall = 1, ring = 1, alarm = 1 }
	return d.settings
end
-- отправить изменённую часть данных на сервер (он проверит и пришлёт синхронизацию)
function P.Save(key)
	local d = P.Data()
	if d[key] == nil then return end
	net.Start("nyrp.phone.set")
	net.WriteString(key)
	net.WriteTable(d[key])
	net.SendToServer()
end

function P.ContactName(number)
	number = P.Digits(number)
	for _, c in ipairs(P.Data().contacts or {}) do
		if c.number == number then return c.name end
	end
end
function P.Who(number)
	return P.ContactName(number) or P.FormatNumber(number)
end

local function inHands()
	local w = LocalPlayer():GetActiveWeapon()
	return IsValid(w) and w:GetClass() == "nyrp_phone"
end

function P.Active()
	local it = P.Item()
	return it and it.data and it.data.sim and inHands()
end

-- ---------------------------------------------------------- экраны --
-- P.Register(name, {title, draw = function(st, x, y, w, h), key = function(st, key) -> true если обработал, enter, leave})
function P.Register(name, def) P.Screens[name] = def end

function P.Push(name, st)
	st = st or {}
	st.name = name
	P.Stack[#P.Stack + 1] = st
	P.Focus = nil
	P.Trans = RealTime()
	local def = P.Screens[name]
	if def and def.enter then def.enter(st) end
	UI.Sound("click")
end

function P.Back()
	if #P.Stack <= 1 then return end
	local st = table.remove(P.Stack)
	local def = P.Screens[st.name]
	if def and def.leave then def.leave(st) end
	P.Focus = st.from
	P.Trans = RealTime()
	surface.PlaySound("nyrp/phone/key.wav")
end

function P.Home()
	while #P.Stack > 1 do P.Back() end
end

function P.Top() return P.Stack[#P.Stack] end

-- --------------------------------------------------------- открытие --
local function locked()
	local s = P.Settings()
	return s.pin or s.face
end

function P.OpenUI()
	if P.Open then return true end
	if not inHands() then return false end
	local it = P.Item()
	if not it then return false end
	if not (it.data and it.data.sim) then
		NYRP.Notify("Телефон не активирован: вставьте SIM-карту (перетащите её на телефон в инвентаре)", "warning", 6)
		return false
	end
	P.Open = true
	born, closing = RealTime(), nil
	P.Unlocked = not locked()
	P.LockBorn = RealTime()
	if #P.Stack == 0 then P.Stack = { { name = "home" } } end
	P.Focus = nil
	surface.PlaySound("nyrp/phone/unlock.wav")
	return true
end

function P.CloseUI(instant)
	if not P.Open then return end
	if P.Prompt then P.CancelPrompt() end
	P.Open = false
	closing = RealTime()
	if P.Mouse then P.Mouse = false NYRP.FreeMouse("phone", false) end
	if P.OnClose then P.OnClose() end
	surface.PlaySound("nyrp/phone/lock.wav")
	if instant then closing = nil end
end

function P.IsOpen() return P.Open end

-- поднять/опустить телефон в руке (анимация вьюмодели идёт с сервера)
function P.RaiseWeapon(up)
	local w = LocalPlayer():GetActiveWeapon()
	if IsValid(w) and w.Raise then w:Raise(up) end
	RunConsoleCommand("nyrp_phone_raise", up and "1" or "0")
end

-- ------------------------------------------------------------ кнопки --
-- Регистрирует кнопку текущего кадра. Возвращает фокус (bool) и «наведение мышью».
function P.Btn(id, x, y, w, h, act, opts)
	local b = { id = id, x = x, y = y, w = w, h = h, act = act, opts = opts }
	-- попадание мышью запоминаем сейчас (с учётом обрезки прокруткой), а фокус выбираем в конце кадра —
	-- верхняя из перекрывающихся кнопок (иначе фокус «прыгал» между ними каждый кадр)
	if P.Mouse then
		local mx, my = gui.MousePos()
		b.hover = mx >= x and mx <= x + w and my >= y and my <= y + h and P.ClipOk(my)
	end
	P.Btns[#P.Btns + 1] = b
	return P.Focus == id
end

function P.ResolveHover()
	if not P.Mouse then P.HoverId = nil return end
	for i = #P.Btns, 1, -1 do
		local b = P.Btns[i]
		if b.hover then
			P.Focus = b.id
			-- звук — только когда курсор перешёл на другую кнопку
			if P.HoverId ~= b.id then
				P.HoverId = b.id
				surface.PlaySound("nyrp/phone/key.wav")
			end
			return
		end
	end
	P.HoverId = nil
end

-- кнопки, обрезанные прокруткой, не должны ловить мышь
P.Clip = nil
function P.ClipOk(my)
	return not P.Clip or (my >= P.Clip[1] and my <= P.Clip[2])
end

local function activate(b)
	if not b or not b.act then return end
	surface.PlaySound("nyrp/phone/key.wav")
	b.act()
end

local function center(b) return b.x + b.w / 2, b.y + b.h / 2 end

local function move(dx, dy)
	local cur
	for _, b in ipairs(P.Btns) do if b.id == P.Focus then cur = b end end
	if not cur then
		if P.Btns[1] then P.Focus = P.Btns[1].id end
		return
	end
	local cx, cy = center(cur)
	local best, bs
	for _, b in ipairs(P.Btns) do
		if b ~= cur and not (b.opts and b.opts.noNav) then
			local bx, by = center(b)
			local vx, vy = bx - cx, by - cy
			local along = vx * dx + vy * dy
			if along > 2 then
				local perp = math.abs(vx * dy - vy * dx)
				-- кнопки «в одной строке/колонке» предпочтительнее
				local overlap = dx ~= 0 and (b.y < cur.y + cur.h and b.y + b.h > cur.y) or (dy ~= 0 and (b.x < cur.x + cur.w and b.x + b.w > cur.x))
				local s = along + perp * (overlap and 0.3 or 2.2)
				if not bs or s < bs then best, bs = b, s end
			end
		end
	end
	if best then
		P.Focus = best.id
		surface.PlaySound("nyrp/phone/key.wav")
	end
end

-- ----------------------------------------------------------- ввод текста --
-- P.Ask(title, default, opts{numeric, max, hint}, cb(text))
function P.Ask(title, default, opts, cb)
	if P.Prompt then P.CancelPrompt() end
	opts = opts or {}
	-- настоящее поле ввода поверх окошка на экране телефона (фон и заголовок рисует HUDPaint)
	local x, y, w, h = P.Rect()
	local bz = UI.S(9)
	local sx, sw, sh = x + bz, w - bz * 2, h - bz * 2
	local py = y + bz + sh - UI.S(150)
	local frame = vgui.Create("EditablePanel")
	frame:SetPos(sx + UI.S(18), py + UI.S(34))
	frame:SetSize(sw - UI.S(36), UI.S(70))
	frame:MakePopup()
	frame.Paint = function() end
	local e = vgui.Create("DTextEntry", frame)
	e:Dock(FILL)
	e:SetMultiline(not opts.numeric)
	e:SetFont(NYRP.Font("medium", 14))
	e:SetText(default or "")
	e:SetUpdateOnType(true)
	e:SetDrawLanguageID(false)
	e:SetCursor("beam")
	e.Paint = function(pnl, pw, ph)
		if pnl:GetValue() == "" and opts.hint then
			draw.SimpleText(opts.hint, NYRP.Font("medium", 14), UI.S(4), UI.S(4), FAINT)
		end
		pnl:DrawTextEntryText(WHITE, Color(247, 198, 0, 120), YELLOW)
	end
	e.AllowInput = function(_, ch)
		if opts.numeric and not ch:match(opts.pattern or "%d") then return true end
		if (utf8.len(e:GetValue()) or 0) >= (opts.max or 120) then return true end
	end
	local function submit()
		local v = string.Trim((string.gsub(e:GetValue(), "\n", " ")))
		P.CancelPrompt()
		if cb then cb(v) end
	end
	e.OnEnter = submit
	e.OnKeyCodeTyped = function(_, k)
		if k == KEY_ENTER or k == KEY_PAD_ENTER then submit() return true end
		if k == KEY_ESCAPE then
			P.CancelPrompt()
			timer.Simple(0, function() if gui.IsGameUIVisible() then gui.HideGameUI() end end)
			return true
		end
	end
	timer.Simple(0, function()
		if IsValid(e) then
			e:RequestFocus()
			e:SetCaretPos(utf8.len(e:GetValue()) or 0)
		end
	end)
	P.Prompt = { entry = e, frame = frame, title = title, hint = opts.hint, born = RealTime() }
end

-- F2: свободная мышь. Курсор сразу ставим на экран телефона.
function P.ToggleMouse(on)
	if (P.LastToggle or 0) + 0.2 > RealTime() then return end   -- клавиша и бинд F2 не должны переключить дважды
	P.LastToggle = RealTime()
	if on == nil then on = not P.Mouse end
	P.Mouse = on
	NYRP.FreeMouse("phone", on)
	if on then
		local x, y, w, h = P.Rect()
		input.SetCursorPos(math.floor(x + w / 2), math.floor(y + h * 0.55))
	end
	surface.PlaySound("nyrp/phone/key.wav")
end

function P.CancelPrompt()
	if P.Prompt and IsValid(P.Prompt.frame) then P.Prompt.frame:Remove() end
	P.Prompt = nil
	P.SkipKeys = RealTime() + 0.15
end

-- ---------------------------------------------------------- клавиши --
local keyState = {}
local function pressed(k)
	local d = input.IsKeyDown(k)
	local was = keyState[k]
	keyState[k] = d
	return d and not was
end

hook.Add("Think", "nyrp.phone.keys", function()
	-- телефон закрывается сам, если его убрали из рук / вынули SIM
	if P.Open and not P.Active() then P.CloseUI(true) end
	-- F2 обрабатываем всегда, пока телефон открыт (даже если фокус клавиатуры у другой панели)
	if pressed(KEY_F2) and P.Open and not P.Prompt and not gui.IsGameUIVisible() then P.ToggleMouse() end
	local keys = { KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_PAD_ENTER, KEY_BACKSPACE }
	if not P.Open or P.Prompt or gui.IsGameUIVisible() or (P.SkipKeys and RealTime() < P.SkipKeys)
		or (IsValid(vgui.GetKeyboardFocus()) and not P.Mouse) or (NYRP.Chat and NYRP.Chat.IsOpen and NYRP.Chat.IsOpen()) then
		for _, k in ipairs(keys) do keyState[k] = input.IsKeyDown(k) end
		return
	end
	local top = P.Top()
	-- клавиши получает экран приложения, только если он сейчас на экране (не звонок/блокировка/будильник)
	local def = P.ActiveScreen and P.Screens[P.ActiveScreen]
	local dirs = { [KEY_UP] = { 0, -1, "up" }, [KEY_DOWN] = { 0, 1, "down" }, [KEY_LEFT] = { -1, 0, "left" }, [KEY_RIGHT] = { 1, 0, "right" } }
	for k, d in pairs(dirs) do
		if pressed(k) then
			if not (def and def.key and def.key(P.ActiveState or top, d[3])) then move(d[1], d[2]) end
		end
	end
	if pressed(KEY_ENTER) or pressed(KEY_PAD_ENTER) then
		if not (def and def.key and def.key(P.ActiveState or top, "enter")) then
			for _, b in ipairs(P.Btns) do if b.id == P.Focus then activate(b) break end end
		end
	end
	if pressed(KEY_BACKSPACE) then
		if not (def and def.key and def.key(P.ActiveState or top, "back")) then P.Back() end
	end
end)

-- стрелки по умолчанию привязаны к движению — пока телефон открыт, они только для телефона
hook.Add("PlayerBindPress", "nyrp.phone", function(_, bind, down)
	if not P.Open then return end
	local arrow = input.IsKeyDown(KEY_UP) or input.IsKeyDown(KEY_DOWN) or input.IsKeyDown(KEY_LEFT) or input.IsKeyDown(KEY_RIGHT)
	if arrow and (bind:find("forward") or bind:find("back") or bind:find("left") or bind:find("right") or bind:find("lookup") or bind:find("lookdown")) then
		return true
	end
	if input.IsKeyDown(KEY_ENTER) or input.IsKeyDown(KEY_BACKSPACE) then return true end
	if bind:find("gm_showteam") then
		if down and not P.Prompt then P.ToggleMouse() end
		return true
	end
end)

hook.Add("GUIMousePressed", "nyrp.phone", function(code)
	if not P.Open or not P.Mouse or P.Prompt then return end
	if code == MOUSE_RIGHT then
		P.CloseUI()
		P.RaiseWeapon(false)
		return
	end
	if code ~= MOUSE_LEFT then return end
	local mx, my = gui.MousePos()
	for i = #P.Btns, 1, -1 do
		local b = P.Btns[i]
		if mx >= b.x and mx <= b.x + b.w and my >= b.y and my <= b.y + b.h and P.ClipOk(my) then
			P.Focus = b.id
			local top = P.Top()
			local def = P.ActiveScreen and P.Screens[P.ActiveScreen]
			if not (def and def.click and def.click(P.ActiveState or top, b)) then activate(b) end
			return
		end
	end
end)

-- -------------------------------------------------------------- рисование --
function P.Text(t, font, size, x, y, col, ax, ay)
	draw.SimpleText(t, NYRP.Font(font, size), x, y, col or WHITE, ax or TEXT_ALIGN_LEFT, ay or TEXT_ALIGN_TOP)
end

function P.Icon(name, x, y, size, col)
	UI.DrawIcon(name, x, y, size, col)
end

-- кнопка-плашка со скруглением и подсветкой фокуса
function P.Pill(id, x, y, w, h, label, act, o)
	o = o or {}
	local f = P.Btn(id, x, y, w, h, act)
	local bg = o.bg or (o.solid and (o.color or YELLOW)) or C.card
	if f then bg = o.solid and UI.LerpColor(0.25, bg, color_white) or C.cardHi end
	UI.RoundedRect(o.r or UI.S(10), x, y, w, h, bg)
	if f then UI.Outline(o.r or UI.S(10), x, y, w, h, UI.Alpha(o.color or YELLOW, 220), UI.S(2)) end
	local tc = o.solid and Color(12, 12, 16) or (o.textColor or WHITE)
	if o.icon then
		if label and label ~= "" then
			P.Icon(o.icon, x + UI.S(20), y + h / 2, UI.S(18), o.iconColor or tc)
			P.Text(label, o.font or "semibold", o.size or 14, x + UI.S(38), y + h / 2, tc, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		else
			P.Icon(o.icon, x + w / 2, y + h / 2, o.iconSize or UI.S(20), o.iconColor or tc)
		end
	else
		P.Text(label, o.font or "semibold", o.size or 14, x + w / 2, y + h / 2, tc, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	return f
end

-- Заголовок приложения с кнопкой «назад». Возвращает y, с которого начинать содержимое.
function P.Header(title, x, y, w, color)
	local f = P.Btn("hdr.back", x + UI.S(8), y + UI.S(6), UI.S(34), UI.S(34), P.Back)
	if f then UI.RoundedRect(UI.S(17), x + UI.S(8), y + UI.S(6), UI.S(34), UI.S(34), C.cardHi) end
	P.Icon("p_back", x + UI.S(25), y + UI.S(23), UI.S(18), f and YELLOW or WHITE)
	P.Text(title, "bold", 19, x + UI.S(48), y + UI.S(23), color or WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	return y + UI.S(48)
end

-- Прокручиваемый список строк. drawRow(i, x, y, w, h, focused); act(i)
function P.List(st, prefix, n, x, y, w, h, rowH, drawRow, act)
	st.scroll = st.scroll or 0
	local fi
	for i = 1, n do if P.Focus == prefix .. i then fi = i end end
	if fi then
		local top = (fi - 1) * rowH
		if top < st.scroll then st.scroll = top end
		if top + rowH > st.scroll + h then st.scroll = top + rowH - h end
	end
	st.scroll = math.Clamp(st.scroll, 0, math.max(0, n * rowH - h))
	st.sm = Lerp(FrameTime() * 14, st.sm or st.scroll, st.scroll)
	render.SetScissorRect(x, y, x + w, y + h, true)
	P.Clip = { y, y + h }
	for i = 1, n do
		local ry = y + (i - 1) * rowH - st.sm
		if ry + rowH > y - rowH and ry < y + h + rowH then
			local f = P.Btn(prefix .. i, x, ry, w, rowH - UI.S(4), function() act(i) end)
			drawRow(i, x, ry, w, rowH - UI.S(4), f)
		end
	end
	P.Clip = nil
	render.SetScissorRect(0, 0, 0, 0, false)
	-- полоса прокрутки
	if n * rowH > h then
		local frac = h / (n * rowH)
		local bh = math.max(UI.S(20), h * frac)
		local by = y + (h - bh) * (st.sm / math.max(1, n * rowH - h))
		UI.RoundedRect(UI.S(2), x + w - UI.S(3), by, UI.S(3), bh, Color(255, 255, 255, 60))
	end
end

-- Строка списка: иконка, заголовок, подпись, справа значение.
function P.Row(x, y, w, h, f, icon, title, sub, right, iconCol)
	UI.RoundedRect(UI.S(10), x, y, w - UI.S(6), h, f and C.cardHi or C.card)
	if f then UI.Outline(UI.S(10), x, y, w - UI.S(6), h, UI.Alpha(YELLOW, 200), UI.S(2)) end
	local tx = x + UI.S(12)
	if icon then
		UI.Circle(x + UI.S(26), y + h / 2, UI.S(15), UI.Alpha(iconCol or YELLOW, 40))
		P.Icon(icon, x + UI.S(26), y + h / 2, UI.S(16), iconCol or YELLOW)
		tx = x + UI.S(48)
	end
	if sub and sub ~= "" then
		P.Text(title, "semibold", 14, tx, y + h / 2 - UI.S(1), WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
		P.Text(sub, "regular", 12, tx, y + h / 2 + UI.S(1), DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	else
		P.Text(title, "semibold", 14, tx, y + h / 2, WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	if right then P.Text(right, "medium", 12, x + w - UI.S(18), y + h / 2, DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
end

-- Тост поверх экрана телефона
function P.Toast(text)
	P.ToastText, P.ToastT = text, RealTime()
end

-- Размеры и положение
function P.Rect()
	local w, h = UI.S(300), UI.S(610)
	local wmH = UI.S(300) * 120 / 600 + UI.S(14)
	return ScrW() - w - UI.S(26), ScrH() - h - wmH - UI.S(14), w, h
end

local function statusBar(x, y, w, dark)
	local col = dark and Color(20, 20, 26) or WHITE
	P.Text(NYRP.Time.Format(), "bold", 13, x + UI.S(22), y + UI.S(14), col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	P.Icon("p_battery", x + w - UI.S(26), y + UI.S(14), UI.S(16), col)
	P.Icon("p_wifi", x + w - UI.S(46), y + UI.S(14), UI.S(14), col)
	P.Icon("p_signal", x + w - UI.S(64), y + UI.S(14), UI.S(14), col)
	if P.Call and P.Call.state == "active" then
		UI.RoundedRect(UI.S(8), x + w / 2 - UI.S(30), y + UI.S(6), UI.S(60), UI.S(16), C.green)
		P.Text(string.FormattedTime(CurTime() - P.Call.start, "%02i:%02i"), "bold", 11, x + w / 2, y + UI.S(14), color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end

function P.Wallpaper(x, y, w, h, dim)
	local s = P.Settings()
	surface.SetMaterial(UI.Mat("nyrp/phone/" .. (P.Walls[s.wall or 1] or "wall1") .. ".png"))
	surface.SetDrawColor(255, 255, 255)
	surface.DrawTexturedRect(x, y, w, h)
	if dim then
		surface.SetDrawColor(0, 0, 0, dim)
		surface.DrawRect(x, y, w, h)
	end
end

-- ------------------------------------------------------- экран блокировки --
-- нажатие на клавиатуре кода (экранной или цифрами с клавиатуры)
function P.LockPress(k)
	local s = P.Settings()
	local st = P.LockState
	if not s.pin or not st or P.Unlocked then return end
	st.code = st.code or ""
	if k == "<" then st.code = st.code:sub(1, -2) return end
	surface.PlaySound("nyrp/phone/dtmf_" .. k .. ".wav")
	st.code = st.code .. k
	if #st.code >= #s.pin then
		if st.code == s.pin then
			P.Unlocked = true
			P.LockState = nil
			surface.PlaySound("nyrp/phone/unlock.wav")
		else
			st.wrong = RealTime()
			st.code = ""
			surface.PlaySound("nyrp/phone/busy.wav")
		end
	end
end

-- цифры и Backspace с клавиатуры на экране блокировки
local lockKeys = {}
hook.Add("Think", "nyrp.phone.lockkeys", function()
	if not P.Open or P.Unlocked or P.Call or P.Alarm or P.Prompt or not P.LockState then return end
	for d = 0, 9 do
		local down = input.IsKeyDown(KEY_0 + d) or input.IsKeyDown(KEY_PAD_0 + d)
		if down and not lockKeys[d] then P.LockPress(tostring(d)) end
		lockKeys[d] = down
	end
	local bs = input.IsKeyDown(KEY_BACKSPACE)
	if bs and not lockKeys.bs then P.LockPress("<") end
	lockKeys.bs = bs
end)

local function drawLock(x, y, w, h)
	P.Wallpaper(x, y, w, h, 60)
	local s = P.Settings()
	local hm = NYRP.Time.Format()
	P.Text(P.DateText() .. ", " .. string.lower(P.WeekDays[select(3, P.Date())] or ""), "semibold", 14, x + w / 2, y + UI.S(74), WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	P.Text(hm, "titlelight", 64, x + w / 2, y + UI.S(122), WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	local myChar = LocalPlayer():GetNW2Int("nyrp.charID", -1)
	local faceOk = s.face and s.face == myChar
	local t = RealTime() - (P.LockBorn or 0)
	local st = P.LockState or {}
	P.LockState = st
	-- Face ID
	if s.face and not st.faceDone then
		local cy = y + h * 0.5
		local pulse = 0.5 + math.sin(RealTime() * 6) * 0.5
		UI.Ring(x + w / 2, cy, UI.S(34), UI.Alpha(faceOk and C.green or YELLOW, 120 + pulse * 120))
		P.Icon("p_face", x + w / 2, cy, UI.S(36), WHITE)
		P.Text("Face ID", "semibold", 13, x + w / 2, cy + UI.S(52), DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		if t > 0.9 then
			st.faceDone = true
			if faceOk then
				P.Unlocked = true
				surface.PlaySound("nyrp/phone/unlock.wav")
				return
			end
			st.faceFail = true
			surface.PlaySound("nyrp/phone/busy.wav")
		end
		return
	end
	if not s.pin then
		P.Text("Лицо не распознано", "bold", 15, x + w / 2, y + h * 0.5, C.red, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		P.Text("Этот телефон настроен на другого человека", "regular", 12, x + w / 2, y + h * 0.5 + UI.S(24), DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		return
	end
	-- код-пароль
	st.code = st.code or ""
	local title = st.faceFail and "Лицо не распознано — введите код" or "Введите код-пароль"
	if st.wrong and RealTime() - st.wrong < 1 then title = "Неверный код" end
	P.Text(title, "semibold", 13, x + w / 2, y + UI.S(178), st.wrong and RealTime() - st.wrong < 1 and C.red or WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	local n = #s.pin
	local shake = st.wrong and math.max(0, 1 - (RealTime() - st.wrong) * 3) * math.sin(RealTime() * 60) * UI.S(8) or 0
	for i = 1, n do
		local cx = x + w / 2 + (i - (n + 1) / 2) * UI.S(20) + shake
		if i <= #st.code then UI.Circle(cx, y + UI.S(204), UI.S(6), WHITE) else UI.Ring(cx, y + UI.S(204), UI.S(6), WHITE) end
	end
	local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "<" }
	local bs = UI.S(62)
	local gx = x + w / 2 - bs * 1.5 - UI.S(8)
	for i, k in ipairs(keys) do
		if k ~= "" then
			local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
			local bx, by = gx + col * (bs + UI.S(8)), y + UI.S(236) + row * (bs + UI.S(8))
			local f = P.Btn("lock." .. k, bx, by, bs, bs, function() P.LockPress(k) end)
			UI.Circle(bx + bs / 2, by + bs / 2, bs / 2, f and Color(255, 255, 255, 70) or Color(255, 255, 255, 26))
			if k == "<" then P.Icon("p_back", bx + bs / 2, by + bs / 2, UI.S(20), WHITE)
			else P.Text(k, "titlemed", 26, bx + bs / 2, by + bs / 2, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
		end
	end
end

-- -------------------------------------------------------------- звонок --
local ringback, busyT
local function stopRingback()
	if ringback then ringback:Stop() ringback = nil end
end

net.Receive("nyrp.phone.state", function()
	local state, number, start = net.ReadString(), net.ReadString(), net.ReadFloat()
	stopRingback()
	if state == "dialing" then
		P.Call = { state = state, number = number, born = RealTime() }
		ringback = CreateSound(LocalPlayer(), "nyrp/phone/ringback.wav")
		ringback:PlayEx(0.6, 100)
	elseif state == "ringing" then
		P.Call = { state = state, number = number, born = RealTime() }
		if not P.Open then
			NYRP.Notify("Входящий звонок: " .. P.Who(number) .. (inHands() and " — ЛКМ, чтобы ответить" or " — возьмите телефон в руки"), "info", 6)
		end
	elseif state == "active" then
		P.Call = { state = state, number = number, start = start, born = RealTime() }
	else
		-- завершён / занято / нет номера / не ответили / пропущен
		local text = ({ busy = "Абонент занят", nonumber = "Номер не обслуживается", noanswer = "Абонент не отвечает",
			missed = "Пропущенный вызов", ended = "Вызов завершён" })[state] or "Вызов завершён"
		P.Call = { state = "over", text = text, number = number, born = RealTime() }
		surface.PlaySound(state == "ended" and "nyrp/phone/hangup.wav" or "nyrp/phone/busy.wav")
		if state == "missed" and not P.Open then NYRP.Notify("Пропущенный вызов: " .. P.Who(number), "warning", 6) end
		timer.Create("nyrp.phone.over", 2.2, 1, function() if P.Call and P.Call.state == "over" then P.Call = nil end end)
	end
end)

local function drawCall(x, y, w, h)
	local c = P.Call
	P.Wallpaper(x, y, w, h, 170)
	local name = P.Who(c.number)
	local cy = y + UI.S(150)
	UI.Circle(x + w / 2, cy, UI.S(46), Color(255, 255, 255, 30))
	P.Icon("p_contacts", x + w / 2, cy, UI.S(42), WHITE)
	P.Text(name, "bold", 22, x + w / 2, cy + UI.S(70), WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	if P.ContactName(c.number) then P.Text(P.FormatNumber(c.number), "regular", 13, x + w / 2, cy + UI.S(94), DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
	local status
	if c.state == "dialing" then status = "Вызов" .. string.rep(".", math.floor(RealTime() * 2) % 4)
	elseif c.state == "ringing" then status = "Входящий вызов"
	elseif c.state == "active" then status = string.FormattedTime(CurTime() - c.start, "%02i:%02i")
	else status = c.text end
	P.Text(status, "semibold", 15, x + w / 2, cy + UI.S(122), c.state == "over" and C.red or YELLOW, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	if c.state == "active" then
		local key = input.LookupBinding("+voicerecord") or "?"
		P.Text("Говорите: удерживайте " .. string.upper(key), "regular", 12, x + w / 2, cy + UI.S(146), DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		-- «волна» голоса
		if LocalPlayer():IsSpeaking() then
			for i = -4, 4 do
				local bh = UI.S(6) + math.abs(math.sin(RealTime() * 9 + i)) * UI.S(18) * LocalPlayer():VoiceVolume() * 3
				UI.RoundedRect(UI.S(2), x + w / 2 + i * UI.S(9) - UI.S(2), cy + UI.S(176) - bh / 2, UI.S(4), bh, C.green)
			end
		end
	end
	local by = y + h - UI.S(130)
	local bs = UI.S(64)
	if c.state == "ringing" then
		local f1 = P.Btn("call.decline", x + w * 0.27 - bs / 2, by, bs, bs, function() net.Start("nyrp.phone.hangup") net.SendToServer() end)
		UI.Circle(x + w * 0.27, by + bs / 2, bs / 2 * (f1 and 1.08 or 1), C.red)
		P.Icon("p_hangup", x + w * 0.27, by + bs / 2, UI.S(28), WHITE)
		local f2 = P.Btn("call.answer", x + w * 0.73 - bs / 2, by, bs, bs, function() net.Start("nyrp.phone.answer") net.SendToServer() end)
		UI.Circle(x + w * 0.73, by + bs / 2, bs / 2 * (f2 and 1.08 or 1) + (math.sin(RealTime() * 8) > 0 and UI.S(2) or 0), C.green)
		P.Icon("p_call", x + w * 0.73, by + bs / 2, UI.S(28), WHITE)
		P.Text("Отклонить", "medium", 12, x + w * 0.27, by + bs + UI.S(14), DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		P.Text("Ответить", "medium", 12, x + w * 0.73, by + bs + UI.S(14), DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		if not P.Focus or not P.Focus:find("^call%.") then P.Focus = "call.answer" end
	elseif c.state ~= "over" then
		local f = P.Btn("call.hangup", x + w / 2 - bs / 2, by, bs, bs, function() net.Start("nyrp.phone.hangup") net.SendToServer() end)
		UI.Circle(x + w / 2, by + bs / 2, bs / 2 * (f and 1.08 or 1), C.red)
		P.Icon("p_hangup", x + w / 2, by + bs / 2, UI.S(28), WHITE)
		P.Focus = "call.hangup"
	end
end

-- ------------------------------------------------------------- будильник --
net.Receive("nyrp.phone.alarm", function()
	P.Alarm = { label = net.ReadString(), born = RealTime() }
	-- сервер уже вложил телефон в руку — открываем экран будильника
	timer.Simple(0.6, function()
		if P.Alarm and inHands() and not P.Open and P.OpenUI() then P.RaiseWeapon(true) end
	end)
	timer.Create("nyrp.phone.alarmoff", 60, 1, function() P.Alarm = nil end)
end)

local function alarmAct(snooze)
	net.Start("nyrp.phone.alarmact")
	net.WriteBool(snooze)
	net.SendToServer()
	P.Alarm = nil
	P.Focus = nil
end

local function drawAlarm(x, y, w, h)
	P.Wallpaper(x, y, w, h, 150)
	local pulse = 0.5 + math.sin(RealTime() * 5) * 0.5
	UI.Circle(x + w / 2, y + UI.S(170), UI.S(60 + pulse * 8), UI.Alpha(YELLOW, 40 + pulse * 30))
	P.Icon("p_alarm", x + w / 2, y + UI.S(170), UI.S(50), YELLOW)
	P.Text(NYRP.Time.Format(), "titlelight", 56, x + w / 2, y + UI.S(270), WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	P.Text(P.Alarm.label ~= "" and P.Alarm.label or "Будильник", "semibold", 16, x + w / 2, y + UI.S(316), DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	local bw = w - UI.S(48)
	P.Pill("alarm.snooze", x + UI.S(24), y + h - UI.S(170), bw, UI.S(50), "Отложить на 10 минут", function() alarmAct(true) end, { r = UI.S(25) })
	P.Pill("alarm.off", x + UI.S(24), y + h - UI.S(108), bw, UI.S(50), "Выключить", function() alarmAct(false) end, { solid = true, r = UI.S(25), color = C.red })
	if not P.Focus or not P.Focus:find("^alarm%.") then P.Focus = "alarm.off" end
end

-- ------------------------------------------------------------- главный рисунок --
hook.Add("HUDPaint", "nyrp.phone", function()
	local openT = P.Open and math.min((RealTime() - born) / 0.28, 1) or 0
	local closeT = closing and math.min((RealTime() - closing) / 0.2, 1) or 1
	local vis = P.Open and UI.Ease(openT) or (closing and 1 - UI.Ease(closeT) or 0)
	if vis <= 0.001 then P.Btns = {} return end
	if NYRP.HUDHidden and NYRP.HUDHidden() and not P.Open then return end
	local x, y, w, h = P.Rect()
	y = y + (1 - vis) * (h + UI.S(60))

	P.Btns = {}
	P.ActiveScreen, P.ActiveState = nil, nil
	-- корпус
	UI.RoundedRect(UI.S(42), x - UI.S(3), y - UI.S(3), w + UI.S(6), h + UI.S(6), Color(0, 0, 0, 120))
	UI.RoundedRect(UI.S(40), x, y, w, h, Color(36, 38, 44))
	UI.RoundedRect(UI.S(38), x + UI.S(2), y + UI.S(2), w - UI.S(4), h - UI.S(4), Color(8, 9, 12))
	local bz = UI.S(9)
	local sx, sy, sw, sh = x + bz, y + bz, w - bz * 2, h - bz * 2
	surface.SetDrawColor(10, 11, 16)
	surface.DrawRect(sx, sy, sw, sh)

	if P.Alarm then
		drawAlarm(sx, sy, sw, sh)
	elseif P.Call then
		drawCall(sx, sy, sw, sh)
	elseif not P.Unlocked then
		drawLock(sx, sy, sw, sh)
	else
		local top = P.Top()
		local def = top and P.Screens[top.name]
		if def then
			P.ActiveScreen, P.ActiveState = top.name, top
			local tt = P.Trans and math.min((RealTime() - P.Trans) / 0.18, 1) or 1
			local ok, err = pcall(def.draw, top, sx, sy + UI.S(28), sw, sh - UI.S(28))
			if not ok then
				ErrorNoHalt("[NYRP phone] " .. tostring(err) .. "\n")
				P.Stack = { { name = "home" } }
			end
			if tt < 1 then
				surface.SetDrawColor(10, 11, 16, 255 * (1 - UI.Ease(tt)))
				surface.DrawRect(sx, sy + UI.S(28), sw, sh - UI.S(28))
			end
		end
	end
	statusBar(sx, sy, sw, false)
	-- фокус по умолчанию — первая кнопка
	if P.Open and #P.Btns > 0 then
		local found = false
		for _, b in ipairs(P.Btns) do if b.id == P.Focus then found = true break end end
		if (not found and P.Focus ~= "homebar") or (P.Focus == "homebar" and not P.Mouse) then P.Focus = (P.Btns[2] and P.Btns[1].id == "hdr.back") and P.Btns[2].id or P.Btns[1].id end
	end

	-- ввод текста
	if P.Prompt and IsValid(P.Prompt.entry) then
		local py = sy + sh - UI.S(150)
		surface.SetDrawColor(0, 0, 0, 160)
		surface.DrawRect(sx, sy, sw, sh)
		UI.RoundedRect(UI.S(16), sx + UI.S(10), py, sw - UI.S(20), UI.S(130), Color(28, 30, 40))
		P.Text(P.Prompt.title, "bold", 14, sx + UI.S(24), py + UI.S(14), YELLOW)
		UI.RoundedRect(UI.S(10), sx + UI.S(16), py + UI.S(32), sw - UI.S(32), UI.S(74), Color(14, 15, 22))
		if IsValid(P.Prompt.entry) and P.Prompt.entry:HasFocus() then UI.Outline(UI.S(10), sx + UI.S(16), py + UI.S(32), sw - UI.S(32), UI.S(74), UI.Alpha(YELLOW, 160), UI.S(1)) end
		P.Text("Enter — готово  ·  Esc — отмена", "regular", 11, sx + sw / 2, py + UI.S(112), FAINT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	-- тост
	if P.ToastT and RealTime() - P.ToastT < 2.2 then
		local a = math.min(1, (2.2 - (RealTime() - P.ToastT)) * 4)
		surface.SetFont(NYRP.Font("semibold", 13))
		local tw = surface.GetTextSize(P.ToastText) + UI.S(28)
		UI.RoundedRect(UI.S(14), sx + sw / 2 - tw / 2, sy + sh - UI.S(64), tw, UI.S(28), Color(30, 32, 42, 240 * a))
		P.Text(P.ToastText, "semibold", 13, sx + sw / 2, sy + sh - UI.S(50), UI.Alpha(WHITE, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	-- рамка поверх углов экрана, «чёлка» камеры и полоска «домой»
	UI.Outline(UI.S(40), x, y, w, h, Color(36, 38, 44), UI.S(2))
	UI.Outline(UI.S(38), x + UI.S(2), y + UI.S(2), w - UI.S(4), h - UI.S(4), Color(8, 9, 12), bz - UI.S(2))
	UI.RoundedRect(UI.S(9), x + w / 2 - UI.S(40), sy + UI.S(5), UI.S(80), UI.S(18), Color(0, 0, 0))
	UI.Circle(x + w / 2 + UI.S(26), sy + UI.S(14), UI.S(4), Color(20, 24, 40))
	local hb = P.Open and P.Btn("homebar", x + w / 2 - UI.S(70), y + h - bz - UI.S(24), UI.S(140), UI.S(26), function()
		if P.Unlocked and #P.Stack > 1 and not P.Call and not P.Alarm then
			P.Home()
		else
			P.CloseUI()
			P.RaiseWeapon(false)
		end
	end, { noNav = true })
	UI.RoundedRect(UI.S(3), x + w / 2 - UI.S(hb and 56 or 50), y + h - bz - UI.S(hb and 11 or 10), UI.S(hb and 112 or 100), UI.S(hb and 6 or 4),
		hb and YELLOW or Color(255, 255, 255, 140))

	P.ResolveHover()

	-- подсказки управления под телефоном
	if P.Open then
		local hint = P.Mouse and "Мышь: клик  ·  полоска внизу — домой/выход  ·  ПКМ — убрать  ·  F2 — без мыши" or "↑↓←→ — выбор  ·  Enter  ·  Backspace — назад  ·  ПКМ — убрать  ·  F2 — мышь"
		P.Text(hint, "medium", 11, x + w / 2, y + h + UI.S(12), Color(255, 255, 255, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end)

-- телефон взяли в руки во время входящего звонка/будильника — сразу экран вызова
hook.Add("Think", "nyrp.phone.autoopen", function()
	if P.Open or not inHands() then return end
	if (P.Call and P.Call.state == "ringing") or P.Alarm then
		local w = LocalPlayer():GetActiveWeapon()
		if IsValid(w) and not w.HolsterAt and w.GetRaised and not w:GetRaised() and P.OpenUI() then P.RaiseWeapon(true) end
	end
end)

-- Инвентарь: «Извлечь SIM-карту»
hook.Add("NYRP.ItemContext", "nyrp.phone", function(kind, key, it, opts)
	if it.id ~= "phone" or not (it.data and it.data.sim) then return end
	opts[#opts + 1] = { text = "Извлечь SIM-карту", icon = "arrow_left", func = function()
		net.Start("nyrp.phone.eject")
		net.WriteString(kind)
		net.WriteString(tostring(key))
		net.SendToServer()
	end }
end)

hook.Add("HUDShouldDraw", "nyrp.phone", function(name)
	if P.Open and name == "CHudWeaponSelection" then return false end
end)

-- телефон переложили в слот — закрываем инвентарь, сервер затем даст телефон в руку
net.Receive("nyrp.phone.ui", function()
	if NYRP.Inventory and NYRP.Inventory.IsOpen and NYRP.Inventory.IsOpen() then NYRP.Inventory.Close() end
end)
