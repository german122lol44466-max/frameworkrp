--[[
	scp_edit на клиенте: все точки в мире (подписи, радиусы, направление) и панель слева.
	Удерживайте C — появляется курсор и можно нажимать. Выбрать точку или группу в списке → кнопки снизу.
]]

local S = WS.Story
local ED = { on = false, unsaved = false, ch = 0, step = 0, points = {}, groups = {}, sel = nil }
S.Editor = ED

local GOLD = Color(226, 190, 120)
local SET_COL = Color(120, 220, 150)
local AUTO_COL = Color(240, 170, 80)
local ENEMY_COL = Color(230, 90, 80)
local panel

local function sc() return ScrH() / 1080 end

local function op(name, fn)
	net.Start("ws.edit.op")
	net.WriteString(name)
	if fn then fn() end
	net.SendToServer()
	surface.PlaySound("buttons/lightswitch2.wav")
end

local function aimPos()
	local ply = LocalPlayer()
	local tr = util.TraceLine({ start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * 10000, filter = ply, mask = MASK_PLAYERSOLID })
	return tr.HitPos
end

local function feetPos()
	local ply = LocalPlayer()
	local tr = util.TraceLine({ start = ply:GetPos() + Vector(0, 0, 8), endpos = ply:GetPos() - Vector(0, 0, 4000), filter = ply, mask = MASK_PLAYERSOLID })
	return tr.Hit and tr.HitPos or ply:GetPos()
end

-- ---------------------------------------------------------------- данные

local buildPanel

net.Receive("ws.edit.state", function()
	local on = net.ReadBool()
	if not on then
		ED.on = false
		if IsValid(panel) then panel:Remove() end
		gui.EnableScreenClicker(false)
		return
	end
	ED.unsaved = net.ReadBool()
	ED.ch = net.ReadUInt(6)
	ED.step = net.ReadUInt(6)
	for i, def in ipairs(S.Points) do
		ED.points[i] = { def = def, pos = net.ReadVector(), yaw = net.ReadFloat(), r = net.ReadUInt(12), set = net.ReadBool() }
	end
	for i, g in ipairs(S.Groups) do
		local list = {}
		for k = 1, net.ReadUInt(8) do list[k] = { pos = net.ReadVector(), yaw = net.ReadFloat() } end
		ED.groups[i] = { def = g, spots = list }
	end
	local first = not ED.on
	ED.on = true
	if first and WS.Menu and WS.Menu.IsOpen() then WS.Menu.Close() end
	buildPanel()
end)

-- ---------------------------------------------------------------- мир

local function circle(pos, r, col)
	local prev
	for i = 0, 40 do
		local a = i / 40 * math.pi * 2
		local p = pos + Vector(math.cos(a) * r, math.sin(a) * r, 4)
		if prev then render.DrawLine(prev, p, col, true) end
		prev = p
	end
end

hook.Add("PostDrawTranslucentRenderables", "ws.editor", function(depth, sky)
	if not ED.on or depth or sky then return end
	render.SetColorMaterial()
	for i, p in ipairs(ED.points) do
		local sel = ED.sel and ED.sel.kind == "point" and ED.sel.i == i
		local col = sel and GOLD or (p.set and SET_COL or AUTO_COL)
		render.DrawSphere(p.pos + Vector(0, 0, 8), sel and 10 or 7, 10, 10, col)
		render.DrawLine(p.pos, p.pos + Vector(0, 0, sel and 220 or 120), col, true)
		local dir = Angle(0, p.yaw, 0):Forward()
		render.DrawLine(p.pos + Vector(0, 0, 10), p.pos + Vector(0, 0, 10) + dir * 48, col, true)
		if p.r > 0 and p.def.r then circle(p.pos, p.r, Color(col.r, col.g, col.b, sel and 255 or 90)) end
	end
	for gi, g in ipairs(ED.groups) do
		local sel = ED.sel and ED.sel.kind == "group" and ED.sel.i == gi
		for _, sp in ipairs(g.spots) do
			local col = sel and GOLD or ENEMY_COL
			render.DrawBox(sp.pos, Angle(0, sp.yaw, 0), Vector(-12, -12, 0), Vector(12, 12, 72), Color(col.r, col.g, col.b, sel and 70 or 35))
			render.DrawLine(sp.pos + Vector(0, 0, 60), sp.pos + Vector(0, 0, 60) + Angle(0, sp.yaw, 0):Forward() * 40, col, true)
		end
	end
end)

