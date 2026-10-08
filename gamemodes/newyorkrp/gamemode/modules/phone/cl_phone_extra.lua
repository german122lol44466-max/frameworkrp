--[[
	Камера (фото и видео), Фото, банковские приложения и мини-игры.
	Снимки и видео хранятся у игрока: data/nyrp/phone/<серийник телефона>/
	  p_<время>.jpg — фото; v_<время>.txt — описание видео (кол-во кадров, fps), v_<время>_<n>.jpg — кадры.
]]

local UI = NYRP.UI
local P = NYRP.Phone
local C = P.Col

local function S(x) return UI.S(x) end

-- ------------------------------------------------------------------ файлы --
local function dir()
	local serial = P.Data().serial or "noserial"
	local d = "nyrp/phone/" .. serial
	file.CreateDir(d)
	return d
end

local function stamp() return os.time() .. string.format("%03d", math.random(0, 999)) end

-- список медиа: { {kind="photo"/"video", name, frames, fps} }, новые сверху
function P.Media()
	local d = dir()
	local out = {}
	for _, f in ipairs(file.Find(d .. "/p_*.jpg", "DATA")) do
		out[#out + 1] = { kind = "photo", name = f, t = tonumber(f:match("p_(%d+)")) or 0 }
	end
	for _, f in ipairs(file.Find(d .. "/v_*.txt", "DATA")) do
		local info = util.JSONToTable(file.Read(d .. "/" .. f, "DATA") or "") or {}
		local base = f:gsub("%.txt$", "")
		out[#out + 1] = { kind = "video", name = base, frames = info.frames or 0, fps = info.fps or 8, t = tonumber(base:match("v_(%d+)")) or 0 }
	end
	table.sort(out, function(a, b) return a.t > b.t end)
	return out
end

local matCache = {}
local function mediaMat(path)
	local m = matCache[path]
	if not m then
		m = Material("../data/" .. path, "smooth")
		matCache[path] = m
	end
	return m
end

function P.MediaThumb(m)
	local d = dir()
	if m.kind == "photo" then return mediaMat(d .. "/" .. m.name) end
	return mediaMat(d .. "/" .. m.name .. "_1.jpg")
end

-- ----------------------------------------------------------------- съёмка --
-- Кадр снимаем прямо с видоискателя на экране телефона (второй рендер сцены давал мерцание).
local captureQueue = {}

local function camView(front)
	local eye, ang = EyePos(), EyeAngles()
	if front then
		local a = Angle(-ang.p * 0.3, ang.y + 180, 0)
		return eye + ang:Forward() * 26 + Vector(0, 0, -2), a, true
	end
	return eye + ang:Forward() * 6 + ang:Right() * 3 - ang:Up() * 2, ang, false
end

local function requestCapture(quality, cb)
	captureQueue[#captureQueue + 1] = { quality = quality, cb = cb }
end

-- вызывается сразу после отрисовки видоискателя, до сетки и кнопок
local function processCaptures(x, y, w, h)
	while #captureQueue > 0 do
		local q = table.remove(captureQueue, 1)
		local data = render.Capture({ format = "jpeg", quality = q.quality, x = math.floor(x), y = math.floor(y), w = math.floor(w), h = math.floor(h), alpha = false })
		if data then q.cb(data) end
	end
end

-- ----------------------------------------------------------------- Камера --
P.Register("camera", {
	enter = function(st) st.mode = st.mode or "photo" end,
	leave = function(st) if st.rec then P.StopRec(st) end end,
	draw = function(st, x, y, w, h)
		-- видоискатель на весь экран
		local vy = y - S(28)
		local vh = h + S(28)
		local origin, ang, viewer = camView(st.front)
		render.RenderView({ origin = origin, angles = ang, x = x, y = vy, w = w, h = vh, fov = 62, drawviewmodel = false, drawhud = false, drawviewer = viewer })
		processCaptures(x, vy, w, vh)
		-- сетка
		surface.SetDrawColor(255, 255, 255, 30)
		surface.DrawRect(x + w / 3, vy, 1, vh)
		surface.DrawRect(x + w * 2 / 3, vy, 1, vh)
		surface.DrawRect(x, vy + vh / 3, w, 1)
		surface.DrawRect(x, vy + vh * 2 / 3, w, 1)
		-- вспышка
		if st.flash and RealTime() - st.flash < 0.25 then
			surface.SetDrawColor(255, 255, 255, 255 * (1 - (RealTime() - st.flash) / 0.25))
			surface.DrawRect(x, vy, w, vh)
		end
		-- назад
		local fb = P.Btn("hdr.back", x + S(10), y + S(6), S(36), S(36), function() if st.rec then P.StopRec(st) end P.Back() end)
		UI.Circle(x + S(28), y + S(24), S(18), fb and Color(0, 0, 0, 200) or Color(0, 0, 0, 130))
		P.Icon("p_back", x + S(28), y + S(24), S(18), fb and C.yellow or color_white)
		-- нижняя панель
		local by = y + h - S(120)
		surface.SetDrawColor(0, 0, 0, 150)
		surface.DrawRect(x, by - S(34), w, S(154))
		-- режимы
		for i, m in ipairs({ { "photo", "ФОТО" }, { "video", "ВИДЕО" } }) do
			local mx = x + w / 2 + (i - 1.5) * S(80)
			local f = P.Btn("cam.mode." .. m[1], mx - S(36), by - S(30), S(72), S(24), function()
				if st.rec then return end
				st.mode = m[1]
			end)
			P.Text(m[2], "bold", 12, mx, by - S(18), st.mode == m[1] and C.yellow or (f and color_white or C.dim), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		-- спуск
		local sx, sy, sr = x + w / 2, by + S(44), S(30)
		local f = P.Btn("cam.shoot", sx - sr, sy - sr, sr * 2, sr * 2, function() P.Shoot(st) end)
		UI.Circle(sx, sy, sr + S(4), color_white)
		UI.Circle(sx, sy, sr - S(1), Color(0, 0, 0))
		if st.mode == "video" then
			if st.rec then UI.RoundedRect(S(4), sx - S(12), sy - S(12), S(24), S(24), C.red)
			else UI.Circle(sx, sy, sr - S(5), C.red) end
		else
			UI.Circle(sx, sy, sr - S(5), f and C.yellow or color_white)
		end
		if f then UI.Ring(sx, sy, sr + S(7), C.yellow) end
		-- миниатюра последнего снимка
		local media = st.media or P.Media()
		st.media = media
		local tx, ty, ts = x + S(28), sy - S(22), S(44)
		local f2 = P.Btn("cam.gallery", tx, ty, ts, ts, function() P.Push("photos", { from = "cam.gallery" }) end)
		UI.RoundedRect(S(8), tx - S(2), ty - S(2), ts + S(4), ts + S(4), f2 and C.yellow or Color(255, 255, 255, 120))
		if media[1] then
			surface.SetMaterial(P.MediaThumb(media[1]))
			surface.SetDrawColor(255, 255, 255)
			surface.DrawTexturedRect(tx, ty, ts, ts)
		else
			UI.RoundedRect(S(6), tx, ty, ts, ts, Color(20, 20, 24))
		end
		-- переключение камеры
		local fx = x + w - S(50)
		local f3 = P.Btn("cam.flip", fx - S(22), sy - S(22), S(44), S(44), function() if not st.rec then st.front = not st.front end end)
		UI.Circle(fx, sy, S(22), f3 and Color(255, 255, 255, 80) or Color(255, 255, 255, 34))
		P.Icon("p_face", fx, sy, S(22), st.front and C.yellow or color_white)
		-- идёт запись
		if st.rec then
			local t = RealTime() - st.rec.t0
			UI.RoundedRect(S(10), x + w / 2 - S(44), y + S(10), S(88), S(24), C.red)
			P.Text(string.format("● %02d:%02d", math.floor(t / 60), math.floor(t % 60)), "bold", 12, x + w / 2, y + S(22), color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			-- кадры видео
			local fps = 8
			if RealTime() >= st.rec.next and not st.rec.busy then
				st.rec.next = RealTime() + 1 / fps
				st.rec.n = st.rec.n + 1
				local n = st.rec.n
				local base = st.rec.base
				st.rec.busy = true
				requestCapture(70, function(data)
					file.Write(dir() .. "/" .. base .. "_" .. n .. ".jpg", data)
					if st.rec then st.rec.busy = false end
				end)
			end
			if t >= 20 or st.rec.n >= 160 then P.StopRec(st) end
		end
		-- последний снимок «улетает» в миниатюру
		if st.shotT and RealTime() - st.shotT < 0.5 then
			P.Text("Сохранено в «Фото»", "semibold", 12, x + w / 2, y + S(40), color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end,
	key = function(st, k)
		if k == "back" and st.rec then P.StopRec(st) end
	end,
})

function P.Shoot(st)
	if st.mode == "video" then
		if st.rec then P.StopRec(st) return end
		st.rec = { t0 = RealTime(), next = 0, n = 0, base = "v_" .. stamp() }
		surface.PlaySound("nyrp/phone/rec_start.wav")
		return
	end
	if st.busy then return end
	st.busy = true
	surface.PlaySound("nyrp/phone/shutter.wav")
	LocalPlayer():EmitSound("nyrp/phone/shutter.wav", 50, 100, 0.6)
	st.flash = RealTime()
	requestCapture(92, function(data)
		file.Write(dir() .. "/p_" .. stamp() .. ".jpg", data)
		st.busy = false
		st.media = nil
		st.shotT = RealTime()
	end)
end

function P.StopRec(st)
	local r = st.rec
	if not r then return end
	st.rec = nil
	surface.PlaySound("nyrp/phone/rec_stop.wav")
	-- описание пишем, когда последний кадр точно сохранён
	timer.Simple(0.5, function()
		file.Write(dir() .. "/" .. r.base .. ".txt", util.TableToJSON({ frames = r.n, fps = 8 }))
		st.media = nil
	end)
end

-- ------------------------------------------------------------------- Фото --
P.Register("photos", {
	enter = function(st) st.media = P.Media() end,
	draw = function(st, x, y, w, h)
		local cy = P.Header("Фото", x, y, w, Color(255, 160, 80))
		local media = st.media or {}
		if #media == 0 then
			P.Icon("p_photos", x + w / 2, cy + S(110), S(54), C.faint)
			P.Text("Снимков пока нет — откройте «Камеру»", "medium", 12, x + w / 2, cy + S(160), C.faint, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			return
		end
		local cols = 3
		local ts = (w - S(24) - S(8) * (cols - 1)) / cols
		local rows = math.ceil(#media / cols)
		local areaH = y + h - cy - S(12)
		st.scroll = st.scroll or 0
		-- прокрутка к фокусу
		for i = 1, #media do
			if P.Focus == "ph." .. i then
				local ry = math.floor((i - 1) / cols) * (ts + S(8))
				if ry < st.scroll then st.scroll = ry end
				if ry + ts > st.scroll + areaH then st.scroll = ry + ts - areaH end
			end
		end
		st.scroll = math.Clamp(st.scroll, 0, math.max(0, rows * (ts + S(8)) - areaH))
		render.SetScissorRect(x, cy, x + w, cy + areaH, true)
		P.Clip = { cy, cy + areaH }
		for i, m in ipairs(media) do
			local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
			local bx, by = x + S(12) + col * (ts + S(8)), cy + row * (ts + S(8)) - st.scroll
			if by + ts > cy and by < cy + areaH then
				local f = P.Btn("ph." .. i, bx, by, ts, ts, function() P.Push("photo", { media = m, list = media, idx = i, from = "ph." .. i }) end)
				surface.SetMaterial(P.MediaThumb(m))
				surface.SetDrawColor(255, 255, 255)
				surface.DrawTexturedRect(bx, by, ts, ts)
				if m.kind == "video" then
					UI.Circle(bx + ts / 2, by + ts / 2, S(14), Color(0, 0, 0, 140))
					P.Icon("p_play", bx + ts / 2, by + ts / 2, S(14), color_white)
					P.Text(string.format("0:%02d", math.floor(m.frames / m.fps)), "bold", 10, bx + ts - S(6), by + ts - S(6), color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
				end
				if f then UI.Outline(S(4), bx - S(2), by - S(2), ts + S(4), ts + S(4), C.yellow, S(3)) end
			end
		end
		P.Clip = nil
		render.SetScissorRect(0, 0, 0, 0, false)
	end,
})

P.Register("photo", {
	enter = function(st) st.t0 = RealTime() end,
	draw = function(st, x, y, w, h)
		local m = st.media
		surface.SetDrawColor(0, 0, 0)
		surface.DrawRect(x, y - S(28), w, h + S(28))
		local d = dir()
		local mat
		if m.kind == "photo" then
			mat = mediaMat(d .. "/" .. m.name)
		else
			local n = math.max(1, m.frames)
			local frame = math.floor((RealTime() - st.t0) * m.fps) % n + 1
			mat = mediaMat(d .. "/" .. m.name .. "_" .. frame .. ".jpg")
		end
		-- снимок 9:16 вписываем в экран
		local ih = h - S(60)
		local iw = ih * 9 / 16
		if iw > w then iw = w ih = iw * 16 / 9 end
		surface.SetMaterial(mat)
		surface.SetDrawColor(255, 255, 255)
		surface.DrawTexturedRect(x + w / 2 - iw / 2, y, iw, ih)
		local by = y + h - S(52)
		P.Pill("pv.back", x + S(12), by, S(44), S(40), "", P.Back, { icon = "p_back" })
		if m.kind == "video" then P.Text("Видео · " .. m.frames .. " кадров", "medium", 12, x + w / 2, by + S(20), C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
		P.Pill("pv.del", x + w - S(56), by, S(44), S(40), "", function()
			if m.kind == "photo" then
				file.Delete(d .. "/" .. m.name)
			else
				file.Delete(d .. "/" .. m.name .. ".txt")
				for i = 1, m.frames do file.Delete(d .. "/" .. m.name .. "_" .. i .. ".jpg") end
			end
			P.Back()
			local top = P.Top()
			if top then top.media = P.Media() end
			P.Toast("Удалено")
		end, { icon = "trash", iconColor = C.red })
	end,
	key = function(st, k)
		local list = st.list
		if not list then return end
		if k == "left" or k == "right" then
			local i = math.Clamp(st.idx + (k == "left" and -1 or 1), 1, #list)
			if i ~= st.idx then st.idx, st.media, st.t0 = i, list[i], RealTime() end
			return true
		end
	end,
})

-- ------------------------------------------------------------------- Банки --
P.BankInfo = P.BankInfo or {}
net.Receive("nyrp.phone.bankinfo", function()
	local bank = net.ReadString()
	P.BankInfo[bank] = { balance = net.ReadDouble(), log = net.ReadTable() }
	local msg = net.ReadString()
	if msg ~= "" then P.Toast(msg) surface.PlaySound("nyrp/phone/notify.wav") end
end)

local function bankOp(op, bank, amount, number)
	net.Start("nyrp.phone.bank")
	net.WriteString(op)
	net.WriteString(bank)
	net.WriteDouble(amount or 0)
	net.WriteString(number or "")
	net.SendToServer()
end

local function askAmount(title, cb)
	P.Ask(title, "", { numeric = true, max = 7, hint = "Сумма в долларах" }, function(v)
		local n = tonumber(P.Digits(v))
		if n and n > 0 then cb(n) end
	end)
end

P.Register("bank", {
	enter = function(st) bankOp("info", st.app) end,
	draw = function(st, x, y, w, h)
		local a = P.StoreByID[st.app]
		surface.SetDrawColor(a.color.r * 0.25, a.color.g * 0.25, a.color.b * 0.25)
		surface.DrawRect(x, y - S(28), w, h + S(28))
		local cy = P.Header(a.name, x, y, w)
		-- карта со счётом
		local info = P.BankInfo[st.app]
		local cx, cw, ch = x + S(14), w - S(28), S(150)
		UI.RoundedRect(S(16), cx, cy, cw, ch, a.color)
		surface.SetDrawColor(255, 255, 255, 18)
		for i = 0, 6 do surface.DrawRect(cx + cw - S(40) - i * S(16), cy + S(10), S(8), ch - S(20)) end
		P.Icon(a.icon, cx + S(26), cy + S(26), S(22), color_white)
		P.Text(string.upper(a.name), "title", 13, cx + S(44), cy + S(26), color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		P.Text("Баланс", "medium", 12, cx + S(18), cy + S(66), Color(255, 255, 255, 180))
		P.Text(info and NYRP.Money.Format(info.balance) or "…", "title", 30, cx + S(18), cy + S(80), color_white)
		local num = P.Data().sim and P.Data().sim.number or ""
		P.Text("•••• " .. num:sub(-4), "semibold", 12, cx + S(18), cy + ch - S(22), Color(255, 255, 255, 200))
		cy = cy + ch + S(14)
		local bw = (w - S(28) - S(16)) / 3
		local ops = {
			{ "bk.dep", "Пополнить", "p_cash", function() askAmount("Пополнить из наличных", function(n) bankOp("deposit", st.app, n) end) end },
			{ "bk.wd", "Снять", "p_card", function() askAmount("Снять наличными", function(n) bankOp("withdraw", st.app, n) end) end },
			{ "bk.tr", "Перевод", "p_transfer", function()
				P.Ask("Номер получателя", "", { numeric = true, max = 10, hint = "10 цифр" }, function(numb)
					numb = P.Digits(numb)
					if numb == "" then return end
					askAmount("Сумма перевода на " .. P.FormatNumber(numb), function(n) bankOp("transfer", st.app, n, numb) end)
				end)
			end },
		}
		for i, o in ipairs(ops) do
			local bx = x + S(14) + (i - 1) * (bw + S(8))
			local f = P.Btn(o[1], bx, cy, bw, S(62), o[4])
			UI.RoundedRect(S(12), bx, cy, bw, S(62), f and C.cardHi or C.card)
			if f then UI.Outline(S(12), bx, cy, bw, S(62), C.yellow, S(2)) end
			P.Icon(o[3], bx + bw / 2, cy + S(22), S(20), color_white)
			P.Text(o[2], "semibold", 11, bx + bw / 2, cy + S(46), color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		cy = cy + S(76)
		P.Text("ИСТОРИЯ", "title", 12, x + S(18), cy, C.faint)
		cy = cy + S(22)
		local log = info and info.log or {}
		if #log == 0 then P.Text("Операций пока не было", "regular", 12, x + S(18), cy, C.dim) end
		for _, l in ipairs(log) do
			if cy > y + h - S(30) then break end
			P.Text(l.text, "medium", 12, x + S(18), cy, color_white)
			P.Text(P.DateText(l.day) .. " " .. (l.time or ""), "regular", 10, x + S(18), cy + S(15), C.faint)
			P.Text((l.amount > 0 and "+" or "") .. NYRP.Money.Format(l.amount), "bold", 13, x + w - S(18), cy + S(6), l.amount > 0 and C.green or color_white, TEXT_ALIGN_RIGHT)
			cy = cy + S(34)
		end
	end,
})

-- --------------------------------------------------------------------- Игры --
local function best(id) return (P.Settings().games or {})[id] or 0 end
local function saveBest(id, score)
	local s = P.Settings()
	s.games = s.games or {}
	if score > (s.games[id] or 0) then
		s.games[id] = score
		P.Save("settings")
		return true
	end
end

local function gameOverlay(x, y, w, h, title, sub, col)
	surface.SetDrawColor(0, 0, 0, 170)
	surface.DrawRect(x, y, w, h)
	P.Text(title, "title", 26, x + w / 2, y + h / 2 - S(16), col or C.yellow, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	P.Text(sub, "medium", 12, x + w / 2, y + h / 2 + S(14), color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- Subway Snake
local SN_W, SN_H = 14, 20
P.Register("game_snake", {
	enter = function(st) st.state = "ready" end,
	draw = function(st, x, y, w, h)
		local cy = P.Header("Subway Snake", x, y, w, Color(90, 210, 100))
		P.Text("Счёт: " .. (st.score or 0) .. "   Рекорд: " .. best("snake"), "semibold", 12, x + S(16), cy - S(6), C.dim)
		cy = cy + S(14)
		local cell = math.floor(math.min((w - S(20)) / SN_W, (y + h - cy - S(14)) / SN_H))
		local gx, gy = x + (w - cell * SN_W) / 2, cy
		UI.RoundedRect(S(6), gx - S(4), gy - S(4), cell * SN_W + S(8), cell * SN_H + S(8), Color(16, 30, 20))
		surface.SetDrawColor(255, 255, 255, 6)
		for i = 0, SN_W do surface.DrawRect(gx + i * cell, gy, 1, cell * SN_H) end
		if st.state == "play" then
			if RealTime() >= st.next then
				st.next = RealTime() + math.max(0.06, 0.15 - #st.body * 0.002)
				st.dir = st.want or st.dir
				local hd = st.body[1]
				local nx, ny = hd[1] + st.dir[1], hd[2] + st.dir[2]
				local dead = nx < 0 or ny < 0 or nx >= SN_W or ny >= SN_H
				for i = 1, #st.body - 1 do if st.body[i][1] == nx and st.body[i][2] == ny then dead = true end end
				if dead then
					st.state = "over"
					st.newBest = saveBest("snake", st.score)
					surface.PlaySound("nyrp/phone/busy.wav")
				else
					table.insert(st.body, 1, { nx, ny })
					if nx == st.food[1] and ny == st.food[2] then
						st.score = st.score + 10
						surface.PlaySound("nyrp/phone/key.wav")
						st.food = { math.random(0, SN_W - 1), math.random(0, SN_H - 1) }
					else
						table.remove(st.body)
					end
				end
			end
		end
		if st.food then
			UI.Circle(gx + st.food[1] * cell + cell / 2, gy + st.food[2] * cell + cell / 2, cell * 0.4, C.yellow)
		end
		for i, b in ipairs(st.body or {}) do
			local c = i == 1 and Color(120, 240, 130) or Color(60, 180, 80)
			UI.RoundedRect(S(3), gx + b[1] * cell + 1, gy + b[2] * cell + 1, cell - 2, cell - 2, c)
		end
		if st.state == "ready" then gameOverlay(gx, gy, cell * SN_W, cell * SN_H, "SUBWAY SNAKE", "Enter — старт, стрелки — поворот")
		elseif st.state == "over" then gameOverlay(gx, gy, cell * SN_W, cell * SN_H, st.newBest and "НОВЫЙ РЕКОРД!" or "КОНЕЦ", "Счёт " .. st.score .. " · Enter — ещё раз", st.newBest and C.green or C.red) end
	end,
	key = function(st, k)
		if k == "enter" and st.state ~= "play" then
			st.state, st.score, st.next = "play", 0, RealTime() + 0.3
			st.body = { { 7, 12 }, { 7, 13 }, { 7, 14 } }
			st.dir, st.want = { 0, -1 }, nil
			st.food = { math.random(0, SN_W - 1), math.random(0, 8) }
			return true
		end
		local dirs = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
		if dirs[k] and st.state == "play" then
			local d = dirs[k]
			if d[1] ~= -st.dir[1] or d[2] ~= -st.dir[2] then st.want = d end
			return true
		end
		return st.state == "play" and k == "enter"
	end,
})

-- 2048 Blocks
local TILE_COL = {
	[2] = Color(238, 228, 218), [4] = Color(237, 224, 200), [8] = Color(242, 177, 121), [16] = Color(245, 149, 99),
	[32] = Color(246, 124, 95), [64] = Color(246, 94, 59), [128] = Color(237, 207, 114), [256] = Color(237, 204, 97),
	[512] = Color(237, 200, 80), [1024] = Color(237, 197, 63), [2048] = Color(247, 198, 0),
}
local function g2048spawn(g)
	local free = {}
	for r = 1, 4 do for c = 1, 4 do if g[r][c] == 0 then free[#free + 1] = { r, c } end end end
	if #free == 0 then return end
	local p = free[math.random(#free)]
	g[p[1]][p[2]] = math.random() < 0.9 and 2 or 4
end
local function g2048slide(st, dr, dc)
	local g = st.grid
	local moved, gained = false, 0
	local function line(i)
		local cells = {}
		for k = 1, 4 do
			local r, c
			if dr ~= 0 then r = dr > 0 and 5 - k or k c = i else c = dc > 0 and 5 - k or k r = i end
			cells[k] = { r, c }
		end
		return cells
	end
	for i = 1, 4 do
		local cells = line(i)
		local vals = {}
		for _, rc in ipairs(cells) do if g[rc[1]][rc[2]] ~= 0 then vals[#vals + 1] = g[rc[1]][rc[2]] end end
		local out = {}
		local k = 1
		while k <= #vals do
			if vals[k + 1] and vals[k] == vals[k + 1] then
				out[#out + 1] = vals[k] * 2
				gained = gained + vals[k] * 2
				k = k + 2
			else
				out[#out + 1] = vals[k]
				k = k + 1
			end
		end
		for j, rc in ipairs(cells) do
			local v = out[j] or 0
			if g[rc[1]][rc[2]] ~= v then moved = true end
			g[rc[1]][rc[2]] = v
		end
	end
	if moved then
		st.score = st.score + gained
		g2048spawn(g)
		surface.PlaySound("nyrp/phone/key.wav")
		-- проверка конца игры
		local canMove = false
		for r = 1, 4 do for c = 1, 4 do
			local v = g[r][c]
			if v == 0 or (g[r + 1] and g[r + 1][c] == v) or g[r][c + 1] == v then canMove = true end
		end end
		if not canMove then
			st.state = "over"
			st.newBest = saveBest("g2048", st.score)
		end
	end
end

P.Register("game_g2048", {
	enter = function(st) st.state = "ready" end,
	draw = function(st, x, y, w, h)
		local cy = P.Header("2048 Blocks", x, y, w, Color(240, 170, 60))
		P.Text("Счёт: " .. (st.score or 0) .. "   Рекорд: " .. best("g2048"), "semibold", 12, x + S(16), cy - S(6), C.dim)
		cy = cy + S(20)
		local size = w - S(32)
		local gx, gy = x + S(16), cy
		UI.RoundedRect(S(10), gx, gy, size, size, Color(60, 54, 48))
		local ts = (size - S(10) * 5) / 4
		for r = 1, 4 do
			for c = 1, 4 do
				local v = st.grid and st.grid[r][c] or 0
				local tx, ty = gx + S(10) + (c - 1) * (ts + S(10)), gy + S(10) + (r - 1) * (ts + S(10))
				UI.RoundedRect(S(6), tx, ty, ts, ts, v > 0 and (TILE_COL[v] or Color(60, 58, 50)) or Color(80, 74, 66))
				if v > 0 then
					P.Text(tostring(v), "title", v >= 1000 and 20 or 26, tx + ts / 2, ty + ts / 2, v <= 4 and Color(110, 100, 90) or color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
			end
		end
		if st.state == "ready" then gameOverlay(gx, gy, size, size, "2048", "Enter — старт, стрелки — сдвиг")
		elseif st.state == "over" then gameOverlay(gx, gy, size, size, st.newBest and "НОВЫЙ РЕКОРД!" or "ХОДОВ НЕТ", "Счёт " .. st.score .. " · Enter — заново", st.newBest and C.green or C.red) end
		P.Text("Складывайте одинаковые кварталы, чтобы получить 2048.", "regular", 11, x + w / 2, gy + size + S(20), C.faint, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end,
	key = function(st, k)
		if k == "enter" and st.state ~= "play" then
			st.grid = { { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 } }
			st.score, st.state = 0, "play"
			g2048spawn(st.grid)
			g2048spawn(st.grid)
			return true
		end
		if st.state ~= "play" then return k == "enter" end
		if k == "up" then g2048slide(st, -1, 0) return true end
		if k == "down" then g2048slide(st, 1, 0) return true end
		if k == "left" then g2048slide(st, 0, -1) return true end
		if k == "right" then g2048slide(st, 0, 1) return true end
	end,
})

-- Yellow Rush: такси по трём полосам, уворачивается от машин
P.Register("game_taxi", {
	enter = function(st) st.state = "ready" end,
	draw = function(st, x, y, w, h)
		local cy = P.Header("Yellow Rush", x, y, w, C.yellow)
		P.Text("Очки: " .. math.floor(st.score or 0) .. "   Рекорд: " .. best("taxi"), "semibold", 12, x + S(16), cy - S(6), C.dim)
		cy = cy + S(14)
		local rw, rh = w - S(40), y + h - cy - S(14)
		local rx = x + S(20)
		surface.SetDrawColor(40, 42, 48)
		surface.DrawRect(rx, cy, rw, rh)
		local lane = rw / 3
		st.road = (st.road or 0) + FrameTime() * (st.state == "play" and st.speed or 0.3) * rh
		for i = 1, 2 do
			for k = -1, 8 do
				local ly = cy + ((k * S(50) + st.road) % (rh + S(50))) - S(50)
				surface.SetDrawColor(230, 230, 230, 120)
				surface.DrawRect(rx + lane * i - S(2), math.max(cy, ly), S(4), math.max(0, math.min(S(26), cy + rh - ly)))
			end
		end
		local carW, carH = lane * 0.55, S(54)
		local function car(l, cyy, col)
			local cx = rx + lane * (l - 0.5) - carW / 2
			UI.RoundedRect(S(8), cx, cyy, carW, carH, col)
			surface.SetDrawColor(20, 30, 40, 220)
			surface.DrawRect(cx + S(5), cyy + S(10), carW - S(10), S(12))
			surface.DrawRect(cx + S(5), cyy + carH - S(18), carW - S(10), S(8))
		end
		if st.state == "play" then
			local dt = FrameTime()
			st.score = st.score + dt * 10 * st.speed
			st.speed = st.speed + dt * 0.02
			st.spawn = st.spawn - dt
			if st.spawn <= 0 then
				st.spawn = math.max(0.35, 1.1 - st.speed * 0.25)
				st.cars[#st.cars + 1] = { lane = math.random(1, 3), y = -carH, col = HSVToColor(math.random(0, 360), 0.6, 0.8) }
			end
			st.lx = Lerp(dt * 16, st.lx or st.lane, st.lane)
			for i = #st.cars, 1, -1 do
				local c = st.cars[i]
				c.y = c.y + dt * st.speed * rh * 0.9
				if c.y > rh then table.remove(st.cars, i)
				elseif c.lane == st.lane and c.y + carH > rh - carH - S(14) and c.y < rh - S(14) then
					st.state = "over"
					st.newBest = saveBest("taxi", math.floor(st.score))
					surface.PlaySound("nyrp/phone/busy.wav")
				end
			end
		end
		render.SetScissorRect(rx, cy, rx + rw, cy + rh, true)
		for _, c in ipairs(st.cars or {}) do car(c.lane, cy + c.y, c.col) end
		if st.lane then
			local l = st.lx or st.lane
			local cx = rx + lane * (l - 0.5) - carW / 2
			local py = cy + rh - carH - S(14)
			UI.RoundedRect(S(8), cx, py, carW, carH, C.yellow)
			surface.SetDrawColor(20, 20, 20)
			for i = 0, 3 do surface.DrawRect(cx + i * carW / 4 + S(2), py + carH / 2 - S(3), carW / 8, S(6)) end
			surface.SetDrawColor(30, 40, 50, 220)
			surface.DrawRect(cx + S(5), py + S(8), carW - S(10), S(10))
		end
		render.SetScissorRect(0, 0, 0, 0, false)
		if st.state == "ready" then gameOverlay(rx, cy, rw, rh, "YELLOW RUSH", "Enter — старт, ← → — полоса")
		elseif st.state == "over" then gameOverlay(rx, cy, rw, rh, st.newBest and "НОВЫЙ РЕКОРД!" or "АВАРИЯ!", "Очки " .. math.floor(st.score) .. " · Enter — ещё раз", st.newBest and C.green or C.red) end
	end,
	key = function(st, k)
		if k == "enter" and st.state ~= "play" then
			st.state, st.score, st.speed, st.spawn, st.cars, st.lane, st.lx = "play", 0, 0.6, 0.5, {}, 2, 2
			return true
		end
		if st.state == "play" then
			if k == "left" then st.lane = math.max(1, st.lane - 1) return true end
			if k == "right" then st.lane = math.min(3, st.lane + 1) return true end
			if k == "up" or k == "down" or k == "enter" then return true end
		end
	end,
})
