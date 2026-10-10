--[[
	Справка: /help (/помощь, /справка), консоль nyrp_help, кнопка «СПРАВКА» в меню паузы.
	Вкладки: «Клавиши» (все бинды режима, с текущими назначенными клавишами), «Команды» (чат-команды,
	пометка «админ»), «Службы» (роли и профессии — как вступить), «О режиме». Поиск по текущей вкладке.
	Другие модули могут дополнить справку: NYRP.Help.AddCommand("/cmd", "<аргументы>", "описание", isAdmin, "Раздел"),
	NYRP.Help.AddKey("Клавиша", "что делает", "Раздел").
]]

NYRP.Help = NYRP.Help or {}
local H = NYRP.Help
local UI = NYRP.UI

-- ---------------------------------------------------------------- данные --
local function key(cvar, def)
	local cv = GetConVar(cvar)
	local code = cv and cv:GetInt() or 0
	if code and code > 0 then return string.upper(input.GetKeyName(code) or def) end
	return def
end
local function bind(b, def)
	local k = input.LookupBinding(b)
	return k and string.upper(k) or def
end

-- клавиши: { клавиша (строка или функция), описание, раздел }
H.Keys = H.Keys or {}
local BASE_KEYS = {
	{ function() return bind("+forward", "W") .. " " .. bind("+moveleft", "A") .. " " .. bind("+back", "S") .. " " .. bind("+moveright", "D") end, "Ходьба", "Движение" },
	{ function() return bind("+speed", "SHIFT") end, "Бег (тратит выносливость)", "Движение" },
	{ function() return bind("+walk", "ALT") end, "Медленный шаг", "Движение" },
	{ function() return bind("+duck", "CTRL") end, "Присесть", "Движение" },
	{ function() return bind("+jump", "SPACE") end, "Прыжок; встать со стула, выйти из позы /act", "Движение" },
	{ function() return bind("+walk", "ALT") .. " + " .. bind("+use", "E") end, "Сесть на стул, скамейку, ступеньку; глядя под ноги — на пол. Ещё раз — встать", "Движение" },
	{ function() return bind("+use", "E") end, "Взаимодействие: двери, предметы, банкомат, NPC; по человеку — меню (познакомиться, деньги, удостоверение)", "Взаимодействие" },
	{ "F1", "По двери квартиры — жильцы и аренда, по двери бизнеса — управление", "Взаимодействие" },
	{ "ПКМ", "С пустыми руками — взять предмет или тело руками; ЛКМ — бросить; R + мышь — повернуть", "Взаимодействие" },
	{ function() return bind("+menu_context", "C") end, "Удерживать: выбросить деньги, информация, упасть", "Взаимодействие" },
	{ function() return key("nyrp_bind_inventory", "O") end, "Инвентарь (сумка и снаряжение). У игроков также Q", "Меню" },
	{ function() return key("nyrp_bind_gestures", "G") end, "Удерживать: круговое меню жестов и режим голоса", "Меню" },
	{ "H", "Память: знакомые, мысли (задания), навыки", "Меню" },
	{ function() return key("nyrp_bind_health", "J") end, "Состояние здоровья: ранения, лечение", "Меню" },
	{ function() return key("nyrp_bind_thirdperson", "F3") end, "Третье лицо", "Меню" },
	{ function() return key("nyrp_bind_tpmenu", "F4") end, "Настройка камеры третьего лица", "Меню" },
	{ function() return bind("+showscores", "TAB") end, "Список игроков", "Меню" },
	{ "ESC", "Меню паузы: персонажи, настройки, бинды, справка", "Меню" },
	{ "F7", "Админ-меню (только администрации)", "Меню" },
	{ function() return bind("messagemode", "Y") end, "Чат (слева — выбор: сказать, шёпот, крик, действие, OOC)", "Чат и голос" },
	{ function() return bind("messagemode2", "U") end, "Чат сразу в OOC (//)", "Чат и голос" },
	{ function() return bind("+voicerecord", "V") end, "Говорить голосом (громкость — в меню G)", "Чат и голос" },
	{ "ПКМ", "С рацией в руке — говорить в эфир", "Чат и голос" },
	{ function() return bind("invnext", "КОЛЕСО") .. " / 1–6" end, "Выбор оружия и предметов в руках", "Оружие" },
	{ function() return bind("+reload", "R") .. " (держать)" end, "Поднять / опустить оружие. Из опущенного нельзя стрелять", "Оружие" },
	{ function() return bind("+reload", "R") end, "Перезарядка (оружие поднято)", "Оружие" },
	{ "F2", "Телефон в руках: свободная мышь", "Телефон" },
	{ "↑ ↓ ← →  ENTER", "Телефон: выбор и нажатие; BACKSPACE — назад; ПКМ — убрать от лица", "Телефон" },
	{ function() return key("nyrp_bind_911", "F6") end, "Службы и такси: принять верхний вызов 911", "Службы" },
}