hook.Add("HUDPaint", "ws.editor", function()
	if not ED.on then return end
	local s = sc()
	local eye = EyePos()
	local function label(pos, text, sub, col)
		local d = eye:Distance(pos)
		if d > 8000 then return end
		local sp = pos:ToScreen()
		if not sp.visible then return end
		local a = math.Clamp(1 - d / 8000, 0.35, 1)
		draw.SimpleTextOutlined(text, WS.Font("menusemi", 16), sp.x, sp.y, Color(col.r, col.g, col.b, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, 200 * a))
		if sub then
			draw.SimpleTextOutlined(sub, WS.Font("menulight", 13), sp.x, sp.y + 2, Color(220, 224, 230, 220 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 200 * a))
		end
	end
	for i, p in ipairs(ED.points) do
		local sel = ED.sel and ED.sel.kind == "point" and ED.sel.i == i
		label(p.pos + Vector(0, 0, sel and 230 or 130), p.def.id, p.def.name .. (p.set and "" or "  (авто)"), sel and GOLD or (p.set and SET_COL or AUTO_COL))
	end
	for gi, g in ipairs(ED.groups) do
		for k, sp in ipairs(g.spots) do
			label(sp.pos + Vector(0, 0, 84), g.def.id .. " #" .. k, nil, ENEMY_COL)
		end
	end
	-- подсказка
	local w = ScrW()
	draw.SimpleTextOutlined("SCP_EDIT  ·  C — панель  ·  " .. (ED.unsaved and "есть несохранённые изменения" or "сохранено"),
		WS.Font("menusemi", 16), w / 2, 18 * s, ED.unsaved and AUTO_COL or SET_COL, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 200))
	local tp = aimPos():ToScreen()
	surface.SetDrawColor(GOLD)
	surface.DrawRect(tp.x - 6 * s, tp.y, 12 * s, 1)
	surface.DrawRect(tp.x, tp.y - 6 * s, 1, 12 * s)
end)

-- ---------------------------------------------------------------- панель

