--[[
	Админ-меню (клиент): /admin, консоль nyrp_admin, F4 (nyrp_bind_admin) — только администраторам.
	Вкладки: «Игроки» (поиск, карточка игрока, действия), «Баны», «Логи», «Настройки», «Предупреждения».
	Все действия уходят на сервер (nyrp.admin.act) и там же проверяются права.
	Также: приём настроек сервера (nyrp.admin.cfg) — применяются к NYRP.Config у всех игроков.
]]

NYRP.Admin = NYRP.Admin or {}
local A = NYRP.Admin
local UI = NYRP.UI
local GOLD = Color(247, 198, 0)
local PINK = Color(255, 90, 140)

local bindCvar = CreateClientConVar("nyrp_bind_admin", tostring(KEY_F4), true, false, "Клавиша: админ-меню")

A.Data = A.Data or {}
A.CfgValues = A.CfgValues or {}

-- --------------------------------------------------------------- сеть --
function A.Act(act, target, a1, a2, a3)
	net.Start("nyrp.admin.act")
	net.WriteString(act)
	net.WriteEntity(IsValid(target) and target or NULL)
	net.WriteString(tostring(a1 or ""))
	net.WriteString(tostring(a2 or ""))
	net.WriteString(tostring(a3 or ""))
	net.SendToServer()
end

-- запросы не чаще раза в 1.1 с (сервер тоже ограничивает); лишний — откладывается
local lastReq, pending = 0, nil
local function sendReq(kind, p1, p2)
	lastReq = RealTime()
	net.Start("nyrp.admin.req")
	net.WriteString(kind)
	net.WriteString(p1 or "")
	net.WriteString(p2 or "")
	net.SendToServer()
end
function A.Request(kind, p1, p2)
	local wait = 1.1 - (RealTime() - lastReq)
	if wait <= 0 then sendReq(kind, p1, p2) return end
	pending = { kind, p1, p2 }
	timer.Create("nyrp.admin.req", wait, 1, function()
		if pending then local p = pending pending = nil sendReq(p[1], p[2], p[3]) end
	end)
end

net.Receive("nyrp.admin.data", function()
	local kind = net.ReadString()
	local len = net.ReadUInt(32)
	local raw = net.ReadData(len)
	local json = util.Decompress(raw or "")
	local data = json and util.JSONToTable(json)
	if not data then return end
	A.Data[kind] = data
	if A.OnData and A.OnData[kind] then A.OnData[kind](data) end
end)

net.Receive("nyrp.admin.cfg", function()
	local n = net.ReadUInt(8)
	for _ = 1, n do
		local key = net.ReadString()
		local s = A.SettingByKey[key]
		local v
		if s and s.type == "bool" then v = net.ReadBool() else v = net.ReadDouble() end
		if s then
			A.CfgValues[key] = v
			A.ApplySetting(s, v)
		end
	end
	if A.OnData and A.OnData.cfg then A.OnData.cfg() end
end)

hook.Add("InitPostEntity", "nyrp.admin.cfg", function()
	timer.Simple(2, function() sendReq("cfg") end)
end)

A.OnData = A.OnData or {}

-- ------------------------------------------------------- окно ввода --
-- A.Prompt(заголовок, описание, поля, кнопка, onOk(values), цвет)
-- поле: { key, label, placeholder, numeric, default, presets = { { "1 ч", "60" }, ... } }
function A.Prompt(title, desc, fields, okText, onOk, accent)
	accent = accent or GOLD
	local bg = vgui.Create("EditablePanel")
	bg:SetSize(ScrW(), ScrH())
	bg:MakePopup()
	bg.Born = RealTime()
	bg.Paint = function(s, w, h)
		local t = UI.Ease((RealTime() - s.Born) / 0.2)
		surface.SetDrawColor(0, 0, 0, 140 * t)
		surface.DrawRect(0, 0, w, h)
	end
	bg.OnMousePressed = function(s) s:Remove() end
	local bw = UI.S(480)
	local bh = UI.S(150)
	for _, f in ipairs(fields) do bh = bh + UI.S(70) + (f.presets and UI.S(38) or 0) end
	local box = vgui.Create("EditablePanel", bg)
	box:SetSize(bw, bh)
	box:Center()
	box.OnMousePressed = function() end
	box.Paint = function(_, w, h)
		UI.RoundedRect(UI.S(12), 0, 0, w, h, UI.Col.panel)
		UI.Outline(UI.S(12), 0, 0, w, h, UI.Col.stroke, 1)
		surface.SetDrawColor(accent)
		surface.DrawRect(UI.S(24), UI.S(56), UI.S(36), 2)
		draw.SimpleText(title, NYRP.Font("title", 24), UI.S(24), UI.S(16), color_white)
		if desc then draw.SimpleText(desc, NYRP.Font("regular", 14), UI.S(24), UI.S(66), UI.Col.dim) end
	end
	local y = UI.S(desc and 96 or 74)
	local entries = {}
	local first
	for _, f in ipairs(fields) do
		local lbl = vgui.Create("DLabel", box)
		lbl:SetPos(UI.S(24), y)
		lbl:SetFont(NYRP.Font("semibold", 13))
		lbl:SetTextColor(UI.Col.dim)
		lbl:SetText(string.upper(f.label or ""))
		lbl:SizeToContents()
		y = y + UI.S(20)
		local e = vgui.Create("NYRP.TextEntry", box)
		e:SetPos(UI.S(24), y)
		e:SetSize(bw - UI.S(48), UI.S(40))
		e:SetPlaceholderText(f.placeholder or "")
		if f.numeric then e:SetNumeric(true) end
		if f.default then e:SetValue(tostring(f.default)) end
		entries[f.key] = e
		first = first or e
		y = y + UI.S(48)
		if f.presets then
			local px = UI.S(24)
			for _, pr in ipairs(f.presets) do
				local b = vgui.Create("NYRP.Button", box)
				b:SetLabel(pr[1])
				b:SetFontStyle("medium", 13)
				b:SetAlign(TEXT_ALIGN_CENTER)
				b:SetStyle("ghost")
				b:SetAccent(accent)
				local tw = UI.TextSize(pr[1], NYRP.Font("medium", 13)) + UI.S(22)
				b:SetSize(tw, UI.S(28))
				b:SetPos(px, y - UI.S(2))
				b.DoClick = function() e:SetValue(pr[2]) end
				px = px + tw + UI.S(6)
			end
			y = y + UI.S(38)
		end
	end
	local function submit()
		local vals = {}
		for k, e in pairs(entries) do vals[k] = string.Trim(e:GetValue()) end
		if onOk(vals) ~= false then bg:Remove() end
	end
	for _, e in pairs(entries) do e.OnEnter = submit end
	local ok = vgui.Create("NYRP.Button", box)
	ok:SetSize((bw - UI.S(60)) / 2, UI.S(42))
	ok:SetPos(UI.S(24), bh - UI.S(62))
	ok:SetLabel(okText or "Готово")
	ok:SetStyle("solid")
	ok:SetAccent(accent)
	ok:SetAlign(TEXT_ALIGN_CENTER)
	ok.DoClick = submit
	local no = vgui.Create("NYRP.Button", box)
	no:SetSize((bw - UI.S(60)) / 2, UI.S(42))
	no:SetPos(UI.S(36) + (bw - UI.S(60)) / 2, bh - UI.S(62))
	no:SetLabel("Отмена")
	no:SetStyle("ghost")
	no:SetAlign(TEXT_ALIGN_CENTER)
	no.DoClick = function() bg:Remove() end
	if first then first:RequestFocus() end
	UI.Sound("open")
	return bg