-- команды: { команда, аргументы, описание, админ, раздел }
H.Commands = H.Commands or {}
local BASE_COMMANDS = {
	{ "/w", "<текст>", "Шёпот — слышно совсем рядом (/ш)", false, "Чат" },
	{ "/y", "<текст>", "Крик — слышно далеко (/к)", false, "Чат" },
	{ "/me", "<действие>", "Действие от третьего лица: ** Имя действие (/я)", false, "Чат" },
	{ "/it", "<описание>", "Описание окружения: ** ...", false, "Чат" },
	{ "/looc", "<текст>", "Вне роли, только рядом (коротко: .// или [[)", false, "Чат" },
	{ "/ooc", "<текст>", "Вне роли, весь сервер (коротко: //)", false, "Чат" },
	{ "/r", "<текст>", "Рация: сказать на своей частоте (/р, /radio)", false, "Чат" },
	{ "/познакомиться", "", "Представиться тому, на кого смотрите (/introduce, /представиться)", false, "Персонаж" },
	{ "/act", "<поза>", "Поза: сесть_на_корточки, стоять_облокотившись, руки_вверх, руки_за_голову, лечь, скрестить_руки, раненый, сидеть_у_стены… Без аргумента — выйти из позы", false, "Персонаж" },
	{ "/acts", "", "Окно со всеми позами", false, "Персонаж" },
	{ "/raise", "", "Поднять / опустить оружие (/поднять); то же — удерживать R", false, "Персонаж" },
	{ "/shift", "", "Начать / закончить смену на работе (/смена)", false, "Работа и службы" },
	{ "/911accept", "", "Принять верхний вызов 911 (службы, такси)", false, "Работа и службы" },
	{ "/help", "", "Эта справка (/помощь, /справка)", false, "Персонаж" },
	{ "/roll", "[макс]", "Бросить кость 1..макс (по умолчанию 100) — видно рядом (/ролл)", false, "Персонаж" },
	{ "/coin", "", "Подбросить монетку (/монетка)", false, "Персонаж" },
	{ "/dice", "", "Бросить два кубика (/кости)", false, "Персонаж" },
	-- администрация: игроки
	{ "/admin", "", "Админ-меню (также F7, консоль nyrp_admin)", true, "Администрация" },
	{ "/goto", "<имя>", "Телепортироваться к игроку (/тп)", true, "Администрация" },
	{ "/bring", "<имя>", "Телепортировать игрока к себе", true, "Администрация" },
	{ "/return", "[имя]", "Вернуть себя или игрока туда, где он был до телепорта", true, "Администрация" },
	{ "/freeze", "<имя>", "Заморозить игрока (/unfreeze — разморозить)", true, "Администрация" },
	{ "/slay", "<имя>", "Убить игрока", true, "Администрация" },
	{ "/hp", "<имя> [здоровье]", "Вылечить / установить здоровье (/heal)", true, "Администрация" },
	{ "/addmoney", "<имя> <сумма>", "Выдать деньги (минус — забрать)", true, "Администрация" },
	{ "/kick", "<имя> [причина]", "Кикнуть игрока", true, "Администрация" },
	{ "/ban", "<имя|SteamID> <минуты> [причина]", "Забанить (0 минут — навсегда)", true, "Администрация" },
	{ "/unban", "<SteamID>", "Разбанить", true, "Администрация" },
	{ "/warn", "<имя> <причина>", "Выдать предупреждение (/warns <имя> — посмотреть)", true, "Администрация" },
	{ "/charkill", "<имя>", "Смерть персонажа — удалить персонажа игрока (/pk)", true, "Администрация" },
	{ "/observer", "", "Режим наблюдателя: невидимость и полёт (/obs, V у админа)", true, "Администрация" },
	{ "/spectate", "<имя>", "Наблюдать за игроком (/spec; без имени — выйти)", true, "Администрация" },
	{ "/setrole", "[игрок] <роль>", "Назначить роль (police, medic, fire, citizen). Без аргументов — список", true, "Администрация" },
	{ "/facaccept", "[имя]", "Одобрить заявку в службу. Без аргумента — список заявок", true, "Администрация" },
	{ "/flaggive", "<имя> <буквы>", "Выдать флаги: p — физган, t — тулган, e — пропы, n — энтити, v — транспорт", true, "Администрация" },
	{ "/flagtake", "<имя> <буквы>", "Забрать флаги", true, "Администрация" },
	{ "/flags", "[имя]", "Посмотреть флаги (свои — любой игрок)", true, "Администрация" },
	-- администрация: мир
	{ "/persist", "", "Сделать проп, на который смотрите, постоянным (сохраняется)", true, "Мир и карта" },
	{ "/unpersist", "", "Снять постоянство с пропа", true, "Мир и карта" },
	{ "/textadd", "[размер] <текст>", "3D-надпись на стене/полу (перенос — \\n)", true, "Мир и карта" },
	{ "/textcolor", "<r g b | #rrggbb | reset>", "Цвет следующих надписей", true, "Мир и карта" },
	{ "/textremove", "", "Удалить ближайшую 3D-надпись", true, "Мир и карта" },
	{ "/paneladd", "<ссылка> [ширина] [высота]", "Панель с картинкой (png/jpg) на стене", true, "Мир и карта" },
	{ "/panelremove", "", "Удалить панель", true, "Мир и карта" },
	{ "/spawnadd", "[роль|all]", "Точка появления под ногами (по умолчанию — общая)", true, "Мир и карта" },
	{ "/spawnremove", "", "Удалить ближайшую точку спавна", true, "Мир и карта" },
	{ "/spawns", "", "Показать точки спавна", true, "Мир и карта" },
	{ "/doorownable", "<цена> [название] | off", "Дверь сдаётся в аренду (смотреть на дверь)", true, "Мир и карта" },
	{ "/doorbusiness", "<цена> [название]", "Коммерческое помещение (по лицензии ратуши)", true, "Мир и карта" },
	{ "/doorfaction", "<police|medic|fire|off>", "Служебная дверь — открывают только сотрудники", true, "Мир и карта" },
	{ "/mailbox", "", "Поставить стену почтовых ящиков (смотреть на стену)", true, "Мир и карта" },
	{ "/mailboxremove", "", "Удалить почтовые ящики", true, "Мир и карта" },
	{ "/street", "<вид>", "Поставить уличный объект (без вида — список)", true, "Мир и карта" },
	{ "/streetremove", "", "Убрать уличный объект", true, "Мир и карта" },
	{ "/npc", "<jobs|cityhall|factions>", "Поставить готового NPC", true, "Мир и карта" },
	{ "/areaedit", "", "Редактор зон (районов)", true, "Мир и карта" },
	{ "/terminal", "<роль>", "Служебный компьютер", true, "Мир и карта" },
	{ "/armory", "<роль>", "Оружейная / шкаф снаряжения службы", true, "Мир и карта" },
	{ "/bed", "", "Больничная койка", true, "Мир и карта" },
	{ "/jailpoint", "", "Добавить камеру КПЗ (где стоите)", true, "Мир и карта" },
	{ "/jailrelease", "", "Точка выхода из КПЗ", true, "Мир и карта" },
	{ "/jailclear", "", "Удалить все точки КПЗ", true, "Мир и карта" },
	{ "/jobpoint", "<профессия>", "Добавить точку задания профессии", true, "Мир и карта" },
	{ "/jobpointdel", "", "Удалить ближайшую точку задания", true, "Мир и карта" },
	{ "/jobstation", "<профессия>", "Поставить станцию профессии", true, "Мир и карта" },
	{ "/fire", "", "Начать пожар (проверка FDNY)", true, "Мир и карта" },
	{ "/fireclear", "", "Потушить все пожары", true, "Мир и карта" },
	{ "/graffitiremove", "", "Стереть граффити, на которое смотрите", true, "Мир и карта" },
	{ "/graffitiwipe", "", "Стереть все граффити на карте", true, "Мир и карта" },
}

