--[[
	Меню паузы (ESC) в стиле NYRP: продолжить, персонажи, настройки, бинды,
	стандартное меню игры, отключиться.
	ESC сначала закрывает открытое окно (чат, инвентарь, удостоверение...), потом открывает меню.
]]

local UI = NYRP.UI
local P = {}
NYRP.Pause = P

local function closeTopWindow()
	if IsValid(UI.ActiveMenu) then UI.ActiveMenu:Remove() return true end
	if P.Binding then P.Binding = nil return true end
	if NYRP.Chat and NYRP.Chat.IsOpen and NYRP.Chat.IsOpen() then NYRP.Chat.Close() return true end
	if IsValid(NYRP.PassportPanel) then NYRP.PassportPanel:Remove() return true end
	if NYRP.Inventory and NYRP.Inventory.IsOpen and NYRP.Inventory.IsOpen() then NYRP.Inventory.Close() return true end
	if IsValid(NYRP.Camera.Menu) then NYRP.Camera.Menu:Remove() return true end
	if NYRP.Editor and NYRP.Chars.EditorActive then NYRP.Editor.Close() return true end
	return false
end

hook.Add("OnPauseMenuShow", "nyrp.pause", function()
	if P.AllowGameUI then
		P.AllowGameUI = nil
		return
	end
	if closeTopWindow() then return false end
	if NYRP.State ~= "playing" then return false end
	if IsValid(P.Panel) then P.Close() else P.Open() end
	return false
end)

function P.Close()
	if IsValid(P.Panel) then
		P.Panel.Closing = RealTime()
		UI.Sound("close")
	end
end

-- ---------------------------------------------------------------- бинды --
-- press — по нажатию; release — по отпусканию (для удерживаемых меню); always — даже при открытом окне
local binds = {
	{ cvar = "nyrp_bind_inventory", name = "Инвентарь", desc = "Открыть/закрыть сумку (у админов Q — меню спавна)", always = true,
		press = function() if NYRP.Inventory.Toggle then NYRP.Inventory.Toggle() end end },
	{ cvar = "nyrp_bind_gestures", name = "Меню жестов", desc = "Круговое меню анимаций (удерживайте и отпустите на нужной)",
		press = function() if NYRP.Gestures then NYRP.Gestures.OpenRadial() end end,
		release = function() if NYRP.Gestures then NYRP.Gestures.ReleaseRadial() end end, keepCursor = true },
	{ cvar = "nyrp_bind_thirdperson", name = "Третье лицо", desc = "Включить/выключить (с затемнением)",
		press = function() NYRP.Camera.ToggleThirdPerson() end },
	{ cvar = "nyrp_bind_tpmenu", name = "Меню третьего лица", desc = "Дистанция, смещение, плавность",
		press = function() NYRP.Camera.OpenMenu() end },
}

