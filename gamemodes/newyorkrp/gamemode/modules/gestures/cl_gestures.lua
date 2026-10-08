--[[
	Круговое меню жестов: удерживайте G — меню появляется в центре экрана, наведите курсор
	на сектор и отпустите G (или кликните). Список жестов — sh_gestures.lua.
]]

local UI = NYRP.UI
local G = NYRP.Gestures

local function canUse()
	local ply = LocalPlayer()
	return NYRP.State == "playing" and ply:Alive() and not (NYRP.Cond and NYRP.Cond.KO(ply))
		and not (NYRP.Inventory.IsOpen and NYRP.Inventory.IsOpen())
end

local function play(g)
	if not g then return end
	net.Start("nyrp.gesture.play")
	net.WriteUInt(g.index, 8)
	net.SendToServer()
	UI.Sound("click")
end

function G.OpenRadial()
	if IsValid(G.Radial) or not canUse() then return end
	local pnl = vgui.Create("EditablePanel")
	G.Radial = pnl
	pnl:SetSize(ScrW(), ScrH())
	pnl:MakePopup()
	pnl:SetKeyboardInputEnabled(false)
	input.SetCursorPos(ScrW() / 2, ScrH() / 2)
	pnl.Born = RealTime()
	pnl.Hover = {}
	pnl.Sel = nil
	UI.Sound("open")

	local n = #G.List
	local R1, R2 = UI.S(110), UI.S(250)   -- внутренний и внешний радиус кольца

	pnl.Think = function(s)
		if s.Closing then return end
		local mx, my = gui.MousePos()
		local dx, dy = mx - ScrW() / 2, my - ScrH() / 2
		local d = math.sqrt(dx * dx + dy * dy)
		local sel
		if d > R1 * 0.55 then
			local a = (math.deg(math.atan2(dx, -dy)) + 360 + 180 / n) % 360
			sel = math.floor(a / (360 / n)) + 1
		end
		if sel ~= s.Sel and sel then UI.Sound("hover") end
		s.Sel = sel
	end
	pnl.OnMousePressed = function(s, code)
		if code == MOUSE_LEFT and s.Sel then
			play(G.List[s.Sel])
			G.CloseRadial()
		elseif code == MOUSE_RIGHT then
			G.CloseRadial()
		end
	end
	pnl.Paint = function(s, w, h)
		local t = UI.Ease((RealTime() - s.Born) / 0.22)
		if s.Closing then t = t * (1 - UI.Ease((RealTime() - s.Closing) / 0.15)) end
		local cx, cy = w / 2, h / 2
		local sc = 0.85 + 0.15 * t
		surface.SetAlphaMultiplier(t)
		UI.BlurRect(0, 0, w, h, 2 * t)
		surface.SetDrawColor(4, 5, 9, 110)
		surface.DrawRect(0, 0, w, h)
		UI.Vignette(0, 0, w, h, 200)

		-- кольцо
		local r1, r2 = R1 * sc, R2 * sc
		local seg = 360 / n
		for i, g in ipairs(G.List) do
			s.Hover[i] = UI.Approach(s.Hover[i] or 0, s.Sel == i and 1 or 0, 16)
			local hv = s.Hover[i]
			local a0, a1 = (i - 1) * seg - seg / 2 + 1.2, i * seg - seg / 2 - 1.2
			local poly = {}
			local outer = r2 + hv * UI.S(10)
			for k = 0, 10 do
				local a = math.rad(a0 + (a1 - a0) * k / 10)
				poly[#poly + 1] = { x = cx + math.sin(a) * outer, y = cy - math.cos(a) * outer }
			end
			for k = 10, 0, -1 do
				local a = math.rad(a0 + (a1 - a0) * k / 10)
				poly[#poly + 1] = { x = cx + math.sin(a) * r1, y = cy - math.cos(a) * r1 }
			end
			draw.NoTexture()
			surface.SetDrawColor(UI.LerpColor(hv, Color(14, 16, 24, 225), Color(40, 34, 14, 240)))
			-- выпуклые многоугольники: рисуем сектор полосками
			for k = 1, 10 do
				surface.DrawPoly({ poly[k], poly[k + 1], poly[22 - k], poly[23 - k] })
			end
			local mid = math.rad((a0 + a1) / 2)
			local ir = (r1 + outer) / 2
			local ix, iy = cx + math.sin(mid) * ir, cy - math.cos(mid) * ir
			UI.DrawIcon(g.icon, ix, iy - UI.S(8), UI.S(30) * (1 + hv * 0.15), UI.LerpColor(hv, Color(220, 222, 230), UI.Col.accent))
			draw.SimpleText(g.name, NYRP.Font("semibold", 12), ix, iy + UI.S(20), UI.LerpColor(hv, UI.Col.dim, UI.Col.text), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		-- обводки
		UI.Ring(cx, cy, r2 + UI.S(2), Color(255, 255, 255, 14))
		-- центр
		UI.Circle(cx, cy, r1 - UI.S(10), Color(8, 9, 14, 235))
		UI.Ring(cx, cy, r1 - UI.S(10), Color(255, 255, 255, 18))
		local g = s.Sel and G.List[s.Sel]
		if g then
			UI.DrawIcon(g.icon, cx, cy - UI.S(18), UI.S(34), UI.Col.accent)
			draw.SimpleText(g.name, NYRP.Font("bold", 17), cx, cy + UI.S(18), UI.Col.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		else
			draw.SimpleText("ЖЕСТЫ", NYRP.Font("title", 24), cx, cy - UI.S(6), UI.Col.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		draw.SimpleText("отпустите G или кликните · ПКМ — отмена", NYRP.Font("regular", 12), cx, cy + UI.S(42), UI.Col.faint, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		surface.SetAlphaMultiplier(1)
	end
end

function G.CloseRadial()
	local pnl = G.Radial
	if not IsValid(pnl) or pnl.Closing then return end
	pnl.Closing = RealTime()
	pnl:SetMouseInputEnabled(false)
	timer.Simple(0.16, function() if IsValid(pnl) then pnl:Remove() end end)
end

-- Отпустили G: выбранный жест (если навели) и закрыть.
function G.ReleaseRadial()
	local pnl = G.Radial
	if not IsValid(pnl) or pnl.Closing then return end
	if pnl.Sel and RealTime() - pnl.Born > 0.12 then play(G.List[pnl.Sel]) end
	G.CloseRadial()
end

hook.Add("NYRP.StateChanged", "nyrp.gestures", function() G.CloseRadial() end)