local function button(parent, text, fn, col)
	local b = vgui.Create("DButton", parent)
	b:SetText("")
	b:SetTall(30 * sc())
	b.Paint = function(self, w, h)
		local hov = self:IsHovered()
		draw.RoundedBox(3, 0, 0, w, h, Color(255, 255, 255, hov and 28 or 10))
		local c = col or Color(230, 234, 240)
		draw.SimpleText(text, WS.Font("menusemi", 16), w / 2, h / 2, Color(c.r, c.g, c.b, hov and 255 or 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		return true
	end
	b.DoClick = fn
	return b
end

local function row(parent, text, sub, col, selected, fn)
	local r = vgui.Create("DButton", parent)
	r:SetText("")
	r:Dock(TOP)
	r:DockMargin(0, 0, 0, 2)
	r:SetTall(36 * sc())
	r.Paint = function(self, w, h)
		draw.RoundedBox(3, 0, 0, w, h, Color(255, 255, 255, selected() and 34 or (self:IsHovered() and 16 or 6)))
		surface.SetDrawColor(col().r, col().g, col().b, 230)
		surface.DrawRect(0, 0, 3, h)
		draw.SimpleText(text, WS.Font("menusemi", 15), 10, h * 0.32, Color(236, 240, 246), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText(sub(), WS.Font("menulight", 13), 10, h * 0.72, Color(170, 178, 190), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		return true
	end
	r.DoClick = fn
	return r
end

local function header(parent, text)
	local h = vgui.Create("DPanel", parent)
	h:Dock(TOP)
	h:SetTall(28 * sc())
	h.Paint = function(_, w, hh)
		draw.SimpleText(text, WS.Font("menubold", 15), 2, hh * 0.6, GOLD, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
end

local function actions(box)
	box:Clear()
	local s = sc()
	local function add(text, fn, col)
		local b = button(box, text, fn, col)
		b:Dock(TOP)
		b:DockMargin(0, 0, 0, 3 * s)
	end
	local sel = ED.sel
	if sel and sel.kind == "point" then
		local p = ED.points[sel.i]
		local id = p.def.id
		add("Поставить здесь (под ногами)", function() op("set", function() net.WriteString(id) net.WriteVector(feetPos()) net.WriteFloat(EyeAngles().y) end) end)
		add("Поставить, куда смотрю", function() op("set", function() net.WriteString(id) net.WriteVector(aimPos()) net.WriteFloat(EyeAngles().y) end) end)
		if p.def.r then
			add("Радиус: −50", function() op("radius", function() net.WriteString(id) net.WriteUInt(math.max(50, p.r - 50), 12) end) end)
			add("Радиус: +50", function() op("radius", function() net.WriteString(id) net.WriteUInt(math.min(3000, p.r + 50), 12) end) end)
		end
		add("Телепорт к точке", function() op("tp", function() net.WriteVector(p.pos) end) end)
		add("Сбросить (авто)", function() op("reset", function() net.WriteString(id) end) end, AUTO_COL)
	elseif sel and sel.kind == "group" then
		local g = ED.groups[sel.i]
		local gid = g.def.id
		add("Добавить точку здесь", function() op("gadd", function() net.WriteString(gid) net.WriteVector(feetPos()) net.WriteFloat(EyeAngles().y) end) end)
		add("Добавить, куда смотрю", function() op("gadd", function() net.WriteString(gid) net.WriteVector(aimPos()) net.WriteFloat(EyeAngles().y) end) end)
		add("Удалить ближайшую", function()
			local best, bd
			for k, sp in ipairs(g.spots) do
				local d = sp.pos:DistToSqr(LocalPlayer():GetPos())
				if not bd or d < bd then best, bd = k, d end
			end
			if best then op("gdel", function() net.WriteString(gid) net.WriteUInt(best, 8) end) end
		end)
		add("Очистить группу", function() op("gclear", function() net.WriteString(gid) end) end, ENEMY_COL)
		add("Тест: 3 врага", function() op("test", function() net.WriteString(gid) end) end)
	else
		local l = vgui.Create("DLabel", box)
		l:Dock(TOP)
		l:SetTall(40 * s)
		l:SetWrap(true)
		l:SetFont(WS.Font("menulight", 14))
		l:SetTextColor(Color(170, 178, 190))
		l:SetText("Выберите точку или группу врагов в списке.")
	end
end

buildPanel = function()
	local s = sc()
	local keepScroll = IsValid(panel) and panel.scroll and panel.scroll:GetVBar():GetScroll() or 0
	if IsValid(panel) then panel:Remove() end
	panel = vgui.Create("DPanel")
	panel:SetSize(360 * s, ScrH() - 80 * s)
	panel:SetPos(20 * s, 50 * s)
	panel:SetMouseInputEnabled(true)
	panel.Paint = function(_, w, h)
		draw.RoundedBox(6, 0, 0, w, h, Color(8, 10, 14, 225))
		surface.SetDrawColor(255, 255, 255, 16)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
		draw.SimpleText("РЕДАКТОР ТОЧЕК", WS.Font("menubold", 22), 14 * s, 14 * s, Color(238, 240, 244))
		draw.SimpleText(game.GetMap() .. (ED.ch > 0 and string.format("  ·  глава %d, шаг %d", ED.ch, ED.step) or "  ·  сюжет остановлен"),
			WS.Font("menulight", 14), 14 * s, 42 * s, Color(170, 178, 190))
	end

	local foot = vgui.Create("DPanel", panel)
	foot:Dock(BOTTOM)
	foot:DockMargin(10 * s, 0, 10 * s, 10 * s)
	foot:SetTall(170 * s)
	foot.Paint = nil
	local grid = {
		{ ED.unsaved and "Сохранить *" or "Сохранить", function() op("save") end, ED.unsaved and GOLD or SET_COL },
		{ "Заполнить пустые", function() op("auto") end },
		{ "Сюжет ▸", function()
			local m = DermaMenu()
			for i, ch in ipairs(S.Chapters) do m:AddOption(string.format("%s. %s", S.Roman[i], ch.title), function() op("story", function() net.WriteUInt(i, 6) end) end) end
			m:AddSpacer()
			m:AddOption("Остановить", function() op("story", function() net.WriteUInt(0, 6) end) end)
			m:Open()
		end },
		{ "Убрать врагов", function() op("clear") end },
		{ "Загрузить из файла", function() op("reload") end },
		{ "Полёт вкл/выкл", function() op("fly") end },
		{ "Выход", function() RunConsoleCommand("scp_edit") end, ENEMY_COL },
	}
	local bw = (360 * s - 20 * s - 6 * s) / 2
	for i, g in ipairs(grid) do
		local b = button(foot, g[1], g[2], g[3])
		b:SetSize(i == #grid and bw * 2 + 6 * s or bw, 30 * s)
		b:SetPos(((i - 1) % 2) * (bw + 6 * s), math.floor((i - 1) / 2) * 34 * s + 30 * s)
	end
	local fh = vgui.Create("DPanel", foot)
	fh:SetPos(0, 0)
	fh:SetSize(360 * s, 26 * s)
	fh.Paint = function(_, w, h) draw.SimpleText("ОБЩЕЕ", WS.Font("menubold", 15), 2, h / 2, GOLD, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end

	local act = vgui.Create("DPanel", panel)
	act:Dock(BOTTOM)
	act:DockMargin(10 * s, 0, 10 * s, 8 * s)
	act:SetTall(210 * s)
	act.Paint = nil
	actions(act)

	local scroll = vgui.Create("DScrollPanel", panel)
	scroll:Dock(FILL)
	scroll:DockMargin(10 * s, 64 * s, 10 * s, 8 * s)
	panel.scroll = scroll
	header(scroll, "СЮЖЕТНЫЕ ТОЧКИ")
	for i, p in ipairs(ED.points) do
		row(scroll, p.def.id, function()
			local q = ED.points[i]
			return q.def.name .. (q.set and "" or "  ·  авто") .. (q.def.r and ("  ·  r " .. q.r) or "")
		end, function() return ED.points[i].set and SET_COL or AUTO_COL end,
		function() return ED.sel and ED.sel.kind == "point" and ED.sel.i == i end,
		function() ED.sel = { kind = "point", i = i } actions(act) end)
	end
	header(scroll, "ГРУППЫ ВРАГОВ")
	for i, g in ipairs(ED.groups) do
		row(scroll, g.def.id, function()
			local n = #ED.groups[i].spots
			return g.def.name .. "  ·  " .. (n > 0 and (n .. " точ.") or "вокруг цели")
		end, function() return ENEMY_COL end,
		function() return ED.sel and ED.sel.kind == "group" and ED.sel.i == i end,
		function() ED.sel = { kind = "group", i = i } actions(act) end)
	end
	timer.Simple(0, function() if IsValid(scroll) then scroll:GetVBar():SetScroll(keepScroll) end end)
end

-- C — курсор для панели (вместо контекстного меню песочницы)
hook.Add("OnContextMenuOpen", "ws.editor", function()
	if not ED.on then return end
	gui.EnableScreenClicker(true)
	return false
end)

hook.Add("OnContextMenuClose", "ws.editor", function()
	if not ED.on then return end
	gui.EnableScreenClicker(false)
	return false
end)

hook.Add("HUDShouldDraw", "ws.editor", function(name)
	if ED.on and name == "CHudCrosshair" then return false end
end)
