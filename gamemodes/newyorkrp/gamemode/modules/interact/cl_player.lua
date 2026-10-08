--[[
	Круговое меню взаимодействия с игроком: E по человеку — вокруг его груди «в мире»
	раскрываются кнопки (меню следует за ним): Познакомиться, Передать деньги, Показать удостоверение.
	Выбор — движением мыши, подтверждение — E.
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
		-- «$» всегда справа от введённой суммы
		local tw = UI.TextSize(s:GetText(), NYRP.Font("bold", 22))
		if s:GetText() == "" then
			draw.SimpleText(s:HasFocus() and "" or "Сумма", NYRP.Font("medium", 18), UI.S(14), h / 2, UI.Col.faint, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		else
			draw.SimpleText("$", NYRP.Font("bold", 22), UI.S(14) + tw + UI.S(6), h / 2, UI.Col.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		s:DrawTextEntryText(UI.Col.text, UI.Col.accent, UI.Col.text)
	end
	entry:SetTextInset(UI.S(14), 0)
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

-- Само круговое меню — в мире, выбор движением мыши (modules/interact/cl_worldradial.lua).
function I.OpenPlayerMenu(target)
	NYRP.WorldRadial.Open({
		anchor = function() return IsValid(target) and I.Anchor(target) end,
		valid = function()
			return IsValid(target) and target:Alive() and target:GetPos():Distance(LocalPlayer():GetPos()) <= 170
		end,
		options = ACTIONS,
		onSelect = function(act)
			if act.id == "money" then I.OpenMoneyDialog(target) else send(act.id, target) end
		end,
	})
end
