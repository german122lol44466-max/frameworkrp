--[[
	Редактор NPC для админов: C → ПКМ по NPC → «Настроить NPC».
	Вкладки: Основное (тип, имя, описание, модель, анимация с превью), Диалог (реплики и ответы),
	Торговля (что продаёт и за что), Задания (принести предмет / дойти до точки, награда, реплики).
]]

local UI = NYRP.UI
local N = NYRP.NPC
local Items = NYRP.Items

local E = {}   -- состояние редактора
local ACCENT = Color(247, 198, 0)

-- --------------------------------------------------------- мелкие элементы --
local function label(parent, text, small)
	local l = vgui.Create("DLabel", parent)
	l:SetText(text)
	l:SetFont(NYRP.Font(small and "regular" or "semibold", small and 13 or 15))
	l:SetTextColor(small and UI.Col.faint or UI.Col.dim)
	l:SizeToContents()
	return l
end

local function entry(parent, value, onChange, multiline)
	local e = vgui.Create("NYRP.TextEntry", parent)
	e:SetText(value or "")
	e:SetUpdateOnType(true)
	if multiline then
		e:SetMultiline(true)
		e:SetTall(UI.S(90))
		e:SetVerticalScrollbarEnabled(true)
	end
	e.OnValueChange = function(_, v) onChange(v) end
	return e
end

