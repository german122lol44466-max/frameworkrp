--[[
	Потеря связи с сервером: если сервер не отвечает дольше 4 секунд (GetTimeoutInfo), экран темнеет,
	появляется «Потеряно соединение с сервером», счётчик и автоматическое переподключение через 30 с.
	Кнопки: «Переподключиться» (сразу) и «Выйти» (в главное меню). Связь вернулась — окно исчезает само.
]]

NYRP.UX = NYRP.UX or {}
local UX = NYRP.UX
local UI = NYRP.UI

UX.LostAfter = 4          -- через сколько секунд без ответа показывать окно
UX.ReconnectAfter = 30    -- автоматическое переподключение

local function close()
	local p = UX.LostPanel
	if not IsValid(p) or p.Closing then return end
	p.Closing = RealTime()
	p:SetMouseInputEnabled(false)
	p:SetKeyboardInputEnabled(false)
	timer.Simple(0.35, function() if IsValid(p) then p:Remove() end end)
end

local function retry()
	if UX.Retried then return end
	UX.Retried = true
	RunConsoleCommand("retry")
end

local function open(since)
	if IsValid(UX.LostPanel) and not UX.LostPanel.Closing then return end
	if IsValid(UX.LostPanel) then UX.LostPanel:Remove() end
	UX.Retried = false
	local p = vgui.Create("EditablePanel")
	UX.LostPanel = p
	p:SetSize(ScrW(), ScrH())
	p:SetZPos(32000)
	p:MakePopup()
	p:SetKeyboardInputEnabled(false)
	p.Born = RealTime()
	p.Lost = since
	p.Paint = function(s, w, h)
		local t = UI.Ease((RealTime() - s.Born) / 0.6)
		if s.Closing then t = t * (1 - UI.Ease((RealTime() - s.Closing) / 0.3)) end
		surface.SetAlphaMultiplier(t)
		UI.BlurPanel(s, 6)
		surface.SetDrawColor(3, 4, 8, 225)
		surface.DrawRect(0, 0, w, h)
		UI.Vignette(0, 0, w, h, 255)
		local cx, cy = w / 2, h / 2 - UI.S(70)
		-- значок: мигающий сигнал
		local pulse = 0.5 + 0.5 * math.sin(RealTime() * 4)
		UI.Circle(cx, cy - UI.S(40), UI.S(44) + pulse * UI.S(6), Color(214, 70, 64, 40 + 40 * pulse))
		UI.Circle(cx, cy - UI.S(40), UI.S(34), Color(214, 70, 64, 230))
		UI.DrawIcon("p_wifi", cx, cy - UI.S(40), UI.S(36), color_white)
		draw.SimpleText("ПОТЕРЯНО СОЕДИНЕНИЕ С СЕРВЕРОМ", NYRP.Font("title", 34), cx, cy + UI.S(30), UI.Col.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		local lost = math.floor(RealTime() - s.Lost)
		local left = math.max(0, math.ceil(UX.ReconnectAfter - (RealTime() - s.Lost)))
		draw.SimpleText("Сервер не отвечает уже " .. lost .. " с. Возможно, он перезапускается или пропал интернет.",
			NYRP.Font("regular", 16), cx, cy + UI.S(70), UI.Col.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		local msg = UX.Retried and "Переподключение..." or ("Автоматическое переподключение через " .. left .. " с")
		draw.SimpleText(msg, NYRP.Font("semibold", 17), cx, cy + UI.S(104), UI.Col.accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		-- полоса обратного отсчёта
		local bw = UI.S(360)
		local f = math.Clamp((RealTime() - s.Lost) / UX.ReconnectAfter, 0, 1)
		UI.RoundedRect(UI.S(3), cx - bw / 2, cy + UI.S(128), bw, UI.S(6), Color(255, 255, 255, 20))
		UI.RoundedRect(UI.S(3), cx - bw / 2, cy + UI.S(128), bw * f, UI.S(6), UI.Col.accent)
		surface.SetAlphaMultiplier(1)
	end
	p.Think = function(s)
		if not s.Closing and not UX.Retried and RealTime() - s.Lost >= UX.ReconnectAfter then retry() end
	end
	local bw, bh = UI.S(220), UI.S(48)
	local yb = ScrH() / 2 + UI.S(100)
	local rb = vgui.Create("NYRP.Button", p)
	rb:SetSize(bw, bh)
	rb:SetPos(ScrW() / 2 - bw - UI.S(8), yb)
	rb:SetLabel("Переподключиться")
	rb:SetIcon("refresh")
	rb:SetStyle("solid")
	rb:SetAlign(TEXT_ALIGN_CENTER)
	rb.DoClick = function() UX.Retried = false retry() end
	local qb = vgui.Create("NYRP.Button", p)
	qb:SetSize(bw, bh)
	qb:SetPos(ScrW() / 2 + UI.S(8), yb)
	qb:SetLabel("Выйти")
	qb:SetIcon("logout")
	qb:SetStyle("ghost")
	qb:SetAccent(UI.Col.red)
	qb:SetAlign(TEXT_ALIGN_CENTER)
	qb.DoClick = function() RunConsoleCommand("disconnect") end
	surface.PlaySound("buttons/button10.wav")
end

local lostSince
hook.Add("Think", "nyrp.ux.connection", function()
	if not GetTimeoutInfo then return end
	local timingOut, last = GetTimeoutInfo()
	if timingOut and (last or 0) >= UX.LostAfter then
		lostSince = lostSince or (RealTime() - (last or 0))
		open(lostSince)
	elseif lostSince then
		lostSince = nil
		close()
		if NYRP.Notify then NYRP.Notify("Соединение с сервером восстановлено", "success", 4) end
	end
end)