end

-- ------------------------------------------------------- общие виджеты --
local function header(parent, text, sub)
	local p = vgui.Create("DPanel", parent)
	p:Dock(TOP)
	p:SetTall(UI.S(30))
	p:DockMargin(0, 0, 0, UI.S(8))
	p.Paint = function(_, w, h)
		draw.SimpleText(text, NYRP.Font("title", 20), 0, h / 2, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		if sub then
			local s = isfunction(sub) and sub() or sub
			draw.SimpleText(s, NYRP.Font("regular", 13), w, h / 2, UI.Col.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
	end
	return p
end

local function emptyNote(parent, text)
	local p = vgui.Create("DPanel", parent)
	p:Dock(TOP)
	p:SetTall(UI.S(80))
	p.Paint = function(_, w, h)
		draw.SimpleText(text, NYRP.Font("medium", 15), w / 2, h / 2, UI.Col.faint, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	return p
end

local function chip(parent, text, col, selected, fn)
	local b = vgui.Create("DButton", parent)
	b:SetText("")
	local f = NYRP.Font("semibold", 13)
	b:SetSize(UI.TextSize(text, f) + UI.S(24), UI.S(28))
	b:SetCursor("hand")
	b.Hover = 0
	b.Paint = function(s, w, h)
		s.Hover = UI.Approach(s.Hover, s:IsHovered() and 1 or 0, 14)
		local sel = selected()
		UI.RoundedRect(h / 2, 0, 0, w, h, sel and col or Color(255, 255, 255, 10 + s.Hover * 14))
		if not sel then UI.Outline(h / 2, 0, 0, w, h, Color(col.r, col.g, col.b, 60 + s.Hover * 80), 1) end
		draw.SimpleText(text, f, w / 2, h / 2, sel and Color(12, 12, 16) or UI.Col.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		return true
	end
	b.DoClick = function() UI.Sound("click") fn() end
	return b
end

local function fmtDate(t) return t and os.date("%d.%m.%Y %H:%M", t) or "—" end

local function roleOf(p)
	local R = NYRP.Roles
	if R and R.Of then
		local ok, r = pcall(R.Of, p)
		if ok then return r end
	end
end

-- =============================================================== ИГРОКИ ==
local function playerMatches(p, q)
	if q == "" then return true end
	return string.find(A.Lower(NYRP.CharName(p)), q, 1, true) or string.find(A.Lower(p:Nick()), q, 1, true)
		or string.find(A.Lower(p:SteamID()), q, 1, true)
end

local function askReason(title, desc, okText, accent, fn, presets)
	A.Prompt(title, desc, { { key = "reason", label = "Причина", placeholder = "Нарушение правил: …", presets = presets } }, okText, function(v)
		fn(v.reason)
	end, accent)
end

local function actionsFor(p, refresh)
	local name = NYRP.CharName(p)
	local frozen = p:GetNW2Bool("nyrp.frozen", false)
	return {
		{ "Телепорт к нему", "move", GOLD, function() A.Act("goto", p) end },
		{ "Привести к себе", "hand", GOLD, function() A.Act("bring", p) end },
		{ "Вернуть на место", "arrow_left", GOLD, function() A.Act("return", p) end },
		{ frozen and "Разморозить" or "Заморозить", frozen and "unlock" or "lock", UI.Col.blue, function()
			A.Act("freeze", p, frozen and "0" or "1")
			timer.Simple(0.3, refresh)
		end },
		{ "Наблюдать", "eye", UI.Col.blue, function() A.Act("spectate", p) if IsValid(A.Win) then A.Win:Close() end end },
		{ "Вылечить", "medkit", UI.Col.green, function() A.Act("heal", p) end },
		{ "Выдать деньги", "cash", UI.Col.green, function()
			A.Prompt("Деньги: " .. name, "Наличные. Минус — забрать.", {
				{ key = "n", label = "Сумма", placeholder = "500", presets = { { "+100", "100" }, { "+500", "500" }, { "+1000", "1000" }, { "+5000", "5000" }, { "−500", "-500" } } },
			}, "Выдать", function(v)
				local n = tonumber(v.n)
				if not n or n == 0 then UI.Sound("error") return false end
				A.Act("money", p, tostring(math.floor(n)))
			end, UI.Col.green)
		end },
		{ "Сменить роль", "badge", UI.Col.green, function()
			local R = NYRP.Roles
			local opts = {}
			for _, id in ipairs(R and R.Order or {}) do
				local r = R.List[id]
				opts[#opts + 1] = { text = r.Name, icon = "badge", color = r.Color, func = function() A.Act("role", p, id) end }
			end
			UI.Menu(opts)
		end },
		{ "Предупреждение", "warning", GOLD, function()
			askReason("Предупреждение: " .. name, A.WarnLimit .. " за " .. A.WarnDays .. " дней — бан на сутки", "Выдать", GOLD, function(r)
				A.Act("warn", p, r)
			end, { { "NonRP", "NonRP поведение" }, { "DM", "DM — убийство без причины" }, { "Оскорбления", "Оскорбления в OOC" }, { "Метагейм", "Метагейм" } })
		end },
		{ "Убить (slay)", "skull", UI.Col.red, function() A.Act("slay", p) end },
		{ "Кикнуть", "logout", UI.Col.red, function()
			askReason("Кик: " .. name, p:Nick() .. " · " .. p:SteamID(), "Кикнуть", UI.Col.red, function(r) A.Act("kick", p, r) end)
		end },
		{ "Забанить", "lock", UI.Col.red, function()
			A.Prompt("Бан: " .. name, p:Nick() .. " · " .. p:SteamID(), {
				{ key = "m", label = "Срок, минут (0 — навсегда)", placeholder = "60", numeric = true, default = "60",
					presets = { { "1 ч", "60" }, { "1 д", "1440" }, { "3 д", "4320" }, { "7 д", "10080" }, { "30 д", "43200" }, { "Навсегда", "0" } } },
				{ key = "r", label = "Причина", placeholder = "Нарушение правил: …" },
			}, "Забанить", function(v)
				local m = tonumber(v.m)
				if not m or m < 0 then UI.Sound("error") return false end
				A.Act("ban", p, tostring(math.floor(m)), v.r)
			end, UI.Col.red)
		end },
		{ "Удалить персонажа (ПК)", "trash", UI.Col.red, function()
			A.ConfirmCharKill(p)
		end },
	}
end

function A.ConfirmCharKill(p)
	if not IsValid(p) then return end
	UI.Confirm("Пермакилл", "Персонаж «" .. NYRP.CharName(p) .. "» игрока " .. p:Nick() .. " будет удалён НАВСЕГДА вместе с вещами. Отменить нельзя.",
		"Удалить навсегда", function() A.Act("charkill", p) end)
end

local function buildPlayers(parent)
	local selected = A.SelPlayer
	local query = ""

	local left = vgui.Create("DPanel", parent)
	left:Dock(LEFT)
	left:SetWide(UI.S(380))
	left:DockMargin(0, 0, UI.S(16), 0)
	left.Paint = function() end

	local search = vgui.Create("NYRP.TextEntry", left)
	search:Dock(TOP)
	search:SetPlaceholderText("Поиск: имя, ник, SteamID")
	search:DockMargin(0, 0, 0, UI.S(10))

	local count = vgui.Create("DPanel", left)
	count:Dock(TOP)
	count:SetTall(UI.S(18))
	count:DockMargin(UI.S(4), 0, 0, UI.S(6))
	count.Paint = function(_, w, h)
		draw.SimpleText("ОНЛАЙН: " .. player.GetCount(), NYRP.Font("bold", 11), 0, h / 2, UI.Col.faint, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	local scroll = vgui.Create("NYRP.Scroll", left)
	scroll:Dock(FILL)

	local right = vgui.Create("DPanel", parent)
	right:Dock(FILL)
	right.Paint = function(_, w, h) UI.RoundedRect(UI.S(12), 0, 0, w, h, Color(255, 255, 255, 6)) end

	local buildDetail
	local function rebuildList()
		scroll:Clear()
		local list = {}
		for _, p in ipairs(player.GetAll()) do
			if playerMatches(p, query) then list[#list + 1] = p end
		end
		table.sort(list, function(a, b) return A.Lower(NYRP.CharName(a)) < A.Lower(NYRP.CharName(b)) end)
		if #list == 0 then emptyNote(scroll, "Никого не найдено") end
		for _, p in ipairs(list) do
			local row = vgui.Create("DButton", scroll)
			row:SetText("")
			row:Dock(TOP)
			row:SetTall(UI.S(58))
			row:DockMargin(0, 0, UI.S(6), UI.S(6))
			row:SetCursor("hand")
			row.Hover = 0
			row.Paint = function(s, w, h)
				if not IsValid(p) then return true end
				s.Hover = UI.Approach(s.Hover, s:IsHovered() and 1 or 0, 14)
				local sel = selected == p
				local r = roleOf(p)
				local rc = r and r.Color or UI.Col.dim
				UI.RoundedRect(UI.S(10), 0, 0, w, h, sel and Color(247, 198, 0, 30) or Color(255, 255, 255, 8 + s.Hover * 10))
				if sel then UI.Outline(UI.S(10), 0, 0, w, h, Color(247, 198, 0, 120), 1) end
				UI.RoundedRect(UI.S(2), UI.S(8), UI.S(12), UI.S(3), h - UI.S(24), rc)
				draw.SimpleText(NYRP.CharName(p), NYRP.Font("semibold", 16), UI.S(20), UI.S(18), color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				draw.SimpleText(p:Nick() .. "  ·  " .. (r and r.Name or "—"), NYRP.Font("regular", 13), UI.S(20), UI.S(39), UI.Col.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				local ping = p:Ping()
				draw.SimpleText(ping .. " мс", NYRP.Font("medium", 13), w - UI.S(12), UI.S(18), ping > 150 and UI.Col.red or UI.Col.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
				draw.SimpleText(NYRP.Money.Format(p:GetNW2Int("nyrp.money", 0)), NYRP.Font("medium", 13), w - UI.S(12), UI.S(39), GOLD, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
				if p:IsAdmin() then UI.DrawIcon("shield", w - UI.S(90), UI.S(18), UI.S(14), PINK) end
				if A.IsObserver(p) then UI.DrawIcon("eye", w - UI.S(110), UI.S(18), UI.S(14), GOLD) end
				return true
			end
			row.DoClick = function()
				UI.Sound("click")
				selected = p
				A.SelPlayer = p
				buildDetail()
			end
			row.DoRightClick = function()
				local opts = {}
				for _, a in ipairs(actionsFor(p, function() end)) do opts[#opts + 1] = { text = a[1], icon = a[2], color = a[3], func = a[4] } end
				UI.Menu(opts)
			end
		end
		left.Known = {}
		for _, p in ipairs(player.GetAll()) do left.Known[p] = true end
	end

	buildDetail = function()
		right:Clear()
		if not IsValid(selected) then
			local n = vgui.Create("DPanel", right)
			n:Dock(FILL)
			n.Paint = function(_, w, h)
				UI.DrawIcon("users", w / 2, h / 2 - UI.S(30), UI.S(48), Color(255, 255, 255, 30))
				draw.SimpleText("Выберите игрока в списке", NYRP.Font("medium", 16), w / 2, h / 2 + UI.S(20), UI.Col.faint, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				draw.SimpleText("ПКМ по строке — быстрые действия", NYRP.Font("regular", 13), w / 2, h / 2 + UI.S(44), UI.Col.faint, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
			return
		end
		local p = selected
		local card = vgui.Create("DPanel", right)
		card:Dock(TOP)
		card:SetTall(UI.S(176))
		card:DockMargin(UI.S(18), UI.S(18), UI.S(18), UI.S(10))
		card.Paint = function(_, w, h)
			if not IsValid(p) then
				draw.SimpleText("Игрок вышел с сервера", NYRP.Font("medium", 16), 0, UI.S(20), UI.Col.red)
				return
			end
			local r = roleOf(p)
			local rc = r and r.Color or UI.Col.dim
			UI.Glow(UI.S(40), UI.S(40), UI.S(120), UI.S(120), Color(rc.r, rc.g, rc.b, 50))
			UI.Circle(UI.S(40), UI.S(40), UI.S(34), Color(rc.r, rc.g, rc.b, 40))
			if r and r.Icon then
				surface.SetMaterial(UI.Mat("nyrp/status/" .. r.Icon .. ".png"))
				surface.SetDrawColor(rc)
				surface.DrawTexturedRect(UI.S(18), UI.S(18), UI.S(44), UI.S(44))
			else
				UI.DrawIcon("user", UI.S(40), UI.S(40), UI.S(36), rc)
			end
			draw.SimpleText(NYRP.CharName(p), NYRP.Font("title", 28), UI.S(92), UI.S(24), color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText((r and r.Name or "Без роли") .. (p:IsAdmin() and "  ·  администратор" or ""), NYRP.Font("medium", 14), UI.S(92), UI.S(54), rc, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			local stats = {
				{ "STEAM-НИК", p:Nick() },
				{ "STEAMID", p:SteamID() },
				{ "ПИНГ", p:Ping() .. " мс" },
				{ "НАЛИЧНЫЕ", NYRP.Money.Format(p:GetNW2Int("nyrp.money", 0)) },
				{ "ЗДОРОВЬЕ", p:Alive() and (p:Health() .. " / " .. p:GetMaxHealth()) or "мёртв" },
				{ "СОСТОЯНИЕ", (p:GetNW2Bool("nyrp.frozen", false) and "заморожен" or (A.IsObserver(p) and "наблюдатель" or (NYRP.HasCharacter(p) and "в игре" or "в меню"))) },
			}
			local cw = w / 3
			for i, s in ipairs(stats) do
				local cx = ((i - 1) % 3) * cw
				local cy = UI.S(88) + math.floor((i - 1) / 3) * UI.S(44)
				draw.SimpleText(s[1], NYRP.Font("bold", 10), cx, cy, UI.Col.faint)
				draw.SimpleText(s[2], NYRP.Font("semibold", 15), cx, cy + UI.S(14), UI.Col.text)
			end
		end
		local copy = vgui.Create("NYRP.IconButton", card)
		copy:SetSize(UI.S(30), UI.S(30))
		copy:SetIcon("copy")
		copy:SetTooltip("Копировать SteamID")
		card.PerformLayout = function(s, w) copy:SetPos(w - UI.S(30), UI.S(8)) end
		copy.DoClick = function() if IsValid(p) then SetClipboardText(p:SteamID()) NYRP.Notify("SteamID скопирован", "success", 2) end end

		local grid = vgui.Create("DIconLayout", right)
		grid:Dock(FILL)
		grid:DockMargin(UI.S(18), UI.S(4), UI.S(18), UI.S(18))
		grid:SetSpaceX(UI.S(8))
		grid:SetSpaceY(UI.S(8))
		local acts = actionsFor(p, function() if IsValid(right) then buildDetail() end end)
		grid.PerformLayout = function(s, w)
			local bw = math.floor((w - UI.S(16)) / 3)
			for _, c in ipairs(s:GetChildren()) do c:SetSize(bw, UI.S(42)) end
			DIconLayout.PerformLayout(s)
		end
		for _, a in ipairs(acts) do
			local b = grid:Add("NYRP.Button")
			b:SetLabel(a[1])
			b:SetIcon(a[2])
			b:SetAccent(a[3])
			b:SetStyle("ghost")
			b:SetFontStyle("semibold", 14)
			b:SetSize(UI.S(200), UI.S(42))
			b.DoClick = function() if IsValid(p) then a[4]() else UI.Sound("error") end end
		end
	end

	search.OnChange = function(s)
		query = A.Lower(string.Trim(s:GetValue()))
		rebuildList()
	end
	rebuildList()
	buildDetail()

	-- новые/ушедшие игроки
	left.Think = function(s)
		if (s.NextCheck or 0) > RealTime() then return end
		s.NextCheck = RealTime() + 1
		local changed = false
		local n = 0
		for _, p in ipairs(player.GetAll()) do
			n = n + 1
			if not s.Known[p] then changed = true end
		end
		if n ~= table.Count(s.Known) then changed = true end
		if changed then rebuildList() end
	end
end

-- ================================================================= БАНЫ ==
local function buildBans(parent)
	local top = vgui.Create("DPanel", parent)
	top:Dock(TOP)
	top:SetTall(UI.S(42))
	top:DockMargin(0, 0, 0, UI.S(12))
	top.Paint = function() end
	local search = vgui.Create("NYRP.TextEntry", top)
	search:Dock(FILL)
	search:SetPlaceholderText("Поиск: ник, SteamID, причина")
	local add = UI.AddButton(top, "Забанить SteamID", "lock", function()
		A.Prompt("Бан по SteamID", "Игрок может быть не на сервере", {
			{ key = "sid", label = "SteamID", placeholder = "STEAM_0:1:12345678 или 7656…" },
			{ key = "m", label = "Срок, минут (0 — навсегда)", numeric = true, default = "1440",
				presets = { { "1 ч", "60" }, { "1 д", "1440" }, { "7 д", "10080" }, { "30 д", "43200" }, { "Навсегда", "0" } } },
			{ key = "r", label = "Причина", placeholder = "Нарушение правил: …" },
		}, "Забанить", function(v)
			if not A.NormalizeSteamID(v.sid) then UI.Sound("error") NYRP.Notify("Неверный SteamID", "error") return false end
			local m = tonumber(v.m)
			if not m or m < 0 then UI.Sound("error") return false end
			A.Act("banid", nil, v.sid, tostring(math.floor(m)), v.r)
			timer.Simple(0.6, function() A.Request("bans") end)
		end, UI.Col.red)
	end, { dock = RIGHT, accent = UI.Col.red })
	add:SetWide(UI.S(200))
	add:DockMargin(UI.S(10), 0, 0, 0)
	local ref = UI.AddButton(top, "", "refresh", function() A.Request("bans") end, { dock = RIGHT })
	ref:SetWide(UI.S(42))
	ref:SetAlign(TEXT_ALIGN_CENTER)
	ref:DockMargin(UI.S(10), 0, 0, 0)

	local scroll = vgui.Create("NYRP.Scroll", parent)
	scroll:Dock(FILL)

	local function fill()
		if not IsValid(scroll) then return end
		scroll:Clear()
		local d = A.Data.bans
		if not d then emptyNote(scroll, "Загрузка…") return end
		local q = A.Lower(string.Trim(search:GetValue()))
		local shown = 0
		local skew = os.time() - (d.now or os.time())
		for _, b in ipairs(d.rows or {}) do
			local hay = A.Lower((b.name or "") .. " " .. (b.steamid or "") .. " " .. (b.reason or "") .. " " .. (b.by or ""))
			if q == "" or string.find(hay, q, 1, true) then
				shown = shown + 1
				local row = vgui.Create("DPanel", scroll)
				row:Dock(TOP)
				row:SetTall(UI.S(78))
				row:DockMargin(0, 0, UI.S(6), UI.S(8))
				row.Paint = function(_, w, h)
					UI.RoundedRect(UI.S(10), 0, 0, w, h, Color(255, 255, 255, 8))
					UI.RoundedRect(UI.S(2), UI.S(8), UI.S(14), UI.S(3), h - UI.S(28), UI.Col.red)
					draw.SimpleText(b.name or b.steamid, NYRP.Font("semibold", 17), UI.S(22), UI.S(18), color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					local nw = UI.TextSize(b.name or b.steamid, NYRP.Font("semibold", 17))
					draw.SimpleText(b.steamid, NYRP.Font("regular", 13), UI.S(32) + nw, UI.S(18), UI.Col.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					draw.SimpleText("Причина: " .. (b.reason or ""), NYRP.Font("regular", 14), UI.S(22), UI.S(40), UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					draw.SimpleText("Выдал: " .. (b.by or "?") .. "  ·  " .. fmtDate(b.time), NYRP.Font("regular", 12), UI.S(22), UI.S(60), UI.Col.faint, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					local left = (b.expires or 0) > 0 and ("ещё " .. A.FormatDuration(b.expires - (os.time() - skew))) or "НАВСЕГДА"
					draw.SimpleText(left, NYRP.Font("bold", 14), w - UI.S(160), UI.S(28), (b.expires or 0) > 0 and GOLD or UI.Col.red, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
					if (b.expires or 0) > 0 then
						draw.SimpleText("до " .. fmtDate(b.expires), NYRP.Font("regular", 12), w - UI.S(160), UI.S(50), UI.Col.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
					end
				end
				local un = UI.AddButton(row, "Разбанить", "unlock", function()
					UI.Confirm("Снять бан", "Разбанить " .. (b.name or b.steamid) .. " (" .. b.steamid .. ")?", "Разбанить", function()
						A.Act("unban", nil, b.steamid)
						timer.Simple(0.6, function() A.Request("bans") end)
					end)
				end, { dock = RIGHT, accent = UI.Col.green })
				un:SetWide(UI.S(136))
				un:DockMargin(0, UI.S(18), UI.S(14), UI.S(18))
			end
		end
		if shown == 0 then emptyNote(scroll, #(d.rows or {}) == 0 and "Активных банов нет" or "Ничего не найдено") end
	end
	search.OnChange = fill
	A.OnData.bans = fill
	fill()
	A.Request("bans")
end

-- ================================================================= ЛОГИ ==
local function buildLogs(parent)
	local cat = A.LogCat or "all"
	local top = vgui.Create("DPanel", parent)
	top:Dock(TOP)
	top:SetTall(UI.S(42))
	top:DockMargin(0, 0, 0, UI.S(10))
	top.Paint = function() end
	local search = vgui.Create("NYRP.TextEntry", top)
	search:Dock(FILL)
	search:SetPlaceholderText("Поиск по тексту или SteamID (Enter)")
	search:SetValue(A.LogSearch or "")
	local function request()
		A.LogSearch = string.Trim(search:GetValue())
		A.Request("logs", cat, A.LogSearch)
	end
	search.OnEnter = request
	local ref = UI.AddButton(top, "Обновить", "refresh", request, { dock = RIGHT })
	ref:SetWide(UI.S(140))
	ref:DockMargin(UI.S(10), 0, 0, 0)

	local chips = vgui.Create("DIconLayout", parent)
	chips:Dock(TOP)
	chips:SetSpaceX(UI.S(6))
	chips:SetSpaceY(UI.S(6))
	chips:DockMargin(0, 0, 0, UI.S(10))
	local all = { { id = "all", name = "Все", col = GOLD } }
	for _, c in ipairs(A.LogCats) do all[#all + 1] = c end
	for _, c in ipairs(all) do
		chips:Add(chip(chips, c.name, c.col, function() return cat == c.id end, function()
			cat = c.id
			A.LogCat = c.id
			request()
		end))
	end

	local info = vgui.Create("DPanel", parent)
	info:Dock(TOP)
	info:SetTall(UI.S(20))
	info:DockMargin(0, 0, 0, UI.S(4))
	info.Paint = function(_, w, h)
		local d = A.Data.logs
		local txt = d and string.format("Показано %d (новые сверху) · в памяти сервера %d из 2000 · файлы: data/nyrp/logs/  ·  клик — копировать строку", #(d.rows or {}), d.total or 0) or "Загрузка…"
		draw.SimpleText(txt, NYRP.Font("regular", 12), 0, h / 2, UI.Col.faint, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	local scroll = vgui.Create("NYRP.Scroll", parent)
	scroll:Dock(FILL)

	local function fill()
		if not IsValid(scroll) then return end
		scroll:Clear()
		local d = A.Data.logs
		if not d then emptyNote(scroll, "Загрузка…") return end
		if #(d.rows or {}) == 0 then emptyNote(scroll, "Записей нет") return end
		for i, e in ipairs(d.rows) do
			local c = A.LogCatById[e.c] or A.LogCatById.other
			local row = vgui.Create("DButton", scroll)
			row:SetText("")
			row:Dock(TOP)
			row:SetTall(UI.S(26))
			row:DockMargin(0, 0, UI.S(6), 1)
			row:SetTooltip(e.x)
			local time = os.date("%d.%m %H:%M:%S", e.t or 0)
			row.Paint = function(s, w, h)
				if s:IsHovered() then UI.RoundedRect(UI.S(4), 0, 0, w, h, Color(255, 255, 255, 14))
				elseif i % 2 == 0 then UI.RoundedRect(UI.S(4), 0, 0, w, h, Color(255, 255, 255, 4)) end
				draw.SimpleText(time, NYRP.Font("medium", 12), UI.S(8), h / 2, UI.Col.faint, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				local tx = UI.S(118)
				local tw = UI.S(78)
				UI.RoundedRect(UI.S(3), tx, h / 2 - UI.S(8), tw, UI.S(16), Color(c.col.r, c.col.g, c.col.b, 40))
				draw.SimpleText(string.upper(c.name), NYRP.Font("bold", 10), tx + tw / 2, h / 2, c.col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				local text = e.x or ""
				local f = NYRP.Font("regular", 13)
				local maxw = w - tx - tw - UI.S(20)
				if UI.TextSize(text, f) > maxw then
					-- обрезаем по символам UTF-8
					local n = utf8.len(text) or #text
					while n > 1 and UI.TextSize(string.sub(text, 1, (utf8.offset(text, n) or #text + 1) - 1) .. "…", f) > maxw do n = n - 4 end
					text = string.sub(text, 1, (utf8.offset(text, math.max(n, 1)) or #text + 1) - 1) .. "…"
				end
				draw.SimpleText(text, f, tx + tw + UI.S(10), h / 2, UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				return true
			end
			row.DoClick = function()
				SetClipboardText(time .. " [" .. c.name .. "] " .. (e.x or ""))
				NYRP.Notify("Строка лога скопирована", "success", 2)
			end
		end
	end
	A.OnData.logs = fill
	fill()
	request()
end

-- ============================================================ НАСТРОЙКИ ==
local function buildSettings(parent)
	local pendingVals = {}
	local scroll
	local function fill()
		if not IsValid(scroll) then return end
		scroll:Clear()
		pendingVals = {}
		for _, s in ipairs(A.Settings) do
			local cur = A.CfgValues[s.key]
			if cur == nil then cur = A.GetSetting(s) end
			local row = vgui.Create("DPanel", scroll)
			row:Dock(TOP)
			row:SetTall(UI.S(58))
			row:DockMargin(0, 0, UI.S(6), UI.S(6))
			row.Paint = function(_, w, h)
				UI.RoundedRect(UI.S(10), 0, 0, w, h, Color(255, 255, 255, 7))
				if pendingVals[s.key] ~= nil then UI.RoundedRect(UI.S(2), UI.S(6), UI.S(12), UI.S(3), h - UI.S(24), GOLD) end
			end
			local reset = vgui.Create("NYRP.IconButton", row)
			reset:Dock(RIGHT)
			reset:SetWide(UI.S(30))
			reset:DockMargin(UI.S(8), UI.S(14), UI.S(12), UI.S(14))
			reset:SetIcon("refresh")
			reset:SetTooltip("Сбросить: " .. tostring(s.type == "bool" and (s.def and "вкл" or "выкл") or s.def))
			reset.DoClick = function()
				UI.Confirm("Сброс настройки", "Вернуть «" .. s.name .. "» к значению по умолчанию (" .. tostring(s.def) .. ")?", "Сбросить", function()
					A.Request("cfgreset", s.key)
				end)
			end
			if s.type == "bool" then
				local t = vgui.Create("NYRP.Toggle", row)
				t:Dock(FILL)
				t:DockMargin(UI.S(18), 0, 0, 0)
				t:SetTall(UI.S(58))
				t:SetLabel(s.name)
				t:SetDescription(s.desc)
				t:SetChecked(cur == true)
				t.OnChange = function(_, v)
					if v == (cur == true) then pendingVals[s.key] = nil else pendingVals[s.key] = v end
				end
			else
				local e = vgui.Create("NYRP.TextEntry", row)
				e:Dock(RIGHT)
				e:SetWide(UI.S(130))
				e:DockMargin(0, UI.S(9), 0, UI.S(9))
				e:SetNumeric(true)
				e:SetValue(tostring(math.floor(tonumber(cur) or s.def)))
				e.OnChange = function(se)
					local v = tonumber(se:GetValue())
					if v and v ~= tonumber(cur) then pendingVals[se.Key] = v else pendingVals[se.Key] = nil end
				end
				e.Key = s.key
				local lbl = vgui.Create("DPanel", row)
				lbl:Dock(FILL)
				lbl.Paint = function(_, w, h)
					draw.SimpleText(s.name, NYRP.Font("medium", 17), UI.S(18), h / 2 - UI.S(2), UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
					draw.SimpleText(s.desc .. "  ·  от " .. s.min .. " до " .. s.max .. (s.suffix or ""), NYRP.Font("regular", 13), UI.S(18), h / 2 + UI.S(2), UI.Col.faint, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
					local v = pendingVals[s.key]
					if v ~= nil and (v < s.min or v > s.max) then
						draw.SimpleText("вне границ", NYRP.Font("semibold", 12), w - UI.S(10), h / 2, UI.Col.red, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
					end
				end
			end
		end
	end

	local bottom = vgui.Create("DPanel", parent)
	bottom:Dock(BOTTOM)
	bottom:SetTall(UI.S(46))
	bottom:DockMargin(0, UI.S(10), 0, 0)
	bottom.Paint = function(_, w, h)
		local n = table.Count(pendingVals)
		draw.SimpleText(n > 0 and ("Изменено: " .. n .. " — не забудьте сохранить") or "Сохраняется в data/nyrp/config.json и применяется сразу у всех",
			NYRP.Font("regular", 14), 0, h / 2, n > 0 and GOLD or UI.Col.faint, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	local save = UI.AddButton(bottom, "Сохранить", "save", function()
		local list = {}
		for key, v in pairs(pendingVals) do
			local s = A.SettingByKey[key]
			if s then
				if s.type ~= "bool" and (v < s.min or v > s.max) then
					NYRP.Notify("«" .. s.name .. "»: допустимо от " .. s.min .. " до " .. s.max, "error", 5)
					UI.Sound("error")
					return
				end
				list[#list + 1] = { s, v }
			end
		end
		if #list == 0 then NYRP.Notify("Изменений нет", "info", 2) return end
		net.Start("nyrp.admin.cfgset")
		net.WriteUInt(#list, 8)
		for _, it in ipairs(list) do
			net.WriteString(it[1].key)
			net.WriteBool(it[1].type == "bool")
			if it[1].type == "bool" then net.WriteBool(it[2] == true) else net.WriteDouble(it[2]) end
		end
		net.SendToServer()
	end, { dock = RIGHT, style = "solid", accent = GOLD })
	save:SetWide(UI.S(200))
	save:DockMargin(0, 0, 0, 0)

	scroll = vgui.Create("NYRP.Scroll", parent)
	scroll:Dock(FILL)
	A.OnData.cfg = fill
	fill()
	A.Request("cfg")
end

-- ======================================================= ПРЕДУПРЕЖДЕНИЯ ==
local function buildWarns(parent)
	local onlyActive = A.WarnsOnlyActive ~= false
	local top = vgui.Create("DPanel", parent)
	top:Dock(TOP)
	top:SetTall(UI.S(42))
	top:DockMargin(0, 0, 0, UI.S(12))
	top.Paint = function() end
	local search = vgui.Create("NYRP.TextEntry", top)
	search:Dock(FILL)
	search:SetPlaceholderText("Поиск: ник, персонаж, SteamID, причина")
	local tg = vgui.Create("NYRP.Toggle", top)
	tg:Dock(RIGHT)
	tg:SetWide(UI.S(200))
	tg:DockMargin(UI.S(16), 0, 0, 0)
	tg:SetLabel("Только активные")
	tg:SetChecked(onlyActive)
	local ref = UI.AddButton(top, "", "refresh", function() A.Request("warns") end, { dock = RIGHT })
	ref:SetWide(UI.S(42))
	ref:SetAlign(TEXT_ALIGN_CENTER)
	ref:DockMargin(UI.S(10), 0, 0, 0)

	local note = vgui.Create("DPanel", parent)
	note:Dock(TOP)
	note:SetTall(UI.S(20))
	note:DockMargin(0, 0, 0, UI.S(6))
	note.Paint = function(_, w, h)
		draw.SimpleText(A.WarnLimit .. " активных предупреждения за " .. A.WarnDays .. " дней — автоматический бан на сутки. Выдать: вкладка «Игроки» или /warn <имя> <причина>",
			NYRP.Font("regular", 12), 0, h / 2, UI.Col.faint, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	local scroll = vgui.Create("NYRP.Scroll", parent)
	scroll:Dock(FILL)

	local function fill()
		if not IsValid(scroll) then return end
		scroll:Clear()
		local d = A.Data.warns
		if not d then emptyNote(scroll, "Загрузка…") return end
		local q = A.Lower(string.Trim(search:GetValue()))
		local shown = 0
		for _, wr in ipairs(d.rows or {}) do
			local hay = A.Lower((wr.name or "") .. " " .. (wr.char or "") .. " " .. (wr.steamid or "") .. " " .. (wr.reason or "") .. " " .. (wr.by or ""))
			if (not onlyActive or wr.active) and (q == "" or string.find(hay, q, 1, true)) then
				shown = shown + 1
				local row = vgui.Create("DPanel", scroll)
				row:Dock(TOP)
				row:SetTall(UI.S(72))
				row:DockMargin(0, 0, UI.S(6), UI.S(8))
				local status, scol = "АКТИВНО", GOLD
				if wr.removed then status, scol = "СНЯТО", UI.Col.faint elseif not wr.active then status, scol = "ИСТЕКЛО", UI.Col.dim end
				row.Paint = function(_, w, h)
					UI.RoundedRect(UI.S(10), 0, 0, w, h, Color(255, 255, 255, 8))
					UI.RoundedRect(UI.S(2), UI.S(8), UI.S(14), UI.S(3), h - UI.S(28), scol)
					local title = (wr.char and wr.char ~= wr.name) and (wr.char .. " (" .. (wr.name or "") .. ")") or (wr.name or wr.steamid)
					draw.SimpleText(title, NYRP.Font("semibold", 16), UI.S(22), UI.S(16), color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					local tw = UI.TextSize(title, NYRP.Font("semibold", 16))
					draw.SimpleText(wr.steamid .. "  ·  активных " .. (wr.count or 0) .. "/" .. (d.limit or A.WarnLimit), NYRP.Font("regular", 12), UI.S(32) + tw, UI.S(17), UI.Col.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					draw.SimpleText(wr.reason or "", NYRP.Font("regular", 14), UI.S(22), UI.S(38), UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					draw.SimpleText("Выдал: " .. (wr.by or "?") .. "  ·  " .. fmtDate(wr.time), NYRP.Font("regular", 12), UI.S(22), UI.S(57), UI.Col.faint, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					draw.SimpleText(status, NYRP.Font("bold", 12), w - UI.S(150), h / 2, scol, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
				end
				if not wr.removed then
					local b = UI.AddButton(row, "Снять", "close", function()
						UI.Confirm("Снять предупреждение", "Снять предупреждение «" .. (wr.reason or "") .. "» с " .. (wr.name or wr.steamid) .. "?", "Снять", function()
							A.Act("unwarn", nil, wr.steamid, tostring(wr.id))
							timer.Simple(0.6, function() A.Request("warns") end)
						end)
					end, { dock = RIGHT, accent = UI.Col.green })
					b:SetWide(UI.S(120))
					b:DockMargin(0, UI.S(16), UI.S(14), UI.S(16))
				end
			end
		end
		if shown == 0 then emptyNote(scroll, onlyActive and "Активных предупреждений нет" or "Предупреждений нет") end
	end
	search.OnChange = fill
	tg.OnChange = function(_, v) onlyActive = v A.WarnsOnlyActive = v fill() end
	A.OnData.warns = fill
	fill()
	A.Request("warns")
end

-- ================================================================= ОКНО ==
local TABS = {
	{ id = "players", name = "Игроки", icon = "users", build = buildPlayers },
	{ id = "bans", name = "Баны", icon = "lock", build = buildBans },
	{ id = "logs", name = "Логи", icon = "clipboard", build = buildLogs },
	{ id = "settings", name = "Настройки", icon = "settings", build = buildSettings },
	{ id = "warns", name = "Предупреждения", icon = "warning", build = buildWarns },
}

function A.OpenMenu(tab)
	local ply = LocalPlayer()
	if not IsValid(ply) or not ply:IsAdmin() then return end
	if IsValid(A.Win) then A.Win:Remove() end
	A.Tab = tab or A.Tab or "players"
	local win, body = UI.Window("Администрирование", "shield", 1220, 760, { keyboard = true, sub = ply:Nick() .. "  ·  " .. (ply:IsSuperAdmin() and "суперадмин" or "админ") })
	A.Win = win
	win.OnKeyCodePressed = function(s, key)
		if key == bindCvar:GetInt() and not vgui.GetKeyboardFocus() then s:Close() end
	end

	local side = vgui.Create("DPanel", body)
	side:Dock(LEFT)
	side:SetWide(UI.S(210))
	side:DockMargin(0, 0, UI.S(18), 0)
	side.Paint = function(_, w, h)
		surface.SetDrawColor(255, 255, 255, 12)
		surface.DrawRect(w - 1, 0, 1, h)
	end

	local content = vgui.Create("DPanel", body)
	content:Dock(FILL)
	content.Paint = function() end

	local buttons = {}
	local function select(id)
		A.Tab = id
		content:Clear()
		A.OnData.bans, A.OnData.logs, A.OnData.warns, A.OnData.cfg = nil, nil, nil, nil
		for _, t in ipairs(TABS) do
			if t.id == id then t.build(content) end
		end
		for bid, b in pairs(buttons) do b.Sel = bid == id end
	end

	for _, t in ipairs(TABS) do
		local b = vgui.Create("NYRP.Button", side)
		b:Dock(TOP)
		b:SetTall(UI.S(46))
		b:DockMargin(0, 0, UI.S(14), UI.S(6))
		b:SetLabel(t.name)
		b:SetIcon(t.icon)
		b:SetFontStyle("semibold", 16)
		local base = b.Paint
		b.Paint = function(s, w, h)
			if s.Sel then
				UI.RoundedRect(UI.S(8), 0, 0, w, h, Color(247, 198, 0, 26))
				UI.RoundedRect(UI.S(2), 0, h * 0.2, UI.S(3), h * 0.6, GOLD)
			end
			return base(s, w, h)
		end
		b.DoClick = function() if A.Tab ~= t.id then select(t.id) end end
		buttons[t.id] = b
	end

	-- внизу: наблюдатель и подсказка
	local hint = vgui.Create("DPanel", side)
	hint:Dock(BOTTOM)
	hint:SetTall(UI.S(64))
	hint:DockMargin(0, UI.S(8), UI.S(14), 0)
	hint.Paint = function(_, w, h)
		local f = NYRP.Font("regular", 12)
		draw.SimpleText("V — наблюдатель", f, 0, UI.S(8), UI.Col.faint)
		draw.SimpleText("F4 / /admin — это меню", f, 0, UI.S(26), UI.Col.faint)
		draw.SimpleText("Онлайн: " .. player.GetCount() .. " / " .. game.MaxPlayers(), f, 0, UI.S(44), UI.Col.faint)
	end
	local obs = UI.AddButton(side, "Наблюдатель", "eye", function()
		A.Act("observer")
		win:Close()
	end, { dock = BOTTOM, accent = GOLD })
	obs:DockMargin(0, UI.S(8), UI.S(14), 0)
	local obsPaint = obs.Paint
	obs.Paint = function(s, w, h)
		s:SetLabel(A.IsObserver(LocalPlayer()) and "Выйти из наблюдателя" or "Наблюдатель")
		return obsPaint(s, w, h)
	end

	select(A.Tab)
	return win
end

function A.ToggleMenu()
	if IsValid(A.Win) and not A.Win.Closing then A.Win:Close() return end
	A.OpenMenu()
end

net.Receive("nyrp.admin.open", function()
	local mode = net.ReadString()
	local ent = net.ReadEntity()
	if mode == "charkill" then A.ConfirmCharKill(ent) return end
	if mode == "warns" then A.OpenMenu("warns") return end
	A.OpenMenu()
end)

concommand.Add("nyrp_admin", function()
	local ply = LocalPlayer()
	if not IsValid(ply) or not ply:IsAdmin() then NYRP.Notify("Только для администрации", "error") return end
	A.ToggleMenu()
end)

-- F4 (настраивается: nyrp_bind_admin) — только у администраторов
hook.Add("PlayerButtonDown", "nyrp.admin.menu", function(ply, key)
	if not IsFirstTimePredicted() or ply ~= LocalPlayer() then return end
	if key ~= bindCvar:GetInt() or not ply:IsAdmin() then return end
	if NYRP.State and NYRP.State ~= "playing" then return end
	if gui.IsGameUIVisible() or vgui.GetKeyboardFocus() then return end
	if IsValid(A.Win) and not A.Win.Closing then A.Win:Close() return end
	if vgui.CursorVisible() then return end
	A.OpenMenu()
end)
