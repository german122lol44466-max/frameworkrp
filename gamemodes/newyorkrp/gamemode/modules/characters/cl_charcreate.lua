--[[
	Меню создания персонажа: размытый фон, превью модели (с выбранной сумкой), форма справа.
]]

local UI = NYRP.UI
local Chars = NYRP.Chars
local C = NYRP.Config

local function V(t) return Vector(t[1], t[2], t[3]) end

local function section(parent, title)
	local l = vgui.Create("DPanel", parent)
	l:Dock(TOP)
	l:SetTall(UI.S(34))
	l:DockMargin(0, UI.S(14), 0, UI.S(4))
	l.Paint = function(_, w, h)
		draw.SimpleText(string.upper(title), NYRP.Font("title", 16), 0, h / 2, UI.Col.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		local tw = UI.TextSize(string.upper(title), NYRP.Font("title", 16))
		surface.SetDrawColor(255, 255, 255, 14)
		surface.DrawRect(tw + UI.S(12), h / 2, w - tw - UI.S(12), 1)
	end
	return l
end

function Chars.OpenCreate(spot)
	local d = { name = "", description = "", gender = "male", modelIndex = 1, height = 178, bag = "waistbag", skills = {} }
	for _, s in ipairs(C.Skills) do d.skills[s.id] = 0 end
	local function model() return C.Models[d.gender][d.modelIndex] end
	local function pointsLeft()
		local n = C.SkillPoints
		for _, v in pairs(d.skills) do n = n - v end
		return n
	end

	UI.Fade(0.35, 0.15, 0.5, function()
		if IsValid(Chars.SelectPanel) then Chars.SelectPanel:SetVisible(false) end
		Chars.SetState("create")
		local pts = NYRP.ClientPoints.create or {}
		if #pts > 0 then
			Chars.FlyPath(pts, 1.6)
		elseif spot then
			local fwd = spot.ang:Forward()
			Chars.MoveCamera({ pos = { (spot.pos + fwd * 110 + Vector(0, 0, 62)):Unpack() },
				ang = { ((spot.pos + Vector(0, 0, 50)) - (spot.pos + fwd * 110 + Vector(0, 0, 62))):Angle():Unpack() } }, 1.4)
		end
	end)

	timer.Simple(0.5, function()
		local pnl = vgui.Create("EditablePanel")
		Chars.CreatePanel = pnl
		pnl:SetSize(ScrW(), ScrH())
		pnl:MakePopup()
		pnl.Born = RealTime()
		pnl.Paint = function(s, w, h)
			local t = UI.Ease((RealTime() - s.Born) / 0.6)
			UI.BlurPanel(s, 7 * t)
			surface.SetDrawColor(6, 8, 14, 150 * t)
			surface.DrawRect(0, 0, w, h)
			UI.Vignette(-UI.S(20), -UI.S(20), w + UI.S(40), h + UI.S(40), 210 * t)
			-- подиум под превью
			local cx = w * 0.3
			UI.Glow(cx, h * 0.86, UI.S(560), UI.S(120), Color(247, 198, 0, 30 * t))
			UI.Glow(cx, h * 0.86, UI.S(300), UI.S(50), Color(255, 255, 255, 30 * t))
			draw.SimpleText("Зажмите ЛКМ и тяните, чтобы повернуть", NYRP.Font("regular", 14), cx, h - UI.S(40), Color(255, 255, 255, 60 * t), TEXT_ALIGN_CENTER)
		end

		-- превью
		local prev = vgui.Create("DModelPanel", pnl)
		prev:SetSize(ScrW() * 0.36, ScrH() * 0.86)
		prev:SetPos(ScrW() * 0.3 - prev:GetWide() / 2, ScrH() * 0.06)
		prev:SetFOV(32)
		prev:SetModel(model())
		prev.Yaw = 20
		prev.UpdateModel = function(s)
			s:SetModel(model())
			local ent = s:GetEntity()
			if not IsValid(ent) then return end
			ent:SetModelScale(Chars.HeightScale(d.height), 0)
			local seq = ent:LookupSequence("idle_all_01")
			if seq and seq >= 0 then ent:ResetSequence(seq) end
		end
		prev:UpdateModel()
		prev.LayoutEntity = function(s, ent)
			if s.Dragging then
				local mx = gui.MouseX()
				s.Yaw = s.Yaw + (mx - (s.LastX or mx)) * 0.5
				s.LastX = mx
			end
			ent:SetAngles(Angle(0, s.Yaw, 0))
			s:RunAnimation()
			s:SetCamPos(Vector(150, 0, 48))
			s:SetLookAt(Vector(0, 0, 38 * Chars.HeightScale(d.height)))
		end
		prev.OnMousePressed = function(s, code) if code == MOUSE_LEFT then s.Dragging = true s.LastX = gui.MouseX() s:MouseCapture(true) end end
		prev.OnMouseReleased = function(s) s.Dragging = false s:MouseCapture(false) end

		-- форма
		local form = vgui.Create("DPanel", pnl)
		local fw = UI.S(560)
		form:SetSize(fw, ScrH() - UI.S(80))
		form:SetPos(ScrW() - fw - UI.S(60), UI.S(40))
		form.Born = RealTime()
		form.Paint = function(s, w, h)
			local t = UI.Ease((RealTime() - s.Born) / 0.5)
			s:SetAlpha(255 * t)
			UI.RoundedRect(UI.S(16), 0, 0, w, h, Color(10, 12, 20, 225))
			UI.Outline(UI.S(16), 0, 0, w, h, Color(255, 255, 255, 16), 1)
			draw.SimpleText("НОВЫЙ ЖИТЕЛЬ", NYRP.Font("title", 34), UI.S(32), UI.S(28), UI.Col.text)
			draw.SimpleText("Нью-Йорк ждёт. Расскажите, кто вы.", NYRP.Font("regular", 16), UI.S(32), UI.S(74), UI.Col.dim)
		end
		local body = vgui.Create("NYRP.Scroll", form)
		body:SetPos(UI.S(32), UI.S(104))
		body:SetSize(fw - UI.S(56), form:GetTall() - UI.S(104) - UI.S(96))

		section(body, "Личность")
		local name = vgui.Create("NYRP.TextEntry", body)
		name:Dock(TOP)
		name:DockMargin(0, 0, UI.S(10), UI.S(8))
		name:SetPlaceholderText("Имя и фамилия (например: Тони Морелли)")
		name.OnChange = function(s) d.name = s:GetValue() end
		local desc = vgui.Create("NYRP.TextEntry", body)
		desc:Dock(TOP)
		desc:DockMargin(0, 0, UI.S(10), 0)
		desc:SetMultiline(true)
		desc:SetTall(UI.S(96))
		desc:SetPlaceholderText("Внешность, характер, манеры — что увидят другие")
		desc.OnChange = function(s) d.description = s:GetValue() end

		section(body, "Пол и внешность")
		local gRow = vgui.Create("DPanel", body)
		gRow:Dock(TOP)
		gRow:SetTall(UI.S(46))
		gRow:DockMargin(0, 0, UI.S(10), UI.S(8))
		gRow.Paint = function() end
		local gBtns = {}
		local function refreshGender()
			for g, b in pairs(gBtns) do b:SetStyle(d.gender == g and "solid" or "ghost") end
		end
		for i, g in ipairs({ { "male", "Мужчина" }, { "female", "Женщина" } }) do
			local b = vgui.Create("NYRP.Button", gRow)
			b:SetLabel(g[2])
			b:SetIcon("user")
			b:SetAlign(TEXT_ALIGN_CENTER)
			b:Dock(LEFT)
			b:SetWide((fw - UI.S(76)) / 2)
			b:DockMargin(0, 0, i == 1 and UI.S(10) or 0, 0)
			b.DoClick = function()
				d.gender = g[1]
				d.modelIndex = 1
				refreshGender()
				prev:UpdateModel()
			end
			gBtns[g[1]] = b
		end
		refreshGender()

		local mRow = vgui.Create("DPanel", body)
		mRow:Dock(TOP)
		mRow:SetTall(UI.S(46))
		mRow:DockMargin(0, 0, UI.S(10), 0)
		mRow.Paint = function(_, w, h)
			UI.RoundedRect(UI.S(8), 0, 0, w, h, Color(255, 255, 255, 8))
			draw.SimpleText("Внешность " .. d.modelIndex .. " из " .. #C.Models[d.gender], NYRP.Font("semibold", 17), w / 2, h / 2, UI.Col.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		for _, dir in ipairs({ { "chevron_left", LEFT, -1 }, { "chevron_right", RIGHT, 1 } }) do
			local b = vgui.Create("NYRP.IconButton", mRow)
			b:SetIcon(dir[1])
			b:Dock(dir[2])
			b:SetWide(UI.S(46))
			b.DoClick = function()
				local n = #C.Models[d.gender]
				d.modelIndex = (d.modelIndex - 1 + dir[3]) % n + 1
				prev:UpdateModel()
			end
		end

		local hs = vgui.Create("NYRP.Slider", body)
		hs:Dock(TOP)
		hs:DockMargin(0, UI.S(10), UI.S(10), 0)
		hs:SetLabel("Рост")
		hs:SetMinMax(C.HeightMin, C.HeightMax)
		hs:SetDecimals(0)
		hs:SetSuffix(" см")
		hs:SetValue(d.height, true)
		hs.OnValueChanged = function(_, v) d.height = v prev:UpdateModel() end

		section(body, "Что носите с собой")
		local bRow = vgui.Create("DPanel", body)
		bRow:Dock(TOP)
		bRow:SetTall(UI.S(96))
		bRow:DockMargin(0, 0, UI.S(10), 0)
		bRow.Paint = function() end
		for i, id in ipairs({ "waistbag", "backpack" }) do
			local cfg = C.Bags[id]
			local card = vgui.Create("DButton", bRow)
			card:SetText("")
			card:Dock(LEFT)
			card:SetWide((fw - UI.S(76)) / 2)
			card:DockMargin(0, 0, i == 1 and UI.S(10) or 0, 0)
			card.Hover = 0
			card.OnCursorEntered = function() UI.Sound("hover") end
			card.DoClick = function() UI.Sound("click") d.bag = id end
			card.Paint = function(s, w, h)
				local sel = d.bag == id
				s.Hover = UI.Approach(s.Hover, (s:IsHovered() or sel) and 1 or 0, 12)
				UI.RoundedRect(UI.S(10), 0, 0, w, h, Color(255, 255, 255, 8 + s.Hover * 8))
				UI.Outline(UI.S(10), 0, 0, w, h, sel and UI.Col.accent or Color(255, 255, 255, 16), sel and 2 or 1)
				UI.Circle(UI.S(44), h / 2, UI.S(26), sel and UI.Alpha(UI.Col.accent, 40) or Color(255, 255, 255, 10))
				UI.DrawIcon(cfg.icon, UI.S(44), h / 2, UI.S(28), sel and UI.Col.accent or UI.Col.dim)
				draw.SimpleText(cfg.name, NYRP.Font("semibold", 18), UI.S(82), h / 2 - UI.S(2), UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
				draw.SimpleText(cfg.cols * cfg.rows .. " ячеек", NYRP.Font("regular", 15), UI.S(82), h / 2 + UI.S(2), UI.Col.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
				return true
			end
		end

		section(body, "Навыки")
		local pts = vgui.Create("DPanel", body)
		pts:Dock(TOP)
		pts:SetTall(UI.S(26))
		pts.Paint = function(_, w, h)
			local left = pointsLeft()
			draw.SimpleText("Свободных очков: " .. left, NYRP.Font("semibold", 16), 0, h / 2, left > 0 and UI.Col.accent or UI.Col.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		for _, sk in ipairs(C.Skills) do
			local row = vgui.Create("DPanel", body)
			row:Dock(TOP)
			row:SetTall(UI.S(58))
			row:DockMargin(0, UI.S(6), UI.S(10), 0)
			row.Paint = function(_, w, h)
				UI.RoundedRect(UI.S(10), 0, 0, w, h, Color(255, 255, 255, 7))
				UI.DrawIcon(sk.icon, UI.S(28), h / 2, UI.S(22), UI.Col.dim)
				draw.SimpleText(sk.name, NYRP.Font("semibold", 17), UI.S(54), h / 2 - UI.S(1), UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
				draw.SimpleText(sk.desc, NYRP.Font("regular", 14), UI.S(54), h / 2 + UI.S(1), UI.Col.faint, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
				local v = d.skills[sk.id]
				local bx = w - UI.S(52) - UI.S(5 * 14)
				for i = 1, C.SkillMax do
					UI.RoundedRect(UI.S(2), bx + (i - 1) * UI.S(13), h / 2 - UI.S(4), UI.S(10), UI.S(8), i <= v and UI.Col.accent or Color(255, 255, 255, 20))
				end
			end
			local plus = vgui.Create("NYRP.IconButton", row)
			plus:SetIcon("plus")
			plus:SetSize(UI.S(34), UI.S(34))
			plus:SetPos(fw - UI.S(76) - UI.S(44), UI.S(12))
			plus.DoClick = function()
				if pointsLeft() > 0 and d.skills[sk.id] < C.SkillMax then d.skills[sk.id] = d.skills[sk.id] + 1 end
			end
			local minus = vgui.Create("NYRP.IconButton", row)
			minus:SetIcon("minus")
			minus:SetSize(UI.S(34), UI.S(34))
			minus:SetPos(fw - UI.S(76) - UI.S(44) - UI.S(5 * 14) - UI.S(46), UI.S(12))
			minus.DoClick = function()
				if d.skills[sk.id] > 0 then d.skills[sk.id] = d.skills[sk.id] - 1 end
			end
		end

		local create = vgui.Create("NYRP.Button", form)
		create:SetSize(UI.S(300), UI.S(54))
		create:SetPos(UI.S(32), form:GetTall() - UI.S(78))
		create:SetLabel("СОЗДАТЬ")
		create:SetIcon("user_plus")
		create:SetStyle("solid")
		create:SetAlign(TEXT_ALIGN_CENTER)
		create:SetFontStyle("title", 22)
		create.DoClick = function()
			if pnl.Busy then return end
			local send = { name = d.name, description = d.description, gender = d.gender, model = model(), height = d.height, skills = d.skills, bag = d.bag }
			local ok, err = Chars.Validate(send)
			if not ok then NYRP.Notify(err, "error") return end
			pnl.Busy = true
			UI.Sound("start")
			UI.Fade(0.7, 0, 0.01, function()
				Chars.HoldBlack = true
				timer.Create("nyrp.holdblack", 8, 1, function() Chars.HoldBlack = false end)
				net.Start("nyrp.char.create")
				net.WriteTable(send)
				net.SendToServer()
			end)
		end
		local back = vgui.Create("NYRP.Button", form)
		back:SetSize(UI.S(180), UI.S(54))
		back:SetPos(fw - UI.S(32) - UI.S(180), form:GetTall() - UI.S(78))
		back:SetLabel("НАЗАД")
		back:SetStyle("ghost")
		back:SetAlign(TEXT_ALIGN_CENTER)
		back:SetFontStyle("title", 20)
		back.DoClick = function()
			UI.Fade(0.35, 0.15, 0.5, function()
				pnl:Remove()
				Chars.SetState("select")
				if NYRP.ClientPoints.chars then Chars.SetCamera(NYRP.ClientPoints.chars) end
				if IsValid(Chars.SelectPanel) then Chars.SelectPanel:SetVisible(true) end
			end)
		end
	end)
end
