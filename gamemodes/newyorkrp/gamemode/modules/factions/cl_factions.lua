--[[
	Служебный компьютер: вкладки «Устав», «Вызовы 911», «На смене» и вкладка службы
	(NYPD — розыск и штрафы, EMS — пострадавшие, FDNY — очаги пожаров).
]]

local UI = NYRP.UI
local F = NYRP.Factions

local EXTRA = {
	police = { name = "Розыск", icon = "handcuffs", empty = "Сейчас никто не в розыске" },
	medic = { name = "Пострадавшие", icon = "critical", empty = "Пострадавших нет" },
	fire = { name = "Пожары", icon = "fire", empty = "Активных возгораний нет" },
}

local function act(ent, a, x, y, z)
	net.Start("nyrp.terminal.act")
	net.WriteEntity(ent)
	net.WriteString(a)
	net.WriteString(x or "")
	net.WriteString(y or "")
	net.WriteString(z or "")
	net.SendToServer()
end

local function roleColor(r)
	local R = NYRP.Roles.List[r]
	return R and R.Color or Color(247, 198, 0)
end

local function statusIcon(name, x, y, s, col)
	surface.SetMaterial(UI.Mat("nyrp/status/" .. name .. ".png"))
	surface.SetDrawColor(col or color_white)
	surface.DrawTexturedRect(x - s / 2, y - s / 2, s, s)
end

-- строка списка: текст слева, кнопки справа
local function row(parent, text, sub, col, buttons)
	local p = vgui.Create("DPanel", parent)
	p:Dock(TOP)
	p:SetTall(UI.S(sub and 58 or 44))
	p:DockMargin(0, 0, 0, UI.S(6))
	p.Paint = function(_, w, h)
		UI.RoundedRect(UI.S(10), 0, 0, w, h, Color(255, 255, 255, 8))
		surface.SetDrawColor(col)
		surface.DrawRect(0, UI.S(8), 3, h - UI.S(16))
		draw.SimpleText(text, NYRP.Font("semibold", 15), UI.S(16), sub and UI.S(10) or h / 2, color_white, TEXT_ALIGN_LEFT, sub and TEXT_ALIGN_TOP or TEXT_ALIGN_CENTER)
		if sub then draw.SimpleText(sub, NYRP.Font("regular", 12), UI.S(16), UI.S(32), UI.Col.dim) end
	end
	for _, b in ipairs(buttons or {}) do
		local btn = UI.AddButton(p, b[1], b[2], b[3], { dock = RIGHT, accent = b[4] or col, style = b[5] })
		btn:SetWide(UI.S(b[6] or 150))
		btn:DockMargin(UI.S(6), UI.S(8), UI.S(8), UI.S(8))
	end
	return p
end

local function emptyText(parent, text)
	local l = vgui.Create("DLabel", parent)
	l:Dock(TOP)
	l:SetTall(UI.S(60))
	l:SetFont(NYRP.Font("medium", 15))
	l:SetTextColor(UI.Col.dim)
	l:SetContentAlignment(5)
	l:SetText(text)
end

