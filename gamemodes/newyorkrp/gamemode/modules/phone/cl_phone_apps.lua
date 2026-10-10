--[[
	Приложения телефона: рабочий стол, Телефон, Заметки, Часы, Календарь, NY Store, Настройки.
	Камера/Фото — cl_phone_camera.lua, банки и игры — cl_phone_extra.lua.
]]

local UI = NYRP.UI
local P = NYRP.Phone
local C = P.Col

local function S(x) return UI.S(x) end

-- ------------------------------------------------------------ рабочий стол --
P.BaseApps = {
	{ id = "phone", name = "Телефон", icon = "p_phone", color = Color(52, 199, 89) },
	{ id = "notes", name = "Заметки", icon = "p_notes", color = Color(247, 198, 0) },
	{ id = "clock", name = "Часы", icon = "p_clock", color = Color(40, 40, 48) },
	{ id = "calendar", name = "Календарь", icon = "p_calendar", color = Color(232, 72, 64) },
	{ id = "camera", name = "Камера", icon = "p_camera", color = Color(90, 95, 110) },
	{ id = "photos", name = "Фото", icon = "p_photos", color = Color(255, 140, 60) },
	{ id = "store", name = "NY Store", icon = "p_store", color = Color(40, 120, 240) },
	{ id = "homes", name = "NY Homes", icon = "home", color = Color(46, 160, 100) },
	{ id = "settings", name = "Настройки", icon = "p_settings", color = Color(120, 124, 136) },
}

