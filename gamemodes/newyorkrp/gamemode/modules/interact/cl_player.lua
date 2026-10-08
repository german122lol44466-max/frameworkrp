--[[
	Круговое меню взаимодействия с игроком: E по человеку — вокруг его груди «в мире»
	раскрываются кнопки (меню следует за ним): Познакомиться, Передать деньги, Показать удостоверение.
]]

local UI = NYRP.UI
local I = NYRP.Interact

local ACTIONS = {
	{ id = "introduce", name = "Познакомиться", icon = "user_plus" },
	{ id = "money", name = "Передать деньги", icon = "g_give" },
	{ id = "showid", name = "Показать удостоверение", icon = "id" },
}

local function send(act, target)
	net.Start("nyrp.player.act")
	net.WriteString(act)
	net.WriteEntity(target)
	net.SendToServer()
end

-- Окно суммы для передачи денег.
function I.OpenMoneyDialog(target)
	if IsValid(I.MoneyDlg) then I.MoneyDlg:Remove() end
	local f = vgui.Create("EditablePanel")
	I.MoneyDlg = f
	f:SetSize(UI.S(380), UI.S(250))
	f:Center()
	f:MakePopup()
	f.Born = RealTime()
	f.Paint = function(s, w, h)
		local t = UI.Ease((RealTime() - s.Born) / 0.25)
		s:SetAlpha(255 * t)
		UI.RoundedBlurPanel(s, UI.S(16), 4)
		UI.RoundedRect(UI.S(16), 0, 0, w, h, Color(12, 14, 22, 240))
		UI.Outline(UI.S(16), 0, 0, w, h, UI.Col.stroke, 1)
		UI.DrawIcon("g_give", UI.S(30), UI.S(32), UI.S(22), UI.Col.accent)
		draw.SimpleText("ПЕРЕДАТЬ ДЕНЬГИ", NYRP.Font("title", 22), UI.S(52), UI.S(32), UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		local who = IsValid(target) and ((NYRP.Recog and NYRP.Recog.Knows(target)) and NYRP.CharName(target) or "Неизвестный") or "—"
		draw.SimpleText("Кому: " .. who, NYRP.Font("medium", 14), UI.S(22), UI.S(64), UI.Col.dim)
		draw.SimpleText("У вас: " .. NYRP.Money.Format(NYRP.Money.Get(LocalPlayer())), NYRP.Font("semibold", 14), w - UI.S(22), UI.S(64), UI.Col.accent, TEXT_ALIGN_RIGHT)
		if not IsValid(target) or target:GetPos():Distance(LocalPlayer():GetPos()) > 170 then s:Remove() end
	end
	local entry = vgui.Create("DTextEntry", f)
	entry:SetPos(UI.S(22), UI.S(96))
	entry:SetSize(f:GetWide() - UI.S(44), UI.S(46))
	entry:SetNumeric(true)
	entry:SetFont(NYRP.Font("bold", 22))
	entry:SetPlaceholderText("Сумма")
	entry.Paint = function(s, w, h)
		UI.RoundedRect(UI.S(10), 0, 0, w, h, Color(0, 0, 0, 110))
		UI.Outline(UI.S(10), 0, 0, w, h, s:HasFocus() and UI.Alpha(UI.Col.accent, 160) or UI.Col.stroke, 1)
		draw.SimpleText("$", NYRP.Font("bold", 22), UI.S(14), h / 2, UI.Col.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		if s:GetText() == "" and not s:HasFocus() then
			draw.SimpleText("Сумма", NYRP.Font("medium", 18), UI.S(34), h / 2, UI.Col.faint, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		s:DrawTextEntryText(UI.Col.text, UI.Col.accent, UI.Col.text)
	end
	entry:SetTextInset(UI.S(34), 0)
	entry:RequestFocus()
	-- быстрые суммы
	local quick = { 10, 50, 100, 500 }
	local qw = (f:GetWide() - UI.S(44) - UI.S(8) * (#quick - 1)) / #quick
	for i, v in ipairs(quick) do
		local b = vgui.Create("DButton", f)
		b:SetText("")
		b:SetPos(UI.S(22) + (i - 1) * (qw + UI.S(8)), UI.S(152))
		b:SetSize(qw, UI.S(30))
		b.Paint = function(s, w, h)
			UI.RoundedRect(UI.S(8), 0, 0, w, h, s:IsHovered() and Color(255, 255, 255, 18) or Color(255, 255, 255, 7))
			draw.SimpleText("$" .. v, NYRP.Font("semibold", 14), w / 2, h / 2, UI.Col.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		b.DoClick = function() entry:SetText(tostring(v)) UI.Sound("click") end
	end
	local ok = vgui.Create("NYRP.Button", f)
	ok:SetPos(UI.S(22), UI.S(196))
	ok:SetSize(f:GetWide() - UI.S(44), UI.S(40))
	ok:SetLabel("ПЕРЕДАТЬ")
	ok:SetStyle("solid")
	ok:SetAlign(TEXT_ALIGN_CENTER)
	local function submit()
		local n = math.floor(tonumber(entry:GetText()) or 0)
		if n <= 0 then UI.Sound("error") return end
		net.Start("nyrp.money.give")
		net.WriteEntity(target)
		net.WriteUInt(n, 32)
		net.SendToServer()
		f:Remove()
	end
	ok.DoClick = submit
	entry.OnEnter = submit
	f.OnKeyCodePressed = function(s, key) if key == KEY_ESCAPE then s:Remove() end end
end

-- Само круговое меню.
function I.OpenPlayerMenu(target)
	if IsValid(I.PlayerMenu) then I.PlayerMenu:Close() return end
	local pnl = vgui.Create("EditablePanel")
	I.PlayerMenu = pnl
	pnl:SetSize(ScrW(), ScrH())
	pnl:MakePopup()
	pnl:SetKeyboardInputEnabled(false)
	pnl.Born = RealTime()
	pnl.Hover = {}
	UI.Sound("open")
	local R = UI.S(120)

	function pnl:Close()
		if self.Closing then return end
		self.Closing = RealTime()
		self:SetMouseInputEnabled(false)
		timer.Simple(0.18, function() if IsValid(self) then self:Remove() end end)
	end

	local function center()
		if not IsValid(target) then return end
		local sc = I.Anchor(target):ToScreen()
		return sc.x, sc.y, sc.visible
	end
	local function buttonPos(i, t)
		local cx, cy = center()
		if not cx then return end
		local a = math.rad(-90 + (i - 1) * 360 / #ACTIONS)
		local r = R * (0.4 + 0.6 * t)
		return cx + math.cos(a) * r, cy + math.sin(a) * r
	end

	pnl.Think = function(s)
		if s.Closing then return end
		if not IsValid(target) or not target:Alive() or target:GetPos():Distance(LocalPlayer():GetPos()) > 170 or not LocalPlayer():Alive() then
			s:Close()
		end
		if input.IsKeyDown(KEY_ESCAPE) then s:Close() end
	end
	local function hovered(s)
		local t = UI.Ease((RealTime() - s.Born) / 0.25)
		local mx, my = gui.MousePos()
		for i in ipairs(ACTIONS) do
			local x, y = buttonPos(i, t)
			if x and (mx - x) ^ 2 + (my - y) ^ 2 <= UI.S(42) ^ 2 then return i end
		end
	end
	pnl.OnMousePressed = function(s, code)
		if code ~= MOUSE_LEFT then s:Close() return end
		local i = hovered(s)
		if not i then s:Close() return end
		local act = ACTIONS[i]
		UI.Sound("click")
		s:Close()
		if act.id == "money" then I.OpenMoneyDialog(target) else send(act.id, target) end
	end
	pnl.Paint = function(s, w, h)
		local t = UI.Ease((RealTime() - s.Born) / 0.25)
		if s.Closing then t = t * (1 - UI.Ease((RealTime() - s.Closing) / 0.18)) end
		local cx, cy = center()
		if not cx then return end
		surface.SetAlphaMultiplier(t)
		UI.Glow(cx, cy, R * 3.2, R * 3.2, Color(0, 0, 0, 170))
		-- центр: «E» и имя
		UI.Circle(cx, cy, UI.S(26), Color(255, 255, 255, 245))
		draw.SimpleText("E", NYRP.Font("bold", 22), cx, cy, Color(12, 14, 20), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		local hi = not s.Closing and hovered(s)
		for i, act in ipairs(ACTIONS) do
			s.Hover[i] = UI.Approach(s.Hover[i] or 0, hi == i and 1 or 0, 16)
			local hv = s.Hover[i]
			local x, y = buttonPos(i, t)
			-- линия от центра к кнопке
			surface.SetDrawColor(255, 255, 255, 30 + 60 * hv)
			surface.DrawLine(cx, cy, x, y)
			local r = UI.S(34) + hv * UI.S(5)
			UI.Circle(x, y + UI.S(2), r + UI.S(3), Color(0, 0, 0, 90))
			UI.Circle(x, y, r, UI.LerpColor(hv, Color(14, 16, 24, 235), Color(247, 198, 0, 255)))
			UI.Ring(x, y, r, Color(255, 255, 255, 30 + 60 * (1 - hv)))
			UI.DrawIcon(act.icon, x, y, UI.S(26), UI.LerpColor(hv, Color(236, 237, 242), Color(14, 14, 18)))
			local font = NYRP.Font("semibold", 15)
			draw.SimpleText(act.name, font, x + 1, y + r + UI.S(14) + 2, Color(0, 0, 0, 170), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			draw.SimpleText(act.name, font, x, y + r + UI.S(14), UI.LerpColor(hv, Color(225, 227, 233), UI.Col.accent), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		surface.SetAlphaMultiplier(1)
	end
end