net.Receive("nyrp.terminal", function()
	local ent, d = net.ReadEntity(), net.ReadTable()
	local R = NYRP.Roles.List[d.role]
	local col = roleColor(d.role)
	local keepTab = IsValid(F.Win) and F.Win.Tab or "charter"
	if IsValid(F.Win) then F.Win:Remove() end
	local onDuty = LocalPlayer():GetNW2Bool("nyrp.onDuty")
	local win, body = UI.Window((R and R.Name or d.role) .. " — служебный компьютер", "keyboard", 980, 660,
		{ sub = "на смене: " .. #d.staff .. (onDuty and " · вы на дежурстве" or "") })
	F.Win = win
	win.Tab = keepTab

	-- слева вкладки
	local side = vgui.Create("DPanel", body)
	side:Dock(LEFT)
	side:SetWide(UI.S(220))
	side:DockMargin(0, 0, UI.S(14), 0)
	side.Paint = function() end
	local page = vgui.Create("NYRP.Scroll", body)
	page:Dock(FILL)

	local tabs = {
		{ id = "charter", name = "Устав", icon = "certificate" },
		{ id = "calls", name = "Вызовы 911 (" .. #d.calls .. ")", icon = "phone_call" },
		{ id = "staff", name = "На смене", icon = "users" },
	}
	if EXTRA[d.role] then tabs[#tabs + 1] = { id = "extra", name = EXTRA[d.role].name .. " (" .. #d.extra .. ")", icon = "warning" } end
	if d.role == "police" then
		tabs[#tabs + 1] = { id = "records", name = "Аресты и судимости", icon = "id" }
		tabs[#tabs + 1] = { id = "fine", name = "Выписать штраф", icon = "clipboard" }
	end

	local function show(id)
		win.Tab = id
		page:Clear()
		local canvas = page
		if id == "charter" then
			local txt = vgui.Create("DLabel", canvas)
			txt:Dock(TOP)
			txt:SetWrap(true)
			txt:SetAutoStretchVertical(true)
			txt:SetFont(NYRP.Font("regular", 15))
			txt:SetTextColor(Color(225, 228, 238))
			txt:SetText(d.charter or "")
			txt:DockMargin(UI.S(6), UI.S(4), UI.S(12), UI.S(12))
		elseif id == "calls" then
			if #d.calls == 0 then emptyText(canvas, "Вызовов нет") end
			local first = true
			for _, c in ipairs(d.calls) do
				local sub = (c.from ~= "" and ("звонил: " .. c.from .. " · ") or "") .. c.ago .. " с назад" .. (c.taken and (" · принял " .. c.taken) or " · не принят")
				local btns = {}
				if not c.taken and first then
					first = false
					btns[1] = { "Принять", "check", function() act(ent, "accept") end, nil, "solid" }
				end
				row(canvas, c.reason .. (c.comment ~= "" and (" — " .. c.comment) or ""), sub, c.taken and UI.Col.dim or Color(230, 70, 60), btns)
			end
		elseif id == "staff" then
			if #d.staff == 0 then emptyText(canvas, "Никого нет на смене") end
			for _, s in ipairs(d.staff) do
				row(canvas, s.name, s.duty and "на дежурстве" or "не на дежурстве", s.alive and (s.duty and col or UI.Col.dim) or Color(90, 90, 90))
			end
		elseif id == "records" then
			if #(d.records or {}) == 0 then emptyText(canvas, "Арестов ещё не было") end
			for _, r in ipairs(d.records or {}) do
				row(canvas, r.name .. " — " .. r.reason, r.date .. " · " .. r.minutes .. " мин КПЗ · задержал " .. r.officer .. " · всего судимостей: " .. r.total, col)
			end
		elseif id == "extra" then
			local E = EXTRA[d.role]
			if #d.extra == 0 then emptyText(canvas, E.empty) end
			for _, e in ipairs(d.extra) do
				local sub = e.left and ("розыск ещё " .. math.max(0, math.ceil(e.left / 60)) .. " мин") or nil
				row(canvas, e.text, sub, col, { { "Метка", "map_pin", function() act(ent, "mark", tostring(e.id), E.name) end } })
			end
		elseif id == "fine" then
			local form = vgui.Create("DPanel", canvas)
			form:Dock(TOP)
			form:SetTall(UI.S(330))
			form.Paint = function(_, w, h)
				UI.RoundedRect(UI.S(12), 0, 0, w, h, Color(255, 255, 255, 6))
				draw.SimpleText("Протокол об административном нарушении NYPD", NYRP.Font("bold", 17), UI.S(16), UI.S(14), color_white)
				draw.SimpleText("Штраф ляжет на банковский счёт нарушителя (раздел «Штрафы» в банке).", NYRP.Font("regular", 12), UI.S(16), UI.S(40), UI.Col.dim)
				draw.SimpleText("Нарушитель", NYRP.Font("medium", 13), UI.S(16), UI.S(70), UI.Col.dim)
				draw.SimpleText("Сумма, $", NYRP.Font("medium", 13), UI.S(16), UI.S(140), UI.Col.dim)
				draw.SimpleText("Статья / причина", NYRP.Font("medium", 13), UI.S(16), UI.S(210), UI.Col.dim)
			end
			local who = vgui.Create("DComboBox", form)
			who:SetPos(UI.S(16), UI.S(92))
			who:SetSize(UI.S(380), UI.S(36))
			who:SetFont(NYRP.Font("medium", 15))
			who:SetValue("выберите человека")
			for _, n in ipairs(d.people or {}) do who:AddChoice(n) end
			local amount = vgui.Create("NYRP.TextEntry", form)
			amount:SetPos(UI.S(16), UI.S(162))
			amount:SetSize(UI.S(180), UI.S(36))
			amount:SetNumeric(true)
			amount:SetValue("100")
			local reason = vgui.Create("NYRP.TextEntry", form)
			reason:SetPos(UI.S(16), UI.S(232))
			reason:SetSize(UI.S(560), UI.S(36))
			reason:SetPlaceholderText("например: нарушение общественного порядка")
			win:SetKeyboardInputEnabled(true)
			local send = UI.AddButton(form, "Выписать штраф", "clipboard", function()
				local name = who:GetSelected()
				if not name then return end
				act(ent, "fine", name, amount:GetValue(), reason:GetValue())
			end, { dock = false, style = "solid", accent = col })
			send:SetPos(UI.S(16), UI.S(282))
			send:SetSize(UI.S(240), UI.S(38))
		end
	end

	for _, t in ipairs(tabs) do
		local b = UI.AddButton(side, t.name, t.icon, function() show(t.id) end, { accent = col })
		b.Think = function(s) s:SetStyle(win.Tab == t.id and "solid" or "ghost") end
	end
	-- шапка службы и смена
	local badge = vgui.Create("DPanel", side)
	badge:Dock(BOTTOM)
	badge:SetTall(UI.S(110))
	badge.Paint = function(_, w, h)
		UI.RoundedRect(UI.S(12), 0, 0, w, h, UI.Alpha(col, 24))
		if R and R.Icon then statusIcon(R.Icon, w / 2, UI.S(36), UI.S(48), col) end
		draw.SimpleText(R and R.Name or d.role, NYRP.Font("bold", 15), w / 2, UI.S(76), color_white, TEXT_ALIGN_CENTER)
	end
	local duty = UI.AddButton(side, onDuty and "Закончить дежурство" or "Заступить на дежурство", onDuty and "logout" or "play",
		function() act(ent, "duty") end, { dock = BOTTOM, accent = onDuty and UI.Col.red or col, style = "solid" })
	duty:DockMargin(0, UI.S(8), 0, UI.S(8))
	local re = UI.AddButton(side, "Обновить", "refresh", function() act(ent, "refresh") end, { dock = BOTTOM })
	re:DockMargin(0, UI.S(8), 0, 0)

	local ok = false
	for _, t in ipairs(tabs) do if t.id == keepTab then ok = true end end
	show(ok and keepTab or "charter")
end)

-- подсказка в руках у задержанного
hook.Add("HUDPaint", "nyrp.cuffs", function()
	local ply = LocalPlayer()
	if not IsValid(ply) or not F.Cuffed(ply) then return end
	local w, h = ScrW(), ScrH()
	local tw = UI.S(300)
	UI.RoundedRect(UI.S(12), w / 2 - tw / 2, h - UI.S(150), tw, UI.S(44), Color(10, 12, 20, 210))
	statusIcon("handcuffs", w / 2 - tw / 2 + UI.S(26), h - UI.S(128), UI.S(26), Color(230, 70, 60))
	draw.SimpleText("Вы в наручниках", NYRP.Font("semibold", 16), w / 2 - tw / 2 + UI.S(50), h - UI.S(128), color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end)

-- ---------------------------------------------------- меню задержанного (R) --
local function pact(t, a, x, y)
	net.Start("nyrp.police.act")
	net.WriteEntity(t)
	net.WriteString(a)
	net.WriteString(x or "")
	net.WriteString(y or "")
	net.SendToServer()
end

local function jailForm(t)
	local win, body = UI.Window("Помещение в КПЗ", "lock", 520, 330, { keyboard = true })
	local mins = 5
	local row = vgui.Create("DPanel", body)
	row:Dock(TOP)
	row:SetTall(UI.S(44))
	row.Paint = function() end
	for _, m in ipairs({ 3, 5, 10, 15, 20 }) do
		local b = UI.AddButton(row, m .. " мин", nil, function() mins = m end, { dock = LEFT })
		b:SetWide(UI.S(88))
		b:DockMargin(0, 0, UI.S(6), 0)
		b.Think = function(s) s:SetStyle(mins == m and "solid" or "ghost") end
	end
	local lbl = vgui.Create("DLabel", body)
	lbl:Dock(TOP)
	lbl:DockMargin(0, UI.S(14), 0, UI.S(6))
	lbl:SetFont(NYRP.Font("medium", 14))
	lbl:SetTextColor(UI.Col.dim)
	lbl:SetText("Статья / основание задержания")
	local reason = vgui.Create("NYRP.TextEntry", body)
	reason:Dock(TOP)
	reason:SetTall(UI.S(38))
	reason:SetPlaceholderText("например: ограбление магазина, сопротивление полиции")
	local go = UI.AddButton(body, "Поместить в КПЗ", "lock", function()
		pact(t, "jail", tostring(mins), reason:GetValue())
		win:Close()
	end, { dock = BOTTOM, style = "solid", accent = Color(70, 120, 230) })
	go:DockMargin(0, UI.S(12), 0, 0)
end

net.Receive("nyrp.police.menu", function()
	local t, hasJail = net.ReadEntity(), net.ReadBool()
	if not IsValid(t) then return end
	local led = false
	UI.Menu({
		{ text = "Обыскать", icon = "hand", func = function() pact(t, "search") end },
		{ text = "Вести / отпустить", icon = "walk", func = function() pact(t, "lead") end },
		{ text = hasJail and "Поместить в КПЗ" or "КПЗ не настроено", icon = "lock", disabled = not hasJail, func = function() jailForm(t) end },
		{ divider = true },
		{ text = "Снять наручники", icon = "unlock", color = UI.Col.red, func = function() pact(t, "uncuff") end },
	}, ScrW() / 2 + UI.S(20), ScrH() / 2)
end)

-- результат обыска
net.Receive("nyrp.police.search", function()
	local t, items, money = net.ReadEntity(), net.ReadTable(), net.ReadUInt(32)
	if IsValid(F.Search) then F.Search:Remove() end
	local win, body = UI.Window("Обыск", "hand", 560, 560, { sub = "наличные: " .. NYRP.Money.Format(money) })
	F.Search = win
	local list = vgui.Create("NYRP.Scroll", body)
	list:Dock(FILL)
	if #items == 0 then emptyText(list, "Ничего не найдено") end
	table.sort(items, function(a, b) return (a.cat == "weapon" and 0 or 1) < (b.cat == "weapon" and 0 or 1) end)
	for _, it in ipairs(items) do
		local danger = it.cat == "weapon"
		row(list, it.name .. (it.n > 1 and (" ×" .. it.n) or ""), it.worn and "надето / в руках" or "в сумке",
			danger and Color(230, 70, 60) or UI.Col.dim,
			{ { "Изъять", "box", function() pact(t, "take", it.key) end, danger and Color(230, 70, 60) or nil, nil, 120 } })
	end
end)

-- -------------------------------------------- наручники на запястьях --
local cuffMdl
hook.Add("PostPlayerDraw", "nyrp.cuffs.model", function(ply)
	if not F.Cuffed(ply) then return end
	local l, r = ply:LookupBone("ValveBiped.Bip01_L_Hand"), ply:LookupBone("ValveBiped.Bip01_R_Hand")
	local ml, mr = l and ply:GetBoneMatrix(l), r and ply:GetBoneMatrix(r)
	if not ml or not mr then return end
	if not IsValid(cuffMdl) then
		cuffMdl = ClientsideModel("models/nyrp/city/handcuffs.mdl", RENDERGROUP_OPAQUE)
		if not IsValid(cuffMdl) then return end
		cuffMdl:SetNoDraw(true)
	end
	local a, b = ml:GetTranslation(), mr:GetTranslation()
	local dir = (b - a):GetNormalized()
	local ang = dir:Angle()
	ang:RotateAroundAxis(ang:Up(), 90)       -- ось «браслет—браслет» модели — Y
	cuffMdl:SetPos((a + b) / 2)
	cuffMdl:SetAngles(ang)
	cuffMdl:SetupBones()
	cuffMdl:DrawModel()
end)

-- ------------------------------------------------------ КПЗ: таймер --
hook.Add("HUDPaint", "nyrp.jail", function()
	local ply = LocalPlayer()
	local u = IsValid(ply) and ply:GetNW2Float("nyrp.jailUntil", 0) or 0
	if u <= CurTime() then return end
	local left = math.ceil(u - CurTime())
	local w = UI.S(340)
	local x, y = ScrW() / 2 - w / 2, UI.S(40)
	UI.RoundedRect(UI.S(12), x, y, w, UI.S(64), Color(10, 12, 20, 220))
	statusIcon("handcuffs", x + UI.S(32), y + UI.S(32), UI.S(32), Color(70, 120, 230))
	draw.SimpleText(string.format("КПЗ: %d:%02d", math.floor(left / 60), left % 60), NYRP.Font("bold", 20), x + UI.S(60), y + UI.S(20), color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	draw.SimpleText(ply:GetNW2String("nyrp.jailReason", ""), NYRP.Font("regular", 13), x + UI.S(60), y + UI.S(44), UI.Col.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end)

-- --------------------------------------- метки дежурным: EMS и FDNY --
local function marker(pos, icon, col, text)
	local sc = (pos + Vector(0, 0, 40)):ToScreen()
	if not sc.visible then return end
	local d = math.floor(LocalPlayer():GetPos():Distance(pos) * 0.019)
	local s = UI.S(26)
	UI.Circle(sc.x, sc.y, s * 0.75, Color(10, 12, 20, 190))
	statusIcon(icon, sc.x, sc.y, s, col)
	draw.SimpleTextOutlined(text .. " · " .. d .. " м", NYRP.Font("semibold", 13), sc.x, sc.y + s, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 160))
end

hook.Add("HUDPaint", "nyrp.duty.markers", function()
	local ply = LocalPlayer()
	if not IsValid(ply) or not ply:GetNW2Bool("nyrp.onDuty") then return end
	local r = ply:GetNW2String("nyrp.role", "")
	if r == "medic" then
		for _, p in ipairs(player.GetAll()) do
			if p ~= ply and p:Alive() and p:GetNW2Bool("nyrp.ko") and p:GetNW2Bool("nyrp.koCritical") then
				local rag = p:GetNW2Entity("nyrp.koRag")
				marker(IsValid(rag) and rag:GetPos() or p:GetPos(), "critical", Color(230, 70, 60), "Пострадавший")
			end
		end
		for _, rag in ipairs(ents.FindByClass("prop_ragdoll")) do
			if rag:GetNW2Bool("nyrp.corpse") and CurTime() - rag:GetNW2Float("nyrp.corpseTime", 0) < 30 then
				marker(rag:GetPos(), "critical", Color(255, 170, 60), "Остановка сердца")
			end
		end
	elseif r == "fire" then
		for _, e in ipairs(ents.FindByClass("nyrp_fire")) do
			marker(e:GetPos(), "fire", Color(255, 120, 40), "Пожар " .. math.floor(e:GetPower()) .. "%")
		end
	end
end)