-- Поиск-список: всплывающее окно с поиском (для предметов, анимаций, моделей).
local function pickFrom(title, options, onPick)
	local f = vgui.Create("EditablePanel")
	f:SetSize(UI.S(420), UI.S(520))
	f:Center()
	f:MakePopup()
	f:SetZPos(32000)
	f.Paint = function(_, w, h)
		UI.RoundedRect(UI.S(12), 0, 0, w, h, Color(16, 18, 28, 250))
		UI.Outline(UI.S(12), 0, 0, w, h, UI.Col.stroke, 1)
		draw.SimpleText(title, NYRP.Font("title", 18), UI.S(16), UI.S(22), UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	f.OnKeyCodePressed = function(s, k) if k == KEY_ESCAPE then s:Remove() end end
	f.OnFocusChanged = function(s, gained) if not gained then timer.Simple(0, function() if IsValid(s) and not s:HasHierarchicalFocus() then s:Remove() end end) end end
	local close = vgui.Create("NYRP.IconButton", f)
	close:SetSize(UI.S(28), UI.S(28))
	close:SetPos(f:GetWide() - UI.S(40), UI.S(8))
	close.DoClick = function() f:Remove() end
	local search = vgui.Create("NYRP.TextEntry", f)
	search:SetPos(UI.S(12), UI.S(44))
	search:SetSize(f:GetWide() - UI.S(24), UI.S(36))
	search:SetPlaceholderText("Поиск...")
	search:SetUpdateOnType(true)
	local scroll = vgui.Create("NYRP.Scroll", f)
	scroll:SetPos(UI.S(12), UI.S(88))
	scroll:SetSize(f:GetWide() - UI.S(24), f:GetTall() - UI.S(100))
	local function fill(filter)
		scroll:Clear()
		filter = string.lower(filter or "")
		for _, o in ipairs(options) do
			if filter == "" or string.find(string.lower(o[2] .. " " .. tostring(o[1])), filter, 1, true) then
				local b = scroll:Add("DButton")
				b:Dock(TOP)
				b:SetTall(UI.S(30))
				b:SetText("")
				b.Paint = function(s, w, h)
					if s:IsHovered() then UI.RoundedRect(UI.S(6), 0, 0, w - UI.S(8), h, Color(255, 255, 255, 16)) end
					draw.SimpleText(o[2], NYRP.Font("medium", 14), UI.S(10), h / 2, UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					if o[1] and o[2] ~= o[1] then draw.SimpleText(tostring(o[1]), NYRP.Font("regular", 12), w - UI.S(16), h / 2, UI.Col.faint, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
				end
				b.DoClick = function() onPick(o[1]) UI.Sound("click") f:Remove() end
			end
		end
	end
	search.OnValueChange = function(_, v) fill(v) end
	fill("")
	search:RequestFocus()
end

-- Кнопка-выбор: показывает текущее значение, по клику — список.
local function select(parent, title, getOptions, getValue, onPick)
	local b = vgui.Create("DButton", parent)
	b:SetText("")
	b:SetTall(UI.S(36))
	b.Paint = function(s, w, h)
		UI.RoundedRect(UI.S(8), 0, 0, w, h, Color(255, 255, 255, s:IsHovered() and 16 or 10))
		UI.Outline(UI.S(8), 0, 0, w, h, Color(255, 255, 255, 18), 1)
		local v = getValue()
		local text = v or "—"
		for _, o in ipairs(getOptions()) do if o[1] == v then text = o[2] break end end
		draw.SimpleText(text, NYRP.Font("medium", 15), UI.S(12), h / 2, UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		UI.DrawIcon("chevron_right", w - UI.S(16), h / 2, UI.S(14), UI.Col.dim)
	end
	b.DoClick = function() pickFrom(title, getOptions(), onPick) end
	return b
end

local function small(parent, text, onClick, col)
	local b = vgui.Create("DButton", parent)
	b:SetText("")
	b:SetTall(UI.S(32))
	b.Paint = function(s, w, h)
		local c = col or ACCENT
		UI.RoundedRect(UI.S(8), 0, 0, w, h, s:IsHovered() and UI.Alpha(c, 70) or UI.Alpha(c, 30))
		draw.SimpleText(text, NYRP.Font("semibold", 14), w / 2, h / 2, UI.Col.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	b.DoClick = function() UI.Sound("click") onClick() end
	return b
end

local function itemOptions(withNone)
	local out = {}
	if withNone then out[1] = { false, "— нет —" } end
	local ids = table.GetKeys(Items.List)
	table.sort(ids)
	for _, id in ipairs(ids) do out[#out + 1] = { id, Items.Get(id).name } end
	return out
end

local MODELS = {
	"models/player/group01/male_01.mdl", "models/player/group01/male_02.mdl", "models/player/group01/male_03.mdl",
	"models/player/group01/male_04.mdl", "models/player/group01/male_05.mdl", "models/player/group01/male_06.mdl",
	"models/player/group01/male_07.mdl", "models/player/group01/male_08.mdl", "models/player/group01/male_09.mdl",
	"models/player/group01/female_01.mdl", "models/player/group01/female_02.mdl", "models/player/group01/female_03.mdl",
	"models/player/group01/female_04.mdl", "models/player/group01/female_06.mdl", "models/player/group03/male_04.mdl",
	"models/player/barney.mdl", "models/player/breen.mdl", "models/player/eli.mdl", "models/player/kleiner.mdl",
	"models/player/monk.mdl", "models/player/odessa.mdl", "models/player/mossman.mdl", "models/player/gman_high.mdl",
}

local function sequenceOptions(model)
	local ent = ClientsideModel(model, RENDERGROUP_OTHER)
	if not IsValid(ent) then return {} end
	local out = {}
	for _, name in pairs(ent:GetSequenceList() or {}) do out[#out + 1] = { name, name } end
	ent:Remove()
	table.sort(out, function(a, b)
		local ai, bi = string.find(a[1], "idle") or string.find(a[1], "pose"), string.find(b[1], "idle") or string.find(b[1], "pose")
		if (ai ~= nil) ~= (bi ~= nil) then return ai ~= nil end
		return a[1] < b[1]
	end)
	return out
end

-- ---------------------------------------------------------------- вкладки --
local TABS = {}

-- Основное: тип, имя, описание, модель, анимация + превью.
TABS[1] = { "Основное", "user", function(body)
	local d = E.data
	local left = vgui.Create("DPanel", body)
	left:Dock(LEFT)
	left:SetWide(UI.S(420))
	left.Paint = function() end
	local function row(text, pnl)
		local l = label(left, text)
		l:Dock(TOP)
		l:DockMargin(0, UI.S(10), 0, UI.S(4))
		pnl:SetParent(left)
		pnl:Dock(TOP)
		return pnl
	end
	row("Тип", select(left, "Тип NPC", function() return { { "trader", "Торговец" }, { "talk", "Собеседник" } } end,
		function() return d.kind end, function(v) d.kind = v end))
	row("Имя", entry(left, d.name, function(v) d.name = v end))
	row("Описание (видно под именем)", entry(left, d.desc, function(v) d.desc = v end, true))
	row("Модель", select(left, "Модель", function()
		local o = {}
		for _, m in ipairs(MODELS) do o[#o + 1] = { m, string.match(m, "([^/]+)%.mdl$") } end
		return o
	end, function() return d.model end, function(v) d.model = v E.seqs = nil if IsValid(E.preview) then E.preview:SetModel(v) end end))
	local custom = row("Своя модель (путь .mdl)", entry(left, d.model, function(v)
		if string.match(v, "^models/.+%.mdl$") then d.model = v E.seqs = nil if IsValid(E.preview) then E.preview:SetModel(v) end end
	end))
	custom:SetPlaceholderText("models/...mdl")
	row("Анимация (sequence)", select(left, "Анимация", function()
		E.seqs = E.seqs or sequenceOptions(d.model)
		return E.seqs
	end, function() return d.seq end, function(v) d.seq = v end))
	row("Голос (озвучка реплик)", select(left, "Голос", function()
		local o = {}
		local srv = GetConVar("nyrp_tts_server") and GetConVar("nyrp_tts_server"):GetString() or ""
		for _, v in ipairs(N.Voices) do
			local name = v.name
			if v.engine == "piper" and srv == "" then name = name .. " — нужен сервер nyrp_tts_server" end
			o[#o + 1] = { v.id, name }
		end
		return o
	end, function() return d.voice or "" end, function(v) d.voice = v end))
	local listen = small(left, "Прослушать голос", function()
		local node = d.dialog and d.dialog.nodes and d.dialog.nodes[d.dialog.start or "start"]
		N.Speak(nil, node and node.text or "Привет! Чем могу помочь?", d.voice or "")
	end)
	listen:SetParent(left)
	listen:Dock(TOP)
	listen:DockMargin(0, UI.S(6), 0, 0)

	-- превью
	local pv = vgui.Create("DModelPanel", body)
	E.preview = pv
	pv:Dock(FILL)
	pv:DockMargin(UI.S(20), 0, 0, 0)
	pv:SetModel(d.model)
	pv:SetFOV(32)
	pv:SetCursor("sizewe")
	pv.Yaw = 20
	local paint = pv.Paint
	pv.Paint = function(s, w, h)
		UI.RoundedRect(UI.S(12), 0, 0, w, h, Color(0, 0, 0, 70))
		paint(s, w, h)
		draw.SimpleText(d.name, NYRP.Font("tag", 22), w / 2, h - UI.S(46), UI.Col.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		draw.SimpleText(d.seq, NYRP.Font("regular", 12), w / 2, h - UI.S(22), UI.Col.faint, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	pv.LayoutEntity = function(s, ent)
		local seq = ent:LookupSequence(d.seq)
		if seq >= 0 and ent:GetSequence() ~= seq then ent:ResetSequence(seq) end
		s:RunAnimation()
		ent:SetAngles(Angle(0, s.Yaw, 0))
		s:SetCamPos(Vector(110, 0, 50))
		s:SetLookAt(Vector(0, 0, 38))
	end
	pv.OnMousePressed = function(s) s.Drag = gui.MouseX() s:MouseCapture(true) end
	pv.OnMouseReleased = function(s) s.Drag = nil s:MouseCapture(false) end
	pv.Think = function(s) if s.Drag then s.Yaw = s.Yaw + (gui.MouseX() - s.Drag) * 0.6 s.Drag = gui.MouseX() end end
end }

-- Диалог: реплики слева, справа — текст реплики и ответы.
TABS[2] = { "Диалог", "message", function(body)
	local d = E.data
	local nodes = d.dialog.nodes
	E.node = E.node and nodes[E.node] and E.node or d.dialog.start
	local list = vgui.Create("DPanel", body)
	list:Dock(LEFT)
	list:SetWide(UI.S(220))
	list.Paint = function(_, w, h) UI.RoundedRect(UI.S(10), 0, 0, w, h, Color(0, 0, 0, 60)) end
	local right = vgui.Create("NYRP.Scroll", body)
	right:Dock(FILL)
	right:DockMargin(UI.S(16), 0, 0, 0)

	local function nodeOptions()
		local o = {}
		local ids = table.GetKeys(nodes)
		table.sort(ids)
		for _, id in ipairs(ids) do o[#o + 1] = { id, id .. (id == d.dialog.start and "  (начало)" or "") } end
		return o
	end
	local function questOptions()
		local o = {}
		for id, q in pairs(d.quests) do o[#o + 1] = { id, q.name ~= "" and q.name or id } end
		return o
	end

	local rebuild
	local function buildList()
		list:Clear()
		local head = label(list, "РЕПЛИКИ")
		head:Dock(TOP)
		head:DockMargin(UI.S(12), UI.S(10), 0, UI.S(6))
		for _, o in ipairs(nodeOptions()) do
			local b = vgui.Create("DButton", list)
			b:Dock(TOP)
			b:DockMargin(UI.S(6), 0, UI.S(6), UI.S(4))
			b:SetTall(UI.S(30))
			b:SetText("")
			b.Paint = function(s, w, h)
				local on = E.node == o[1]
				UI.RoundedRect(UI.S(6), 0, 0, w, h, on and UI.Alpha(ACCENT, 60) or Color(255, 255, 255, s:IsHovered() and 12 or 0))
				draw.SimpleText(o[2], NYRP.Font("medium", 14), UI.S(10), h / 2, on and UI.Col.text or UI.Col.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
			b.DoClick = function() E.node = o[1] rebuild() end
		end
		local add = small(list, "+ реплика", function()
			local i = 1
			while nodes["node" .. i] do i = i + 1 end
			nodes["node" .. i] = { text = "", options = { { text = "Назад.", act = "goto", arg = d.dialog.start } } }
			E.node = "node" .. i
			rebuild()
		end)
		add:Dock(BOTTOM)
		add:DockMargin(UI.S(8), 0, UI.S(8), UI.S(8))
	end

	local function buildNode()
		right:Clear()
		local node = nodes[E.node]
		if not node then return end
		local function add(p, top) right:AddItem(p) p:Dock(TOP) p:DockMargin(0, top or UI.S(6), UI.S(10), 0) return p end
		local hdr = vgui.Create("DPanel")
		hdr:SetTall(UI.S(36))
		hdr.Paint = function(_, w, h)
			draw.SimpleText("Реплика «" .. E.node .. "»", NYRP.Font("title", 18), 0, h / 2, UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		add(hdr, 0)
		if E.node ~= d.dialog.start then
			local mk = small(hdr, "Сделать начальной", function() d.dialog.start = E.node rebuild() end)
			mk:Dock(RIGHT)
			mk:SetWide(UI.S(170))
			local del = small(hdr, "Удалить", function() nodes[E.node] = nil E.node = d.dialog.start rebuild() end, UI.Col.red)
			del:Dock(RIGHT)
			del:DockMargin(0, 0, UI.S(8), 0)
			del:SetWide(UI.S(100))
		end
		add(label(nil, "Что говорит NPC"), UI.S(8))
		add(entry(nil, node.text, function(v) node.text = v end, true))
		add(label(nil, "Ответы игрока (до 8)"), UI.S(14))
		local acts = {}
		for _, a in ipairs(N.Acts) do acts[#acts + 1] = { a[1], a[2] } end
		for i, o in ipairs(node.options) do
			local row = vgui.Create("DPanel")
			row:SetTall(UI.S(36))
			row.Paint = function() end
			add(row)
			local t = entry(row, o.text, function(v) o.text = v end)
			t:Dock(FILL)
			local del = small(row, "×", function() table.remove(node.options, i) buildNode() end, UI.Col.red)
			del:Dock(RIGHT)
			del:SetWide(UI.S(36))
			del:DockMargin(UI.S(6), 0, 0, 0)
			if o.act == "goto" or o.act == "quest" or o.act == "turnin" then
				local arg = select(row, o.act == "goto" and "К какой реплике" or "Какое задание",
					function() return o.act == "goto" and nodeOptions() or questOptions() end,
					function() return o.arg end, function(v) o.arg = v end)
				arg:Dock(RIGHT)
				arg:SetWide(UI.S(150))
				arg:DockMargin(UI.S(6), 0, 0, 0)
			end
			local act = select(row, "Что делает ответ", function() return acts end, function() return o.act end,
				function(v) o.act = v o.arg = nil buildNode() end)
			act:Dock(RIGHT)
			act:SetWide(UI.S(180))
			act:DockMargin(UI.S(6), 0, 0, 0)
		end
		if #node.options < 8 then
			local addOpt = small(nil, "+ ответ", function()
				node.options[#node.options + 1] = { text = "", act = "close" }
				buildNode()
			end)
			add(addOpt, UI.S(10))
		end
		local tip = label(nil, "«Дать задание» видно, пока задание не взято; «Сдать задание» — пока оно активно.", true)
		add(tip, UI.S(14))
	end
	rebuild = function() buildList() buildNode() end
	rebuild()
end }

-- Торговля: товар, количество, цена деньгами и/или предметом.
TABS[3] = { "Торговля", "g_give", function(body)
	local d = E.data
	local scroll = vgui.Create("NYRP.Scroll", body)
	scroll:Dock(FILL)
	local function build()
		scroll:Clear()
		local head = vgui.Create("DPanel")
		head:SetTall(UI.S(24))
		head.Paint = function(_, w, h)
			local cols = { { 0, "Товар" }, { 0.36, "Кол-во" }, { 0.46, "Цена, $" }, { 0.58, "+ предмет" }, { 0.84, "Кол-во" } }
			for _, c in ipairs(cols) do draw.SimpleText(c[2], NYRP.Font("semibold", 13), w * c[1], h / 2, UI.Col.faint, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
		end
		scroll:AddItem(head)
		head:Dock(TOP)
		for i, o in ipairs(d.trade) do
			local row = scroll:Add("DPanel")
			row:Dock(TOP)
			row:SetTall(UI.S(38))
			row:DockMargin(0, UI.S(4), UI.S(8), 0)
			row.Paint = function() end
			row.PerformLayout = function(s, w)
				local c = s.cells
				if not c then return end
				c[1]:SetPos(0, 0) c[1]:SetSize(w * 0.34, UI.S(36))
				c[2]:SetPos(w * 0.36, 0) c[2]:SetSize(w * 0.08, UI.S(36))
				c[3]:SetPos(w * 0.46, 0) c[3]:SetSize(w * 0.1, UI.S(36))
				c[4]:SetPos(w * 0.58, 0) c[4]:SetSize(w * 0.24, UI.S(36))
				c[5]:SetPos(w * 0.84, 0) c[5]:SetSize(w * 0.08, UI.S(36))
				c[6]:SetPos(w * 0.94, 0) c[6]:SetSize(w * 0.06, UI.S(36))
			end
			row.cells = {
				select(row, "Товар", function() return itemOptions(false) end, function() return o.item end, function(v) o.item = v end),
				entry(row, tostring(o.n or 1), function(v) o.n = tonumber(v) or 1 end),
				entry(row, tostring(o.money or 0), function(v) o.money = tonumber(v) or 0 end),
				select(row, "Предмет в оплату", function() return itemOptions(true) end, function() return o.costItem or false end,
					function(v) o.costItem = v or nil end),
				entry(row, tostring(o.costN or 1), function(v) o.costN = tonumber(v) or 1 end),
				small(row, "×", function() table.remove(d.trade, i) build() end, UI.Col.red),
			}
			for k = 2, 5, 3 do row.cells[k]:SetNumeric(true) end
			row.cells[3]:SetNumeric(true)
		end
		local add = small(nil, "+ товар", function()
			d.trade[#d.trade + 1] = { item = "water", n = 1, money = 10 }
			build()
		end)
		scroll:AddItem(add)
		add:Dock(TOP)
		add:DockMargin(0, UI.S(10), UI.S(8), 0)
		local tip = label(nil, "Цена может быть деньгами, предметом или и тем и другим. Покупка — через ответ «Открыть торговлю».", true)
		scroll:AddItem(tip)
		tip:Dock(TOP)
		tip:DockMargin(0, UI.S(12), 0, 0)
	end
	build()
end }

-- Задания.
TABS[4] = { "Задания", "check", function(body)
	local d = E.data
	local list = vgui.Create("DPanel", body)
	list:Dock(LEFT)
	list:SetWide(UI.S(220))
	list.Paint = function(_, w, h) UI.RoundedRect(UI.S(10), 0, 0, w, h, Color(0, 0, 0, 60)) end
	local right = vgui.Create("NYRP.Scroll", body)
	right:Dock(FILL)
	right:DockMargin(UI.S(16), 0, 0, 0)
	local rebuild
	local function buildRight()
		right:Clear()
		local q = E.quest and d.quests[E.quest]
		if not q then
			local l = label(nil, "Выберите или создайте задание. Потом добавьте в диалог ответы «Дать задание» и «Сдать задание».", true)
			right:AddItem(l)
			l:Dock(TOP)
			return
		end
		local function add(p, top) right:AddItem(p) p:Dock(TOP) p:DockMargin(0, top or UI.S(6), UI.S(10), 0) return p end
		local function lbl(t) return add(label(nil, t), UI.S(10)) end
		lbl("Название") add(entry(nil, q.name, function(v) q.name = v end))
		lbl("Описание (видно в списке заданий)") add(entry(nil, q.desc, function(v) q.desc = v end, true))
		lbl("Тип") add(select(nil, "Тип задания", function() return { { "bring", "Принести предмет" }, { "reach", "Дойти до точки" } } end,
			function() return q.type end, function(v) q.type = v buildRight() end))
		if q.type == "bring" then
			lbl("Что принести")
			add(select(nil, "Предмет", function() return itemOptions(false) end, function() return q.item end, function(v) q.item = v end))
			lbl("Сколько") local n = add(entry(nil, tostring(q.n or 1), function(v) q.n = tonumber(v) or 1 end)) n:SetNumeric(true)
		else
			lbl("Точка")
			local p = q.point or { x = 0, y = 0, z = 0 }
			local info = add(label(nil, string.format("x %.0f · y %.0f · z %.0f", p.x, p.y, p.z), true))
			add(small(nil, "Отметить точку там, где я стою", function()
				local pos = LocalPlayer():GetPos()
				q.point = { x = pos.x, y = pos.y, z = pos.z }
				info:SetText(string.format("x %.0f · y %.0f · z %.0f", pos.x, pos.y, pos.z))
				info:SizeToContents()
			end))
			lbl("Радиус (единиц, 52 ≈ 1 м)") local r = add(entry(nil, tostring(q.radius or 150), function(v) q.radius = tonumber(v) or 150 end)) r:SetNumeric(true)
		end
		lbl("Награда, $") local m = add(entry(nil, tostring(q.reward.money or 0), function(v) q.reward.money = tonumber(v) or 0 end)) m:SetNumeric(true)
		lbl("Награда предметом")
		add(select(nil, "Предмет-награда", function() return itemOptions(true) end, function() return q.reward.item or false end,
			function(v) q.reward.item = v or nil end))
		lbl("Сколько предметов") local rn = add(entry(nil, tostring(q.reward.n or 1), function(v) q.reward.n = tonumber(v) or 1 end)) rn:SetNumeric(true)
		lbl("Что NPC говорит, когда даёт задание") add(entry(nil, q.accept, function(v) q.accept = v end, true))
		lbl("Что NPC говорит, когда задание сдано") add(entry(nil, q.done, function(v) q.done = v end, true))
		local tog = add(vgui.Create("NYRP.Toggle"), UI.S(12))
		tog:SetLabel("Можно выполнять повторно")
		tog:SetChecked(q.repeatable == true)
		tog.OnChange = function(_, on) q.repeatable = on end
		add(small(nil, "Удалить задание", function() d.quests[E.quest] = nil E.quest = nil rebuild() end, UI.Col.red), UI.S(16))
	end
	local function buildList()
		list:Clear()
		local head = label(list, "ЗАДАНИЯ")
		head:Dock(TOP)
		head:DockMargin(UI.S(12), UI.S(10), 0, UI.S(6))
		local ids = table.GetKeys(d.quests)
		table.sort(ids)
		for _, id in ipairs(ids) do
			local b = vgui.Create("DButton", list)
			b:Dock(TOP)
			b:DockMargin(UI.S(6), 0, UI.S(6), UI.S(4))
			b:SetTall(UI.S(30))
			b:SetText("")
			b.Paint = function(s, w, h)
				local on = E.quest == id
				UI.RoundedRect(UI.S(6), 0, 0, w, h, on and UI.Alpha(ACCENT, 60) or Color(255, 255, 255, s:IsHovered() and 12 or 0))
				local q = d.quests[id]
				draw.SimpleText(q and q.name ~= "" and q.name or id, NYRP.Font("medium", 14), UI.S(10), h / 2, on and UI.Col.text or UI.Col.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
			b.DoClick = function() E.quest = id rebuild() end
		end
		local add = small(list, "+ задание", function()
			local i = 1
			while d.quests["q" .. i] do i = i + 1 end
			d.quests["q" .. i] = { name = "Новое задание", desc = "", type = "bring", item = "water", n = 1,
				reward = { money = 20 }, accept = "Сделаешь — заплачу.", done = "Спасибо, держи.", repeatable = false }
			E.quest = "q" .. i
			rebuild()
		end)
		add:Dock(BOTTOM)
		add:DockMargin(UI.S(8), 0, UI.S(8), UI.S(8))
	end
	rebuild = function() buildList() buildRight() end
	rebuild()
end }

-- ------------------------------------------------------------------ окно --
-- Службы и работы: какие фракции выдаёт NPC (и как получить) и какие профессии предлагает.
-- Работает, если у ответа в диалоге выбрано «Открыть меню фракций» / «Открыть меню профессий».
TABS[#TABS + 1] = { "Службы и работы", "badge", function(body)
	local d = E.data
	d.factions = d.factions or {}
	d.jobs = d.jobs or {}
	local METHODS = { { "free", "Свободно (сразу)" }, { "req", "По требованиям" }, { "whitelist", "Заявка → админ" } }
	local scroll = vgui.Create("DScrollPanel", body)
	scroll:Dock(FILL)
	local function head(text, sub)
		local h = scroll:Add("DPanel")
		h:Dock(TOP)
		h:SetTall(UI.S(48))
		h.Paint = function(_, w, hh)
			draw.SimpleText(text, NYRP.Font("bold", 17), 0, UI.S(6), UI.Col.text)
			draw.SimpleText(sub, NYRP.Font("regular", 12), 0, UI.S(28), UI.Col.dim)
		end
	end
	head("ФРАКЦИИ (госслужбы)", "Отметьте, кого принимает этот NPC. Никто не отмечен — правила берутся из файлов framework/roles.")
	for _, rid in ipairs(NYRP.Roles.Order) do
		local r = NYRP.Roles.List[rid]
		if not r.Default then
			local row = scroll:Add("DPanel")
			row:Dock(TOP)
			row:SetTall(UI.S(44))
			row:DockMargin(0, 0, UI.S(8), UI.S(6))
			row.Paint = function(_, w, h)
				local on = d.factions[rid] ~= nil
				UI.RoundedRect(UI.S(8), 0, 0, w, h, Color(255, 255, 255, on and 16 or 6))
				UI.RoundedRect(UI.S(4), UI.S(12), h / 2 - UI.S(9), UI.S(18), UI.S(18), on and r.Color or Color(255, 255, 255, 30))
				draw.SimpleText(r.Name, NYRP.Font("semibold", 15), UI.S(42), h / 2, on and color_white or UI.Col.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
			local toggle = vgui.Create("DButton", row)
			toggle:SetText("")
			toggle:SetPos(0, 0)
			toggle:SetSize(UI.S(260), UI.S(44))
			toggle.Paint = nil
			toggle.DoClick = function()
				if d.factions[rid] then d.factions[rid] = nil else d.factions[rid] = { method = "req", hours = r.MinHours or 0 } end
				UI.Sound("toggle")
			end
			local hours = vgui.Create("DNumberWang", row)
			hours:Dock(RIGHT)
			hours:SetWide(UI.S(70))
			hours:DockMargin(UI.S(6), UI.S(8), UI.S(8), UI.S(8))
			hours:SetMinMax(0, 1000)
			hours:SetValue(d.factions[rid] and d.factions[rid].hours or (r.MinHours or 0))
			hours.OnValueChanged = function(_, v) if d.factions[rid] then d.factions[rid].hours = math.floor(tonumber(v) or 0) end end
			local hl = vgui.Create("DLabel", row)
			hl:Dock(RIGHT)
			hl:SetWide(UI.S(60))
			hl:SetText("часов:")
			hl:SetFont(NYRP.Font("medium", 13))
			local m = select(row, "Как получить", function() return METHODS end,
				function() return d.factions[rid] and d.factions[rid].method or "req" end,
				function(v) d.factions[rid] = d.factions[rid] or { hours = 0 } d.factions[rid].method = v end)
			m:Dock(RIGHT)
			m:SetWide(UI.S(220))
			m:DockMargin(0, UI.S(4), 0, UI.S(4))
		end
	end
	head("ПРОФЕССИИ", "Отметьте, какие работы предлагает NPC. Никто не отмечен — все профессии.")
	for _, jid in ipairs(NYRP.Jobs.Order) do
		local j = NYRP.Jobs.List[jid]
		local b = scroll:Add("DButton")
		b:SetText("")
		b:Dock(TOP)
		b:SetTall(UI.S(38))
		b:DockMargin(0, 0, UI.S(8), UI.S(4))
		b.DoClick = function() d.jobs[jid] = (not d.jobs[jid]) or nil UI.Sound("toggle") end
		b.Paint = function(s, w, h)
			local on = d.jobs[jid]
			UI.RoundedRect(UI.S(8), 0, 0, w, h, Color(255, 255, 255, on and 16 or (s:IsHovered() and 10 or 5)))
			UI.RoundedRect(UI.S(4), UI.S(12), h / 2 - UI.S(8), UI.S(16), UI.S(16), on and j.Color or Color(255, 255, 255, 30))
			UI.DrawIcon(j.Icon, UI.S(48), h / 2, UI.S(18), j.Color)
			draw.SimpleText(j.Name .. (j.Criminal and "  (криминал)" or ""), NYRP.Font("semibold", 14), UI.S(68), h / 2, on and color_white or UI.Col.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end
end }

function N.OpenEditor(ent, data)
	if IsValid(E.frame) then E.frame:Remove() end
	E = { ent = ent, data = table.Copy(data), tab = 1 }
	local f = vgui.Create("EditablePanel")
	E.frame = f
	f:SetSize(math.min(UI.S(1100), ScrW() - UI.S(40)), math.min(UI.S(720), ScrH() - UI.S(40)))
	f:Center()
	f:MakePopup()
	f.Born = RealTime()
	f.Paint = function(s, w, h)
		s:SetAlpha(255 * UI.Ease((RealTime() - s.Born) / 0.25))
		UI.RoundedBlurPanel(s, UI.S(16), 4)
		UI.RoundedRect(UI.S(16), 0, 0, w, h, Color(14, 16, 26, 245))
		UI.Outline(UI.S(16), 0, 0, w, h, UI.Col.stroke, 1)
		UI.Masked(UI.S(16), 0, 0, w, h, function()
			surface.SetDrawColor(244, 245, 248)
			surface.DrawRect(0, 0, w, UI.S(60))
		end)
		draw.SimpleText("НАСТРОЙКА NPC", NYRP.Font("title", 22), UI.S(24), UI.S(30), Color(20, 22, 30), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText(E.data.name .. " · " .. (N.Kinds[E.data.kind] or ""), NYRP.Font("tag", 17), UI.S(220), UI.S(30), Color(80, 84, 96), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	local close = vgui.Create("NYRP.IconButton", f)
	close:SetSize(UI.S(32), UI.S(32))
	close:SetPos(f:GetWide() - UI.S(48), UI.S(14))
	close.DoClick = function() f:Remove() end

	-- вкладки слева
	local side = vgui.Create("DPanel", f)
	side:SetPos(UI.S(16), UI.S(76))
	side:SetSize(UI.S(190), f:GetTall() - UI.S(150))
	side.Paint = function() end
	local body = vgui.Create("DPanel", f)
	body:SetPos(UI.S(222), UI.S(76))
	body:SetSize(f:GetWide() - UI.S(238), f:GetTall() - UI.S(150))
	body.Paint = function() end
	local function show(i)
		E.tab = i
		body:Clear()
		TABS[i][3](body)
	end
	for i, t in ipairs(TABS) do
		local b = vgui.Create("DButton", side)
		b:Dock(TOP)
		b:DockMargin(0, 0, 0, UI.S(6))
		b:SetTall(UI.S(44))
		b:SetText("")
		b.Paint = function(s, w, h)
			local on = E.tab == i
			UI.RoundedRect(UI.S(10), 0, 0, w, h, on and UI.Alpha(ACCENT, 50) or Color(255, 255, 255, s:IsHovered() and 10 or 4))
			if on then UI.RoundedRect(UI.S(2), 0, UI.S(10), UI.S(3), h - UI.S(20), ACCENT) end
			UI.DrawIcon(t[2], UI.S(24), h / 2, UI.S(18), on and ACCENT or UI.Col.dim)
			draw.SimpleText(t[1], NYRP.Font("semibold", 16), UI.S(44), h / 2, on and UI.Col.text or UI.Col.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		b.DoClick = function() UI.Sound("swipe") show(i) end
	end

	-- низ: действия
	local foot = vgui.Create("DPanel", f)
	foot:SetPos(UI.S(16), f:GetTall() - UI.S(62))
	foot:SetSize(f:GetWide() - UI.S(32), UI.S(46))
	foot.Paint = function() end
	local function send(moveHere)
		E.data.moveHere = moveHere or nil
		net.Start("nyrp.npc.save")
		net.WriteEntity(E.ent)
		net.WriteTable(E.data)
		net.SendToServer()
		E.data.moveHere = nil
		UI.Sound("success")
	end
	local save = vgui.Create("NYRP.Button", foot)
	save:Dock(RIGHT)
	save:SetWide(UI.S(200))
	save:SetLabel("СОХРАНИТЬ")
	save:SetStyle("solid")
	save:SetAccent(ACCENT)
	save:SetAlign(TEXT_ALIGN_CENTER)
	save:SetFontStyle("title", 18)
	save.DoClick = function() send(false) end
	local move = vgui.Create("NYRP.Button", foot)
	move:Dock(RIGHT)
	move:DockMargin(0, 0, UI.S(10), 0)
	move:SetWide(UI.S(260))
	move:SetLabel("Сохранить и поставить ко мне")
	move:SetIcon("move")
	move.DoClick = function() send(true) end
	local del = vgui.Create("NYRP.Button", foot)
	del:Dock(LEFT)
	del:SetWide(UI.S(180))
	del:SetLabel("Удалить NPC")
	del:SetIcon("trash")
	del:SetAccent(UI.Col.red)
	del.DoClick = function()
		net.Start("nyrp.npc.remove") net.WriteEntity(E.ent) net.SendToServer()
		f:Remove()
	end
	show(1)
end

net.Receive("nyrp.npc.edit", function()
	local ent, data = net.ReadEntity(), net.ReadTable()
	N.OpenEditor(ent, data)
end)
