--[[
	Рация на клиенте: окно частоты, индикатор эфира, щелчки при чужой передаче.
]]

local R = NYRP.Radio
local UI = NYRP.UI
local GREEN = Color(96, 220, 110)

function R.OpenUI()
	if IsValid(R.Win) then R.Win:Close() return end
	local ply = LocalPlayer()
	local freq = ply:GetNW2Float("nyrp.radioSet", 150)
	if freq <= 0 then freq = 150 end
	local on = R.Freq(ply) > 0
	local win, body = UI.Window("Рация", "radio", 420, 380, { sub = "100.0 – 300.0 МГц", keyboard = true })
	R.Win = win
	local lcd = vgui.Create("DPanel", body)
	lcd:Dock(TOP)
	lcd:SetTall(UI.S(96))
	lcd.Paint = function(_, w, h)
		UI.RoundedRect(UI.S(10), 0, 0, w, h, on and Color(26, 52, 30) or Color(24, 26, 28))
		UI.Outline(UI.S(10), 0, 0, w, h, Color(0, 0, 0, 160), 2)
		draw.SimpleText(R.Format(freq), NYRP.Font("title", 54), w / 2, h / 2 - UI.S(6), on and Color(150, 240, 140) or Color(80, 90, 84), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		draw.SimpleText(on and "ВКЛ · МГц" or "ВЫКЛ", NYRP.Font("bold", 13), w / 2, h - UI.S(14), on and GREEN or UI.Col.faint, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	lcd.OnMouseWheeled = function(_, d) freq = R.Clamp(freq + d * 0.1) UI.Sound("hover") end
	local row = vgui.Create("DPanel", body)
	row:Dock(TOP)
	row:DockMargin(0, UI.S(12), 0, UI.S(12))
	row:SetTall(UI.S(40))
	row.Paint = function() end
	for _, d in ipairs({ -10, -1, -0.1, 0.1, 1, 10 }) do
		local b = UI.AddButton(row, (d > 0 and "+" or "−") .. tostring(math.abs(d)), nil, function() freq = R.Clamp(freq + d) end, { dock = LEFT, h = 40 })
		b:SetWide(UI.S(58))
		b:DockMargin(0, 0, UI.S(4), 0)
		b:SetAlign(TEXT_ALIGN_CENTER)
	end
	local entry = vgui.Create("DTextEntry", body)
	entry:Dock(TOP)
	entry:SetTall(UI.S(36))
	entry:DockMargin(0, 0, 0, UI.S(12))
	entry:SetFont(NYRP.Font("semibold", 16))
	entry:SetPlaceholderText("Ввести частоту, например 155.5 — Enter")
	entry.OnEnter = function(s) local v = tonumber(string.gsub(s:GetValue(), ",", ".")) if v then freq = R.Clamp(v) end s:SetValue("") end
	local function send(state)
		on = state
		net.Start("nyrp.radio.set")
		net.WriteFloat(freq)
		net.WriteBool(on)
		net.SendToServer()
	end
	UI.AddButton(body, "Настроить на " .. "частоту", "check", function() send(true) UI.Sound("success") end, { style = "solid", accent = GREEN }).Think = function(s)
		s:SetLabel("Настроить: " .. R.Format(freq) .. " МГц")
	end
	UI.AddButton(body, on and "Выключить рацию" or "Включить", "bolt", function(s) send(not on) s:SetLabel(on and "Выключить рацию" or "Включить") end)
end

-- щелчок в эфире, когда кто-то на нашей частоте начинает/заканчивает говорить
local txState = {}
hook.Add("Think", "nyrp.radio.rx", function()
	local me = LocalPlayer()
	if not IsValid(me) then return end
	local my = R.Freq(me)
	for _, p in ipairs(player.GetAll()) do
		local tx = p ~= me and my > 0 and R.Transmitting(p) and math.abs(R.Freq(p) - my) < 0.05
		if tx ~= (txState[p] or false) then
			txState[p] = tx
			surface.PlaySound(tx and "nyrp/fx/radio_on.wav" or "nyrp/fx/radio_off.wav")
		end
	end
end)

-- индикатор: «ПЕРЕДАЧА 150.0» у себя и «ЭФИР» при приёме
hook.Add("HUDPaint", "nyrp.radio", function()
	if NYRP.HUDHidden and NYRP.HUDHidden() then return end
	local me = LocalPlayer()
	local my = R.Freq(me)
	if my <= 0 then return end
	local rx = false
	for p, v in pairs(txState) do if v and IsValid(p) then rx = true end end
	local tx = R.Transmitting(me)
	if not tx and not rx then return end
	local w, h = UI.S(220), UI.S(40)
	local x, y = ScrW() / 2 - w / 2, ScrH() - UI.S(170)
	UI.RoundedRect(UI.S(10), x, y, w, h, Color(10, 22, 12, 220))
	local pulse = 0.6 + 0.4 * math.abs(math.sin(RealTime() * 5))
	UI.DrawIcon("radio", x + UI.S(22), y + h / 2, UI.S(20), UI.Alpha(GREEN, 255 * pulse))
	draw.SimpleText((tx and "ПЕРЕДАЧА " or "ЭФИР ") .. R.Format(my), NYRP.Font("bold", 16), x + UI.S(42), y + h / 2, GREEN, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end)