function H.AddCommand(cmd, args, desc, admin, cat)
	for _, c in ipairs(H.Commands) do if c[1] == cmd then return end end
	H.Commands[#H.Commands + 1] = { cmd, args or "", desc or "", admin and true or false, cat or "Разное" }
end
function H.AddKey(k, desc, cat)
	H.Keys[#H.Keys + 1] = { k, desc, cat or "Разное" }
end

local SKILLS = { strength = "Сила", stamina = "Выносливость", agility = "Ловкость", intellect = "Интеллект", medicine = "Медицина", combat = "Стрельба" }

-- string.lower не понимает кириллицу
local function lowerRu(s)
	s = string.lower(s or "")
	s = string.gsub(s, "\208([\144-\159])", function(c) return "\208" .. string.char(string.byte(c) + 32) end)
	s = string.gsub(s, "\208([\160-\175])", function(c) return "\209" .. string.char(string.byte(c) - 32) end)
	s = string.gsub(s, "\208\129", "\209\145")
	return s
end
H.Lower = lowerRu

-- ------------------------------------------------------------- вкладки --
-- каждая вкладка: список строк { title, sub, text, tag, tagCol, head = раздел }
local function keyRows()
	local out = {}
	local list = {}
	for _, k in ipairs(BASE_KEYS) do list[#list + 1] = k end
	for _, k in ipairs(H.Keys) do list[#list + 1] = k end
	for _, k in ipairs(list) do
		local name = isfunction(k[1]) and k[1]() or k[1]
		out[#out + 1] = { key = name, text = k[2], head = k[3] }
	end
	return out
end

local function commandRows()
	local out, seen = {}, {}
	local isAdmin = LocalPlayer():IsAdmin()
	local list = {}
	for _, c in ipairs(BASE_COMMANDS) do list[#list + 1] = c end
	for _, c in ipairs(H.Commands) do list[#list + 1] = c end
	for _, c in ipairs(list) do
		if not seen[c[1]] then
			seen[c[1]] = true
			out[#out + 1] = { title = c[1] .. (c[2] ~= "" and (" " .. c[2]) or ""), text = c[3], admin = c[4], head = c[5], dim = c[4] and not isAdmin }
		end
	end
	-- админские — в конце
	local sorted = {}
	for _, r in ipairs(out) do if not r.admin then sorted[#sorted + 1] = r end end
	for _, r in ipairs(out) do if r.admin then sorted[#sorted + 1] = r end end
	return sorted
end

local function serviceRows()
	local out = {}
	local R = NYRP.Roles
	if R and R.Order then
		for _, id in ipairs(R.Order) do
			local r = R.List[id]
			local req = {}
			if r.Default then
				req[#req + 1] = "Есть у каждого нового персонажа."
			else
				req[#req + 1] = "Как вступить: NPC-вербовщик городских служб («Расскажите о службах») → «Вступить»."
				if r.Whitelist then req[#req + 1] = "Только по заявке — её одобряет администрация." end
				if (r.MinHours or 0) > 0 then req[#req + 1] = "Наиграть этим персонажем: " .. r.MinHours .. " ч." end
				if r.MinSkills then
					local s = {}
					for sk, lv in pairs(r.MinSkills) do s[#s + 1] = (SKILLS[sk] or sk) .. " " .. lv end
					if #s > 0 then req[#req + 1] = "Навыки: " .. table.concat(s, ", ") .. "." end
				end
				if (r.MaxMembers or 0) > 0 then req[#req + 1] = "Мест: " .. r.MaxMembers .. "." end
				if (r.Salary or 0) > 0 then req[#req + 1] = "Зарплата: " .. (NYRP.Money and NYRP.Money.Format(r.Salary) or ("$" .. r.Salary)) .. " в игровую полночь." end
				if r.Service then req[#req + 1] = "Принимает вызовы 911 («" .. r.Service .. "»): " .. key("nyrp_bind_911", "F6") .. " — принять." end
			end
			out[#out + 1] = { title = r.Name, text = (r.Description or "") .. "\n" .. table.concat(req, " "), head = "Роли (службы)",
				icon = r.Icon, col = r.Color }
		end
	end
	local J = NYRP.Jobs
	if J and J.Order then
		for _, id in ipairs(J.Order) do
			local j = J.List[id]
			local extra = "Берётся у NPC центра занятости. Начать/закончить смену — /shift."
			if j.Criminal then extra = "Криминал: полиция получает вызов, после дела вы в розыске. Начать/закончить — /shift." end
			out[#out + 1] = { title = j.Name, text = (j.Description or "") .. "\n" .. extra, head = j.Criminal and "Криминал" or "Профессии",
				iconUI = j.Icon, col = j.Color }
		end
	end
	return out
end

local ABOUT = {
	{ title = "New-York Roleplay", text = "Серьёзный городской ролевой режим: вы играете за жителя Нью-Йорка — работаете, снимаете квартиру, открываете бизнес, служите в полиции, скорой или пожарной охране. Всё, что говорит и делает персонаж, — часть истории города.", head = "О режиме" },
	{ title = "Персонаж", text = "У каждого персонажа свои вещи, деньги, навыки, знакомые и жильё. Других людей вы не знаете по имени, пока они не представятся (E по человеку → «Познакомиться»). Навыки растут от того, что персонаж делает.", head = "О режиме" },
	{ title = "Правила отыгрыша", text = "Не смешивайте игру и реальность: то, что вы узнали вне роли (OOC), персонаж не знает. Не убивайте без причины, отыгрывайте страх и боль, уважайте других игроков. Вопросы вне роли — в // (OOC) или .// (LOOC).", head = "О режиме" },
	{ title = "Деньги и жильё", text = "Наличные носите с собой, остальное — в банке (банкомат, карта и PIN). Квартиру можно снять в телефоне (NY Homes), ключи придут в почтовый ящик. Письма тоже приходят туда.", head = "О режиме" },
	{ title = "Оружие", text = "Оружие по умолчанию опущено: чтобы стрелять, поднимите его (держите R или /raise). Патроны и магазин сохраняются вместе с персонажем.", head = "О режиме" },
	{ title = "Версия", text = "New-York Roleplay " .. tostring(NYRP.Version or "") .. ". Сообщить об ошибке — администрации сервера.", head = "О режиме" },
}

local TABS = {
	{ id = "keys", name = "Клавиши", icon = "keyboard", rows = keyRows },
	{ id = "cmds", name = "Команды", icon = "message", rows = commandRows },
	{ id = "roles", name = "Службы", icon = "badge", rows = serviceRows },
	{ id = "about", name = "О режиме", icon = "info", rows = function() return ABOUT end },
}

-- ----------------------------------------------------------------- окно --
local function matches(r, q)
	if q == "" then return true end
	local hay = lowerRu((r.title or "") .. " " .. (r.key or "") .. " " .. (r.text or "") .. " " .. (r.head or ""))
	return string.find(hay, q, 1, true) ~= nil
end

local function buildList(scroll, rows, q, width)
	scroll:Clear()
	local lastHead
	local n = 0
	local textFont, titleFont = NYRP.Font("regular", 14), NYRP.Font("semibold", 17)
	for _, r in ipairs(rows) do
		if matches(r, q) then
			n = n + 1
			if r.head and r.head ~= lastHead then
				lastHead = r.head
				local hd = scroll:Add("DPanel")
				hd:Dock(TOP)
				hd:SetTall(UI.S(34))
				hd:DockMargin(0, n > 1 and UI.S(8) or 0, 0, UI.S(2))
				local title = string.upper(r.head)
				hd.Paint = function(_, w, h)
					draw.SimpleText(title, NYRP.Font("title", 16), 0, h / 2, UI.Col.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					surface.SetDrawColor(255, 255, 255, 12)
					surface.DrawRect(UI.TextSize(title, NYRP.Font("title", 16)) + UI.S(12), h / 2, w, 1)
				end
			end
			local keyW = r.key and math.max(UI.S(130), UI.TextSize(r.key, NYRP.Font("bold", 14)) + UI.S(24)) or 0
			local hasIcon = r.icon or r.iconUI
			local left = UI.S(14) + (r.key and keyW + UI.S(14) or 0) + (hasIcon and UI.S(44) or 0)
			local textW = width - left - UI.S(24)
			local lines = {}
			for para in string.gmatch((r.text or "") .. "\n", "(.-)\n") do
				for _, l in ipairs(UI.Wrap(para, textFont, textW)) do lines[#lines + 1] = l end
			end
			local th = r.title and UI.S(24) or 0
			local h = math.max(UI.S(44), UI.S(12) + th + #lines * UI.S(19) + UI.S(10))
			local row = scroll:Add("DPanel")
			row:Dock(TOP)
			row:SetTall(h)
			row:DockMargin(0, 0, UI.S(6), UI.S(6))
			row.Hover = 0
			row.Paint = function(s, w, hh)
				s.Hover = UI.Approach(s.Hover, s:IsHovered() and 1 or 0, 12)
				UI.RoundedRect(UI.S(10), 0, 0, w, hh, Color(255, 255, 255, 7 + 6 * s.Hover))
				local x = UI.S(14)
				if r.key then
					local kh = UI.S(30)
					UI.RoundedRect(UI.S(7), x, hh / 2 - kh / 2, keyW, kh, Color(0, 0, 0, 110))
					UI.Outline(UI.S(7), x, hh / 2 - kh / 2, keyW, kh, Color(255, 255, 255, 30), 1)
					draw.SimpleText(r.key, NYRP.Font("bold", 14), x + keyW / 2, hh / 2, UI.Col.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					x = x + keyW + UI.S(14)
				end
				if r.icon then
					surface.SetMaterial(UI.Mat("nyrp/status/" .. r.icon .. ".png"))
					surface.SetDrawColor(r.col or color_white)
					surface.DrawTexturedRect(x, UI.S(12), UI.S(30), UI.S(30))
					x = x + UI.S(44)
				elseif r.iconUI then
					UI.DrawIcon(r.iconUI, x + UI.S(15), UI.S(27), UI.S(28), r.col or UI.Col.accent)
					x = x + UI.S(44)
				end
				local y = UI.S(10)
				if r.title then
					local tcol = r.dim and UI.Col.dim or (r.col or UI.Col.text)
					draw.SimpleText(r.title, titleFont, x, y, tcol)
					if r.admin then
						local tw = UI.TextSize(r.title, titleFont)
						local f = NYRP.Font("bold", 10)
						local bw = UI.TextSize("АДМИН", f) + UI.S(14)
						UI.RoundedRect(UI.S(6), x + tw + UI.S(10), y + UI.S(3), bw, UI.S(17), Color(214, 70, 64, 50))
						draw.SimpleText("АДМИН", f, x + tw + UI.S(10) + bw / 2, y + UI.S(11), UI.Col.red, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					end
					y = y + th
				else
					y = hh / 2 - #lines * UI.S(19) / 2
				end
				for i, l in ipairs(lines) do
					draw.SimpleText(l, textFont, x, y + (i - 1) * UI.S(19), r.title and UI.Col.dim or UI.Col.text)
				end
			end
		end
	end
	if n == 0 then
		local e = scroll:Add("DPanel")
		e:Dock(TOP)
		e:SetTall(UI.S(120))
		e.Paint = function(_, w, h)
			UI.DrawIcon("question", w / 2, h / 2 - UI.S(16), UI.S(36), UI.Col.faint)
			draw.SimpleText("Ничего не найдено", NYRP.Font("semibold", 16), w / 2, h / 2 + UI.S(22), UI.Col.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end
end

function H.Open(tab)
	if IsValid(H.Win) then H.Win:Close() end
	local win, body = UI.Window("Справка", "question", 900, 680, { sub = "New-York Roleplay", keyboard = true })
	H.Win = win
	H.Tab = tab or H.Tab or "keys"

	local top = vgui.Create("DPanel", body)
	top:Dock(TOP)
	top:SetTall(UI.S(42))
	top:DockMargin(0, 0, 0, UI.S(12))
	top.Paint = function() end

	local search = vgui.Create("NYRP.TextEntry", top)
	search:Dock(RIGHT)
	search:SetWide(UI.S(240))
	search:SetPlaceholderText("Поиск...")
	search:SetUpdateOnType(true)

	local scroll = vgui.Create("NYRP.Scroll", body)
	scroll:Dock(FILL)

	local function rebuild()
		local t
		for _, x in ipairs(TABS) do if x.id == H.Tab then t = x end end
		t = t or TABS[1]
		local q = lowerRu(string.Trim(search:GetValue() or ""))
		buildList(scroll, t.rows(), q, body:GetWide() - UI.S(10))
	end
	search.OnValueChange = function() rebuild() end

	for _, t in ipairs(TABS) do
		local b = UI.AddButton(top, t.name, t.icon, function()
			H.Tab = t.id
			rebuild()
		end, { dock = LEFT, h = 42 })
		b:SetWide(UI.S(140))
		b:DockMargin(0, 0, UI.S(8), 0)
		b.Think = function(s) s:SetStyle(H.Tab == t.id and "solid" or "ghost") end
	end
	rebuild()
	return win
end

net.Receive("nyrp.ux.help", function() H.Open() end)
concommand.Add("nyrp_help", function() H.Open() end)

-- подсказки команд в чате (список при наборе «/»)
hook.Add("InitPostEntity", "nyrp.ux.help", function()
	local C = NYRP.Chat and NYRP.Chat.Commands
	if not C then return end
	local have = {}
	for _, c in ipairs(C) do have[c[1]] = true end
	for _, c in ipairs({ { "/act", "Поза (без аргумента — выйти)" }, { "/acts", "Список поз" }, { "/raise", "Поднять/опустить оружие" }, { "/help", "Справка: клавиши, команды, службы" } }) do
		if not have[c[1]] then C[#C + 1] = c end
	end
end)