local function buildBinds(parent)
	for _, b in ipairs(binds) do
		local row = vgui.Create("DPanel", parent)
		row:Dock(TOP)
		row:SetTall(UI.S(64))
		row:DockMargin(0, 0, 0, UI.S(8))
		row.Paint = function(_, w, h)
			UI.RoundedRect(UI.S(10), 0, 0, w, h, Color(255, 255, 255, 7))
			draw.SimpleText(b.name, NYRP.Font("semibold", 18), UI.S(18), h / 2 - UI.S(1), UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
			draw.SimpleText(b.desc, NYRP.Font("regular", 14), UI.S(18), h / 2 + UI.S(1), UI.Col.faint, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
		end
		local key = vgui.Create("DButton", row)
		key:SetText("")
		key:Dock(RIGHT)
		key:DockMargin(0, UI.S(12), UI.S(12), UI.S(12))
		key:SetWide(UI.S(170))
		key.Hover = 0
		key.Paint = function(s, w, h)
			local waiting = P.Binding == b.cvar
			s.Hover = UI.Approach(s.Hover, (s:IsHovered() or waiting) and 1 or 0, 14)
			UI.RoundedRect(UI.S(8), 0, 0, w, h, waiting and UI.Alpha(UI.Col.accent, 40) or Color(0, 0, 0, 90))
			UI.Outline(UI.S(8), 0, 0, w, h, waiting and UI.Col.accent or Color(255, 255, 255, 20 + s.Hover * 40), 1)
			local code = GetConVar(b.cvar):GetInt()
			local label = waiting and "Нажмите клавишу..." or (code > 0 and string.upper(input.GetKeyName(code) or "?") or "Не назначено")
			draw.SimpleText(label, NYRP.Font(waiting and "medium" or "bold", 15), w / 2, h / 2, waiting and UI.Col.accent or UI.Col.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			return true
		end
		key.DoClick = function(s)
			UI.Sound("click")
			P.Binding = b.cvar
			s:RequestFocus()
		end
		key.OnKeyCodePressed = function(s, code)
			if P.Binding ~= b.cvar then return end
			if code == KEY_ESCAPE then P.Binding = nil return end
			if code == KEY_BACKSPACE then code = 0 end
			RunConsoleCommand(b.cvar, tostring(code))
			P.Binding = nil
			UI.Sound("success")
		end
	end
	local hint = vgui.Create("DPanel", parent)
	hint:Dock(TOP)
	hint:SetTall(UI.S(40))
	hint.Paint = function(_, w, h)
		draw.SimpleText("Backspace — снять клавишу, Esc — отмена", NYRP.Font("regular", 14), 0, h / 2, UI.Col.faint, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
end

-- Клавиши срабатывают, когда нет открытых окон и не печатаем.
local down = {}
hook.Add("Think", "nyrp.binds", function()
	if NYRP.State ~= "playing" or gui.IsGameUIVisible() or vgui.GetKeyboardFocus() then return end
	local cursor = vgui.CursorVisible()
	for _, b in ipairs(binds) do
		local code = GetConVar(b.cvar):GetInt()
		if code > 0 then
			local isDown = input.IsKeyDown(code)
			if isDown and not down[b.cvar] and (not cursor or b.always) then
				down[b.cvar] = true
				b.press()
			elseif not isDown and down[b.cvar] then
				down[b.cvar] = nil
				if b.release then b.release() end
			end
		end
	end
end)

-- ---------------------------------------------------------------- меню --
function P.Open()
	local pnl = vgui.Create("EditablePanel")
	P.Panel = pnl
	pnl:SetSize(ScrW(), ScrH())
	pnl:MakePopup()
	pnl.Born = RealTime()
	pnl.Think = function(s)
		if s.Closing and RealTime() - s.Closing > 0.25 then s:Remove() end
	end
	pnl.Paint = function(s, w, h)
		local t = UI.Ease((RealTime() - s.Born) / 0.3)
		if s.Closing then t = t * (1 - UI.Ease((RealTime() - s.Closing) / 0.25)) end
		s:SetAlpha(255 * t)
		UI.BlurPanel(s, 6)
		surface.SetDrawColor(4, 5, 10, 175)
		surface.DrawRect(0, 0, w, h)
		surface.SetMaterial(UI.Mat("vgui/gradient-l"))
		surface.SetDrawColor(4, 5, 10, 220)
		surface.DrawTexturedRect(0, 0, w * 0.4, h)
		UI.Vignette(-UI.S(30), -UI.S(30), w + UI.S(60), h + UI.S(60), 200)
		surface.SetMaterial(UI.Mat("nyrp/logo.png"))
		surface.SetDrawColor(255, 255, 255)
		surface.DrawTexturedRect(UI.S(70), UI.S(70), UI.S(110), UI.S(110))
		draw.SimpleText("NEW-YORK", NYRP.Font("title", 44), UI.S(200), UI.S(86), UI.Col.text)
		draw.SimpleText("ROLEPLAY  ·  ПАУЗА", NYRP.Font("bold", 15), UI.S(203), UI.S(142), UI.Col.accent)
		draw.SimpleText(LocalPlayer():Nick() .. "  —  " .. NYRP.CharName(LocalPlayer()), NYRP.Font("regular", 15), UI.S(70), h - UI.S(50), UI.Col.faint)
	end
	pnl.OnKeyCodePressed = function(_, key)
		if key == KEY_ESCAPE and not P.Binding then P.Close() end
	end

	local content = vgui.Create("DPanel", pnl)
	content:SetPos(ScrW() * 0.42, UI.S(110))
	content:SetSize(math.min(UI.S(620), ScrW() * 0.5), ScrH() - UI.S(220))
	content.Paint = function() end
	local function showContent(title, build)
		content:Clear()
		local head = vgui.Create("DPanel", content)
		head:Dock(TOP)
		head:SetTall(UI.S(60))
		head.Paint = function(_, w, h)
			draw.SimpleText(title, NYRP.Font("title", 32), 0, h / 2, UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		local body = vgui.Create("DPanel", content)
		body:Dock(FILL)
		body.Paint = function() end
		build(body)
		content:SetAlpha(0)
		content:AlphaTo(255, 0.2)
	end

	local buttons = {
		{ "ПРОДОЛЖИТЬ", "play", function() P.Close() end },
		{ "ПЕРСОНАЖИ", "users", function()
			P.Close()
			UI.Fade(0.4, 0.3, 0.6, function()
				net.Start("nyrp.char.menu")
				net.SendToServer()
				if NYRP.PointsConfigured then NYRP.Chars.OpenMenu(true) end
			end)
		end, not NYRP.PointsConfigured },
		{ "НАСТРОЙКИ", "settings", function() showContent("НАСТРОЙКИ", UI.BuildSettings) end },
		{ "БИНДЫ", "keyboard", function() showContent("БИНДЫ", buildBinds) end },
		{ "МЕНЮ ИГРЫ", "menu", function()
			P.Close()
			P.AllowGameUI = true
			gui.ActivateGameUI()
		end },
		{ "ОТКЛЮЧИТЬСЯ", "logout", function()
			UI.Confirm("Отключиться?", "Персонаж и инвентарь сохранятся.", "Отключиться", function() RunConsoleCommand("disconnect") end)
		end },
	}
	local y = ScrH() * 0.34
	for i, b in ipairs(buttons) do
		local btn = vgui.Create("NYRP.Button", pnl)
		btn:SetSize(UI.S(360), UI.S(56))
		btn:SetPos(UI.S(70), y)
		btn:SetLabel(b[1])
		btn:SetIcon(b[2])
		btn:SetFontStyle("title", 24)
		btn:SetEnabled(not b[4])
		btn.DoClick = b[3]
		btn:SetAlpha(0)
		btn:AlphaTo(255, 0.25, 0.04 * i)
		y = y + UI.S(64)
	end
	UI.Sound("open")
end