function P.AppList()
	local list = table.Copy(P.BaseApps)
	local apps = P.Data().apps or {}
	for _, a in ipairs(P.Store) do
		if apps[a.id] then list[#list + 1] = { id = a.id, name = a.name, icon = a.icon, color = a.color, store = true } end
	end
	return list
end

function P.OpenApp(id)
	local a = P.StoreByID[id]
	if a then
		P.Push(a.kind == "bank" and "bank" or ("game_" .. id), { app = id, from = "home." .. id })
	else
		P.Push(id, { from = "home." .. id })
	end
end

local function appIcon(a, cx, cy, size, f)
	local s = size * (f and 1.08 or 1)
	UI.RoundedRect(S(14), cx - s / 2, cy - s / 2, s, s, a.color)
	surface.SetDrawColor(255, 255, 255, 30)
	surface.DrawRect(cx - s / 2 + S(6), cy - s / 2 + S(1), s - S(12), S(1))
	P.Icon(a.icon, cx, cy, s * 0.52, color_white)
	if f then UI.Outline(S(14), cx - s / 2 - S(3), cy - s / 2 - S(3), s + S(6), s + S(6), C.yellow, S(2)) end
end

P.Register("home", {
	draw = function(st, x, y, w, h)
		P.Wallpaper(x, y - S(28), w, h + S(28))
		-- виджет даты/времени
		P.Text(NYRP.Time.Format(), "titlelight", 46, x + S(20), y + S(8), color_white)
		local d, m, wd = P.Date()
		P.Text(P.WeekDays[wd] .. ", " .. d .. " " .. P.MonthGen[m], "semibold", 14, x + S(22), y + S(64), Color(255, 255, 255, 220))
		local apps = P.AppList()
		local cols, size = 4, S(52)
		local cw = (w - S(24)) / cols
		local dock = {}
		local grid = {}
		for i, a in ipairs(apps) do
			if i <= 4 then dock[#dock + 1] = a else grid[#grid + 1] = a end
		end
		-- сетка
		local gy = y + S(110)
		for i, a in ipairs(grid) do
			local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
			local cx, cy = x + S(12) + cw * col + cw / 2, gy + row * S(92) + size / 2
			local f = P.Btn("home." .. a.id, cx - cw / 2, cy - size / 2 - S(4), cw, size + S(26), function() P.OpenApp(a.id) end)
			appIcon(a, cx, cy, size, f)
			P.Text(a.name, "semibold", 11, cx + 1, cy + size / 2 + S(11) + 1, Color(0, 0, 0, 160), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			P.Text(a.name, "semibold", 11, cx, cy + size / 2 + S(11), color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		-- док внизу
		local dy = y + h - S(96)
		UI.RoundedRect(S(26), x + S(10), dy, w - S(20), S(80), Color(255, 255, 255, 40))
		for i, a in ipairs(dock) do
			local cx, cy = x + S(12) + cw * (i - 1) + cw / 2, dy + S(40)
			local f = P.Btn("home." .. a.id, cx - cw / 2, dy, cw, S(80), function() P.OpenApp(a.id) end)
			appIcon(a, cx, cy, size, f)
		end
		-- пропущенные вызовы — значок на «Телефоне»
		local missed = 0
		for _, r in ipairs(P.Data().recents or {}) do
			if r.dir == "in" and not r.ok then missed = missed + 1 else break end
		end
		if missed > 0 then
			local cx, cy = x + S(12) + cw / 2 + size / 2 - S(4), dy + S(40) - size / 2 + S(4)
			UI.Circle(cx, cy, S(9), C.red)
			P.Text(tostring(missed), "bold", 11, cx, cy, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end,
	key = function(st, k)
		if k == "back" then return true end
	end,
})

-- ------------------------------------------------------------------ вкладки --
local function tabs(st, list, x, y, w)
	st.tab = st.tab or 1
	local tw = (w - S(24)) / #list
	UI.RoundedRect(S(12), x + S(12), y, w - S(24), S(36), Color(255, 255, 255, 12))
	for i, t in ipairs(list) do
		local bx = x + S(12) + (i - 1) * tw
		local f = P.Btn("tab." .. i, bx, y, tw, S(36), function() st.tab = i st.scroll = 0 end)
		if st.tab == i then UI.RoundedRect(S(10), bx + S(3), y + S(3), tw - S(6), S(30), Color(255, 255, 255, 34)) end
		if f then UI.Outline(S(10), bx + S(3), y + S(3), tw - S(6), S(30), C.yellow, S(2)) end
		P.Icon(t[1], bx + S(18), y + S(18), S(14), st.tab == i and C.yellow or C.dim)
		P.Text(t[2], "semibold", 12, bx + S(30), y + S(18), st.tab == i and color_white or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	return y + S(46)
end

local function fmtMinute(t)
	if not t then return "" end
	local day = math.floor(t / 1440)
	local hm = string.format("%02d:%02d", math.floor(t % 1440 / 60), t % 60)
	if day == P.DayIndex() then return hm end
	if day == P.DayIndex() - 1 then return "вчера" end
	return P.DateText(day)
end

-- ------------------------------------------------------------------ Телефон --
local function dial(number)
	number = P.Digits(number)
	if number == "" then return end
	-- экстренные номера: диспетчер 911 (выбор службы и причины)
	if number == "911" or number == "112" or number == "999" then
		surface.PlaySound("nyrp/fx/dispatch.wav")
		P.Push("e911", { from = "dial911" })
		return
	end
	net.Start("nyrp.phone.call")
	net.WriteString(number)
	net.SendToServer()
end
P.Dial = dial

local function contactMenu(i)
	local c = P.Data().contacts[i]
	if not c then return end
	P.Push("contact", { idx = i, from = "row.c." .. i })
end

P.Register("phone", {
	draw = function(st, x, y, w, h)
		local cy = P.Header("Телефон", x, y, w)
		cy = tabs(st, { { "p_contacts", "Контакты" }, { "p_recent", "Недавние" }, { "p_keypad", "Набор" } }, x, cy, w)
		local d = P.Data()
		if st.tab == 1 then
			-- «Мой номер» + добавить
			UI.RoundedRect(S(10), x + S(12), cy, w - S(24), S(40), Color(247, 198, 0, 24))
			P.Text("Мой номер", "medium", 11, x + S(24), cy + S(12), C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			P.Text(P.FormatNumber(d.sim and d.sim.number or ""), "bold", 14, x + S(24), cy + S(28), C.yellow, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			P.Pill("c.add", x + w - S(56), cy + S(5), S(36), S(30), "", function()
				P.Ask("Имя контакта", "", { max = 40 }, function(name)
					if name == "" then return end
					P.Ask("Номер телефона", "", { numeric = true, max = 10, hint = "10 цифр, например 2125550142" }, function(num)
						num = P.Digits(num)
						if num == "" then return end
						d.contacts = d.contacts or {}
						table.insert(d.contacts, { name = name, number = num })
						table.sort(d.contacts, function(a, b) return a.name < b.name end)
						P.Save("contacts")
						P.Toast("Контакт сохранён")
					end)
				end)
			end, { icon = "plus" })
			cy = cy + S(48)
			local list = d.contacts or {}
			if #list == 0 then
				P.Text("Контактов пока нет", "medium", 13, x + w / 2, cy + S(60), C.faint, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				return
			end
			P.List(st, "row.c.", #list, x + S(12), cy, w - S(18), y + h - cy - S(16), S(52), function(i, rx, ry, rw, rh, f)
				P.Row(rx, ry, rw, rh, f, "p_contacts", list[i].name, P.FormatNumber(list[i].number))
			end, contactMenu)
		elseif st.tab == 2 then
			local list = d.recents or {}
			if #list == 0 then
				P.Text("Звонков ещё не было", "medium", 13, x + w / 2, cy + S(60), C.faint, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				return
			end
			P.List(st, "row.r.", #list, x + S(12), cy, w - S(18), y + h - cy - S(16), S(52), function(i, rx, ry, rw, rh, f)
				local r = list[i]
				local missed = r.dir == "in" and not r.ok
				P.Row(rx, ry, rw, rh, f, r.dir == "in" and "p_in" or "p_out", P.Who(r.number),
					missed and "Пропущенный" or (r.dir == "in" and "Входящий" or "Исходящий") .. (r.ok and "" or " · нет ответа"),
					fmtMinute(r.t), missed and C.red or (r.dir == "in" and C.green or C.yellow))
			end, function(i) dial(list[i].number) end)
		else
			-- клавиатура набора
			st.num = st.num or ""
			P.Text(st.num == "" and "Введите номер" or P.FormatNumber(st.num), st.num == "" and "medium" or "bold", st.num == "" and 15 or 22,
				x + w / 2, cy + S(22), st.num == "" and C.faint or color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			local name = st.num ~= "" and P.ContactName(st.num)
			if name then P.Text(name, "medium", 12, x + w / 2, cy + S(44), C.yellow, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
			local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#" }
			local subs = { "", "ABC", "DEF", "GHI", "JKL", "MNO", "PQRS", "TUV", "WXYZ", "", "+", "" }
			local bs = S(56)
			local gap = S(14)
			local gx = x + w / 2 - bs * 1.5 - gap
			local ky = cy + S(58)
			for i, k in ipairs(keys) do
				local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
				local bx, by = gx + col * (bs + gap), ky + row * (bs + S(8))
				local f = P.Btn("key." .. i, bx, by, bs, bs, function()
					surface.PlaySound("nyrp/phone/dtmf_" .. (k == "*" and "star" or k == "#" and "hash" or k) .. ".wav")
					if #st.num < 12 and k:match("%d") then st.num = st.num .. k end
				end)
				UI.Circle(bx + bs / 2, by + bs / 2, bs / 2, f and Color(255, 255, 255, 64) or Color(255, 255, 255, 22))
				P.Text(k, "titlemed", 24, bx + bs / 2, by + bs / 2 - (subs[i] ~= "" and S(5) or 0), color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				if subs[i] ~= "" then P.Text(subs[i], "bold", 8, bx + bs / 2, by + bs / 2 + S(13), C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
			end
			local by = ky + 4 * (bs + S(8)) + S(4)
			local f = P.Btn("key.call", x + w / 2 - bs / 2, by, bs, bs, function() dial(st.num) end)
			UI.Circle(x + w / 2, by + bs / 2, bs / 2 * (f and 1.08 or 1), C.green)
			P.Icon("p_call", x + w / 2, by + bs / 2, S(24), color_white)
			if st.num ~= "" then
				local f2 = P.Btn("key.del", x + w / 2 + bs + gap, by + S(8), S(40), S(40), function() st.num = st.num:sub(1, -2) end)
				P.Icon("p_back", x + w / 2 + bs + gap + S(20), by + S(28), S(20), f2 and C.yellow or C.dim)
			end
		end
	end,
	key = function(st, k)
		-- в наборе цифры можно печатать и с клавиатуры (цифровой ряд)
		return false
	end,
})

-- цифры с клавиатуры в наборе номера
hook.Add("Think", "nyrp.phone.digits", function()
	if not P.Open or P.Prompt then return end
	local top = P.Top()
	if not top or top.name ~= "phone" or top.tab ~= 3 then return end
	top.keys = top.keys or {}
	for d = 0, 9 do
		local down = input.IsKeyDown(KEY_0 + d) or input.IsKeyDown(KEY_PAD_0 + d)
		if down and not top.keys[d] and #(top.num or "") < 12 then
			top.num = (top.num or "") .. d
			surface.PlaySound("nyrp/phone/dtmf_" .. d .. ".wav")
		end
		top.keys[d] = down
	end
end)

P.Register("contact", {
	draw = function(st, x, y, w, h)
		local d = P.Data()
		local c = (d.contacts or {})[st.idx]
		if not c then P.Back() return end
		local cy = P.Header("Контакт", x, y, w)
		UI.Circle(x + w / 2, cy + S(50), S(44), Color(255, 255, 255, 24))
		P.Text(utf8.char(utf8.codepoint(c.name, 1) or 63):upper(), "title", 36, x + w / 2, cy + S(50), C.yellow, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		P.Text(c.name, "bold", 20, x + w / 2, cy + S(114), color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		P.Text(P.FormatNumber(c.number), "medium", 14, x + w / 2, cy + S(138), C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		local bw = w - S(40)
		local by = cy + S(170)
		P.Pill("ct.call", x + S(20), by, bw, S(44), "Позвонить", function() dial(c.number) end, { solid = true, color = C.green, icon = "p_call" })
		P.Pill("ct.name", x + S(20), by + S(52), bw, S(44), "Изменить имя", function()
			P.Ask("Имя контакта", c.name, { max = 40 }, function(v) if v ~= "" then c.name = v P.Save("contacts") end end)
		end, { icon = "p_edit" })
		P.Pill("ct.num", x + S(20), by + S(104), bw, S(44), "Изменить номер", function()
			P.Ask("Номер", c.number, { numeric = true, max = 10 }, function(v) v = P.Digits(v) if v ~= "" then c.number = v P.Save("contacts") end end)
		end, { icon = "p_keypad" })
		P.Pill("ct.del", x + S(20), by + S(156), bw, S(44), "Удалить контакт", function()
			table.remove(d.contacts, st.idx)
			P.Save("contacts")
			P.Back()
			P.Toast("Контакт удалён")
		end, { icon = "trash", textColor = C.red, iconColor = C.red })
	end,
})

-- ------------------------------------------------------------------ Заметки --
P.Register("notes", {
	draw = function(st, x, y, w, h)
		local cy = P.Header("Заметки", x, y, w, C.yellow)
		local d = P.Data()
		d.notes = d.notes or {}
		P.Pill("n.new", x + S(12), cy, w - S(24), S(40), "Новая заметка", function()
			P.Ask("Заголовок", "", { max = 60 }, function(title)
				P.Ask("Текст заметки", "", { max = 2000 }, function(text)
					if title == "" and text == "" then return end
					table.insert(d.notes, 1, { title = title ~= "" and title or "Без названия", text = text, t = P.DayIndex() * 1440 + math.floor(NYRP.Time.Hour() * 60) })
					P.Save("notes")
					P.Toast("Заметка сохранена")
				end)
			end)
		end, { icon = "plus" })
		cy = cy + S(50)
		if #d.notes == 0 then
			P.Text("Здесь будут ваши заметки", "medium", 13, x + w / 2, cy + S(60), C.faint, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			return
		end
		P.List(st, "row.n.", #d.notes, x + S(12), cy, w - S(18), y + h - cy - S(16), S(58), function(i, rx, ry, rw, rh, f)
			local n = d.notes[i]
			local preview = string.Replace(n.text or "", "\n", " ")
			if utf8.len(preview) and utf8.len(preview) > 30 then preview = preview:sub(1, utf8.offset(preview, 31) - 1) .. "…" end
			P.Row(rx, ry, rw, rh, f, "p_notes", n.title, preview, fmtMinute(n.t))
		end, function(i) P.Push("note", { idx = i, from = "row.n." .. i }) end)
	end,
})

P.Register("note", {
	draw = function(st, x, y, w, h)
		local d = P.Data()
		local n = (d.notes or {})[st.idx]
		if not n then P.Back() return end
		local cy = P.Header(n.title, x, y, w, C.yellow)
		P.Text(fmtMinute(n.t), "medium", 11, x + S(20), cy - S(4), C.faint)
		local lines = {}
		for _, para in ipairs(string.Explode("\n", n.text or "")) do
			for _, l in ipairs(UI.Wrap(para, NYRP.Font("regular", 14), w - S(40))) do lines[#lines + 1] = l end
		end
		st.off = st.off or 0
		local maxLines = math.floor((h - (cy - y) - S(120)) / S(20))
		st.off = math.Clamp(st.off, 0, math.max(0, #lines - maxLines))
		for i = 1, maxLines do
			local l = lines[i + st.off]
			if l then P.Text(l, "regular", 14, x + S(20), cy + S(14) + (i - 1) * S(20), color_white) end
		end
		local by = y + h - S(64)
		local bw = (w - S(48)) / 2
		P.Pill("nt.edit", x + S(16), by, bw, S(42), "Изменить", function()
			P.Ask("Текст заметки", n.text, { max = 2000 }, function(v) n.text = v P.Save("notes") end)
		end, { icon = "p_edit" })
		P.Pill("nt.del", x + S(32) + bw, by, bw, S(42), "Удалить", function()
			table.remove(d.notes, st.idx)
			P.Save("notes")
			P.Back()
		end, { icon = "trash", textColor = C.red, iconColor = C.red })
	end,
	key = function(st, k)
		if k == "up" and (st.off or 0) > 0 then st.off = st.off - 1 return true end
		if k == "down" and P.Focus ~= "nt.edit" and P.Focus ~= "nt.del" then st.off = (st.off or 0) + 1 return false end
	end,
})

-- --------------------------------------------------------------------- Часы --
local function parseTime(s)
	local h, m = string.match(s or "", "^%s*(%d%d?)%D?(%d%d)%s*$")
	h, m = tonumber(h), tonumber(m)
	if h and m and h < 24 and m < 60 then return h, m end
end

P.Register("clock", {
	draw = function(st, x, y, w, h)
		local cy = P.Header("Часы", x, y, w)
		cy = tabs(st, { { "p_alarm", "Будильник" }, { "p_stopwatch", "Секундомер" } }, x, cy, w)
		local d = P.Data()
		d.alarms = d.alarms or {}
		if st.tab == 1 then
			P.Pill("al.add", x + S(12), cy, w - S(24), S(40), "Добавить будильник", function()
				P.Ask("Время (ЧЧ:ММ)", "07:00", { numeric = true, pattern = "[%d:]", max = 5 }, function(v)
					local hh, mm = parseTime(v)
					if not hh then P.Toast("Неверное время") return end
					P.Ask("Подпись", "", { max = 30, hint = "Например: на работу" }, function(label)
						table.insert(d.alarms, { h = hh, m = mm, on = true, label = label })
						table.sort(d.alarms, function(a, b) return a.h * 60 + a.m < b.h * 60 + b.m end)
						P.Save("alarms")
						P.Toast("Будильник на " .. string.format("%02d:%02d", hh, mm))
					end)
				end)
			end, { icon = "plus" })
			cy = cy + S(50)
			P.Text("Сейчас " .. NYRP.Time.Format() .. " · игровое время", "medium", 11, x + w / 2, cy, C.faint, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
			cy = cy + S(22)
			if #d.alarms == 0 then
				P.Text("Будильников нет", "medium", 13, x + w / 2, cy + S(50), C.faint, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				return
			end
			P.List(st, "row.a.", #d.alarms, x + S(12), cy, w - S(18), y + h - cy - S(16), S(64), function(i, rx, ry, rw, rh, f)
				local a = d.alarms[i]
				UI.RoundedRect(S(12), rx, ry, rw - S(6), rh, f and C.cardHi or C.card)
				if f then UI.Outline(S(12), rx, ry, rw - S(6), rh, UI.Alpha(C.yellow, 200), S(2)) end
				P.Text(string.format("%02d:%02d", a.h, a.m), "titlemed", 30, rx + S(14), ry + rh / 2 - S(2), a.on and color_white or C.faint, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				P.Text(a.label ~= "" and a.label or "Будильник", "medium", 11, rx + S(100), ry + rh / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				-- переключатель
				local tx, ty = rx + rw - S(62), ry + rh / 2 - S(12)
				UI.RoundedRect(S(12), tx, ty, S(44), S(24), a.on and C.green or Color(255, 255, 255, 40))
				UI.Circle(tx + (a.on and S(32) or S(12)), ty + S(12), S(10), color_white)
			end, function(i)
				st.sel = i
				P.Push("alarm_edit", { idx = i, from = "row.a." .. i })
			end)
		else
			-- секундомер (в реальном времени)
			local t = st.swRun and (st.swAcc or 0) + RealTime() - st.swStart or (st.swAcc or 0)
			local ms = math.floor((t % 1) * 100)
			P.Text(string.format("%02d:%02d,%02d", math.floor(t / 60), math.floor(t % 60), ms), "titlelight", 50, x + w / 2, cy + S(50), color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			local bw = (w - S(48)) / 2
			local by = cy + S(100)
			P.Pill("sw.lap", x + S(16), by, bw, S(44), st.swRun and "Круг" or "Сброс", function()
				if st.swRun then
					st.laps = st.laps or {}
					table.insert(st.laps, 1, t)
				else
					st.swAcc, st.laps = 0, {}
				end
			end)
			P.Pill("sw.go", x + S(32) + bw, by, bw, S(44), st.swRun and "Стоп" or "Старт", function()
				if st.swRun then st.swAcc = t st.swRun = false else st.swStart = RealTime() st.swRun = true end
			end, { solid = true, color = st.swRun and C.red or C.green })
			local ly = by + S(60)
			for i, lap in ipairs(st.laps or {}) do
				if ly > y + h - S(30) then break end
				P.Text("Круг " .. (#st.laps - i + 1), "medium", 13, x + S(24), ly, C.dim)
				P.Text(string.format("%02d:%02d,%02d", math.floor(lap / 60), math.floor(lap % 60), math.floor((lap % 1) * 100)), "semibold", 13, x + w - S(24), ly, color_white, TEXT_ALIGN_RIGHT)
				ly = ly + S(24)
			end
		end
	end,
})

P.Register("alarm_edit", {
	draw = function(st, x, y, w, h)
		local d = P.Data()
		local a = (d.alarms or {})[st.idx]
		if not a then P.Back() return end
		local cy = P.Header("Будильник", x, y, w)
		P.Text(string.format("%02d:%02d", a.h, a.m), "titlelight", 60, x + w / 2, cy + S(50), color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		local bw = w - S(40)
		local by = cy + S(110)
		P.Pill("ae.on", x + S(20), by, bw, S(44), a.on and "Выключить" or "Включить", function() a.on = not a.on P.Save("alarms") end,
			{ solid = not a.on, color = C.green, icon = "p_alarm" })
		P.Pill("ae.time", x + S(20), by + S(52), bw, S(44), "Изменить время", function()
			P.Ask("Время (ЧЧ:ММ)", string.format("%02d:%02d", a.h, a.m), { numeric = true, pattern = "[%d:]", max = 5 }, function(v)
				local hh, mm = parseTime(v)
				if hh then a.h, a.m = hh, mm P.Save("alarms") end
			end)
		end, { icon = "p_clock" })
		P.Pill("ae.label", x + S(20), by + S(104), bw, S(44), "Подпись", function()
			P.Ask("Подпись", a.label, { max = 30 }, function(v) a.label = v P.Save("alarms") end)
		end, { icon = "p_edit" })
		P.Pill("ae.del", x + S(20), by + S(156), bw, S(44), "Удалить", function()
			table.remove(d.alarms, st.idx)
			P.Save("alarms")
			P.Back()
		end, { icon = "trash", textColor = C.red, iconColor = C.red })
	end,
})

-- ---------------------------------------------------------------- Календарь --
P.Register("calendar", {
	enter = function(st)
		st.day = P.DayIndex()
	end,
	draw = function(st, x, y, w, h)
		local cy = P.Header("Календарь", x, y, w, C.red)
		local d = P.Data()
		d.events = d.events or {}
		st.day = st.day or P.DayIndex()
		local today = P.DayIndex()
		local dd, mm = P.Date(st.day)
		-- первый день месяца выбранного дня
		local first = st.day - (dd - 1)
		local _, _, wd1 = P.Date(first)
		P.Text(P.MonthNames[mm], "title", 20, x + S(20), cy, color_white)
		cy = cy + S(32)
		local cw = (w - S(24)) / 7
		for i, wn in ipairs(P.WeekDays) do
			P.Text(wn, "bold", 11, x + S(12) + cw * (i - 0.5), cy, i >= 6 and C.red or C.faint, TEXT_ALIGN_CENTER)
		end
		cy = cy + S(20)
		local has = {}
		for _, e in ipairs(d.events) do has[e.day] = true end
		for n = 1, P.MonthDays[mm] do
			local idx = first + n - 1
			local cell = wd1 - 1 + n - 1
			local col, row = cell % 7, math.floor(cell / 7)
			local bx, by = x + S(12) + cw * col, cy + row * S(36)
			local f = P.Btn("day." .. idx, bx + S(2), by, cw - S(4), S(32), function() st.day = idx P.Push("day", { day = idx, from = "day." .. idx }) end)
			if idx == today then UI.Circle(bx + cw / 2, by + S(16), S(15), C.red) end
			if f then UI.Ring(bx + cw / 2, by + S(16), S(16), C.yellow) end
			P.Text(tostring(n), idx == today and "bold" or "medium", 13, bx + cw / 2, by + S(16), idx < today and C.faint or color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			if has[idx] then UI.Circle(bx + cw / 2, by + S(29), S(2), C.yellow) end
			if f then st.day = idx end
		end
		-- ближайшие события
		local ly = cy + 6 * S(36) + S(4)
		P.Text("БЛИЖАЙШИЕ СОБЫТИЯ", "title", 12, x + S(20), ly, C.faint)
		ly = ly + S(22)
		local up = {}
		for _, e in ipairs(d.events) do if e.day >= today then up[#up + 1] = e end end
		table.sort(up, function(a, b) return a.day < b.day end)
		if #up == 0 then P.Text("Нет событий — выберите день, чтобы добавить", "regular", 12, x + S(20), ly, C.dim) end
		for i = 1, math.min(#up, 4) do
			P.Text(P.DateText(up[i].day), "semibold", 12, x + S(20), ly, C.yellow)
			P.Text(up[i].text, "regular", 12, x + S(110), ly, color_white)
			ly = ly + S(20)
		end
	end,
	enterFocus = true,
})

P.Register("day", {
	draw = function(st, x, y, w, h)
		local d = P.Data()
		local _, _, wd = P.Date(st.day)
		local cy = P.Header(P.DateText(st.day) .. ", " .. P.WeekDays[wd], x, y, w, C.red)
		P.Pill("ev.add", x + S(12), cy, w - S(24), S(40), "Добавить событие", function()
			P.Ask("Событие на " .. P.DateText(st.day), "", { max = 120 }, function(v)
				if v == "" then return end
				table.insert(d.events, { day = st.day, text = v })
				P.Save("events")
			end)
		end, { icon = "plus" })
		cy = cy + S(50)
		local list, map = {}, {}
		for i, e in ipairs(d.events or {}) do if e.day == st.day then list[#list + 1] = e map[#list] = i end end
		if #list == 0 then
			P.Text("В этот день ничего не запланировано", "medium", 13, x + w / 2, cy + S(50), C.faint, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			return
		end
		P.List(st, "row.e.", #list, x + S(12), cy, w - S(18), y + h - cy - S(16), S(52), function(i, rx, ry, rw, rh, f)
			P.Row(rx, ry, rw, rh, f, "p_calendar", list[i].text, "Enter — удалить", nil, C.red)
		end, function(i)
			table.remove(d.events, map[i])
			P.Save("events")
			P.Toast("Событие удалено")
		end)
	end,
})

-- ---------------------------------------------------------------- NY Store --
P.Register("store", {
	draw = function(st, x, y, w, h)
		local cy = P.Header("NY Store", x, y, w, Color(90, 160, 255))
		local d = P.Data()
		d.apps = d.apps or {}
		P.List(st, "row.s.", #P.Store, x + S(12), cy, w - S(18), y + h - cy - S(16), S(84), function(i, rx, ry, rw, rh, f)
			local a = P.Store[i]
			UI.RoundedRect(S(12), rx, ry, rw - S(6), rh, f and C.cardHi or C.card)
			if f then UI.Outline(S(12), rx, ry, rw - S(6), rh, UI.Alpha(C.yellow, 200), S(2)) end
			UI.RoundedRect(S(12), rx + S(10), ry + S(12), S(52), S(52), a.color)
			P.Icon(a.icon, rx + S(36), ry + S(38), S(28), color_white)
			P.Text(a.name, "bold", 14, rx + S(72), ry + S(14), color_white)
			P.Text(a.kind == "bank" and "Финансы" or "Игры", "medium", 11, rx + S(72), ry + S(32), C.dim)
			local lines = UI.Wrap(a.desc, NYRP.Font("regular", 11), rw - S(170))
			P.Text(lines[1] or "", "regular", 11, rx + S(72), ry + S(50), C.faint)
			local installing = st.inst == a.id
			local btn = d.apps[a.id] and "ОТКРЫТЬ" or (installing and "..." or "ЗАГРУЗИТЬ")
			UI.RoundedRect(S(12), rx + rw - S(92), ry + rh / 2 - S(13), S(78), S(26), d.apps[a.id] and Color(255, 255, 255, 30) or Color(40, 120, 240))
			if installing then
				local p = math.Clamp((RealTime() - st.instT) / 2, 0, 1)
				UI.RoundedRect(S(12), rx + rw - S(92), ry + rh / 2 - S(13), S(78) * p, S(26), Color(80, 170, 255))
			end
			P.Text(btn, "bold", 11, rx + rw - S(53), ry + rh / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end, function(i)
			local a = P.Store[i]
			if d.apps[a.id] then P.OpenApp(a.id) return end
			if st.inst then return end
			st.inst, st.instT = a.id, RealTime()
			timer.Simple(2, function()
				st.inst = nil
				local dd = P.Data()
				dd.apps = dd.apps or {}
				dd.apps[a.id] = true
				P.Save("apps")
				surface.PlaySound("nyrp/phone/notify.wav")
				P.Toast(a.name .. " установлено")
			end)
		end)
	end,
})

-- ---------------------------------------------------------------- Настройки --
local function choose(title, list, cur, onPick, preview)
	P.Push("choose", { title = title, list = list, cur = cur, pick = onPick, preview = preview })
end

P.Register("choose", {
	draw = function(st, x, y, w, h)
		local cy = P.Header(st.title, x, y, w)
		P.List(st, "row.ch.", #st.list, x + S(12), cy, w - S(18), y + h - cy - S(16), S(52), function(i, rx, ry, rw, rh, f)
			P.Row(rx, ry, rw, rh, f, i == st.cur and "check" or nil, st.list[i], nil, nil)
			if i == st.cur then P.Icon("check", rx + rw - S(30), ry + rh / 2, S(16), C.yellow) end
			if f and st.preview and st.lastPrev ~= i then st.lastPrev = i st.preview(i) end
		end, function(i)
			st.cur = i
			st.pick(i)
			P.Toast("Сохранено")
		end)
	end,
})

P.Register("walls", {
	draw = function(st, x, y, w, h)
		local cy = P.Header("Обои", x, y, w)
		local s = P.Settings()
		local tw, th = (w - S(48)) / 3, (w - S(48)) / 3 * 16 / 9
		for i, wall in ipairs(P.Walls) do
			local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
			local bx, by = x + S(12) + col * (tw + S(12)), cy + row * (th + S(12))
			local f = P.Btn("wall." .. i, bx, by, tw, th, function()
				s.wall = i
				P.Save("settings")
				P.Toast("Обои установлены")
			end)
			surface.SetMaterial(UI.Mat("nyrp/phone/" .. wall .. ".png"))
			surface.SetDrawColor(255, 255, 255)
			surface.DrawTexturedRect(bx, by, tw, th)
			if s.wall == i then UI.Outline(S(4), bx - S(2), by - S(2), tw + S(4), th + S(4), color_white, S(2)) end
			if f then UI.Outline(S(6), bx - S(4), by - S(4), tw + S(8), th + S(8), C.yellow, S(3)) end
		end
	end,
})

P.Register("settings", {
	draw = function(st, x, y, w, h)
		local cy = P.Header("Настройки", x, y, w)
		local s = P.Settings()
		local d = P.Data()
		local myChar = LocalPlayer():GetNW2Int("nyrp.charID", -1)
		local rows = {
			{ "p_photos", "Обои", "Выбрать изображение", function() P.Push("walls", { from = "row.st.1" }) end },
			{ "bell", "Мелодия звонка", (P.Rings[s.ring or 1] or P.Rings[1])[2], function()
				local names = {}
				for i, r in ipairs(P.Rings) do names[i] = r[2] end
				choose("Мелодия звонка", names, s.ring or 1, function(i) s.ring = i P.Save("settings") end,
					function(i) surface.PlaySound("nyrp/phone/" .. P.Rings[i][1] .. ".wav") end)
			end },
			{ "p_alarm", "Звук будильника", (P.Alarms[s.alarm or 1] or P.Alarms[1])[2], function()
				local names = {}
				for i, r in ipairs(P.Alarms) do names[i] = r[2] end
				choose("Звук будильника", names, s.alarm or 1, function(i) s.alarm = i P.Save("settings") end,
					function(i) surface.PlaySound("nyrp/phone/" .. P.Alarms[i][1] .. ".wav") end)
			end },
			{ "lock", "Код-пароль", s.pin and "Включён" or "Выключен", function()
				if s.pin then
					s.pin = nil
					P.Save("settings")
					P.Toast("Код-пароль выключен")
				else
					P.Ask("Новый код (4–6 цифр)", "", { numeric = true, max = 6 }, function(v)
						v = P.Digits(v)
						if #v < 4 then P.Toast("Нужно минимум 4 цифры") return end
						P.Ask("Повторите код", "", { numeric = true, max = 6 }, function(v2)
							if P.Digits(v2) ~= v then P.Toast("Коды не совпадают") return end
							s.pin = v
							P.Save("settings")
							P.Toast("Код-пароль установлен")
						end)
					end)
				end
			end },
			{ "p_face", "Face ID", s.face and (s.face == myChar and "Ваше лицо" or "Другой человек") or "Не настроен", function()
				if s.face then
					s.face = nil
					P.Save("settings")
					P.Toast("Face ID выключен")
				else
					s.face = myChar
					P.Save("settings")
					surface.PlaySound("nyrp/phone/unlock.wav")
					P.Toast("Лицо сохранено")
				end
			end },
			{ "info", "О телефоне", "Номер " .. P.FormatNumber(d.sim and d.sim.number or ""), function() P.Toast("Серийный № " .. string.upper(d.serial or "—")) end },
		}
		P.List(st, "row.st.", #rows, x + S(12), cy, w - S(18), y + h - cy - S(16), S(56), function(i, rx, ry, rw, rh, f)
			P.Row(rx, ry, rw, rh, f, rows[i][1], rows[i][2], rows[i][3])
		end, function(i) rows[i][4]() end)
	end,
})
