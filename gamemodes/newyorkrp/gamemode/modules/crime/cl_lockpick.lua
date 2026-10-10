--[[
	Мини-игра взлома замка. Мышь влево/вправо — поворот отмычки в личинке (-90°..90°).
	Когда отмычка в «живой» зоне — она дрожит и тихо щёлкает: где-то рядом сладкое место.
	ЛКМ / Пробел — натяжение: сервер решает, провернулся ли замок. Не попали — личинка упрётся,
	отмычка может сломаться. ПКМ / Esc — бросить.
]]

NYRP.Crime = NYRP.Crime or {}
local C = NYRP.Crime
local UI = NYRP.UI

local lg   -- текущее состояние мини-игры
local pnl

local function quit(send)
	if send ~= false then
		net.Start("nyrp.crime.lockTry")
		net.WriteBool(true)
		net.SendToServer()
	end
	if IsValid(pnl) then pnl:Remove() end
	pnl, lg = nil, nil
end

local function try()
	local g = lg
	if not g or g.busy or g.done then return end
	g.busy = RealTime()
	g.turnTarget = 0
	surface.PlaySound("weapons/357/357_reload1.wav")
	net.Start("nyrp.crime.lockTry")
	net.WriteBool(false)
	net.WriteFloat(g.angle)
	net.SendToServer()
end

-- рисование: латунная личинка, скважина, отмычка и натяжитель
local function drawLock(g, w, h)
	local cx, cy = w / 2, h * 0.47
	local R = UI.S(150)
	-- корпус замка
	UI.Circle(cx, cy + UI.S(6), R + UI.S(26), Color(0, 0, 0, 120))
	UI.Circle(cx, cy, R + UI.S(22), Color(58, 60, 66))
	UI.Ring(cx, cy, R + UI.S(22), Color(255, 255, 255, 30))
	-- личинка (поворачивается при натяжении)
	local rot = g.turn * 90
	UI.Circle(cx, cy, R, Color(176, 140, 64))
	UI.Ring(cx, cy, R, Color(255, 230, 160, 90))
	UI.Circle(cx, cy, R * 0.78, Color(160, 126, 56))
	-- скважина — повёрнутый прямоугольник + круг
	local rad = math.rad(rot)
	local function rotp(x, y) return cx + x * math.cos(rad) - y * math.sin(rad), cy + x * math.sin(rad) + y * math.cos(rad) end
	draw.NoTexture()
	surface.SetDrawColor(18, 16, 14)
	local kw, kh = UI.S(14), UI.S(70)
	local x1, y1 = rotp(-kw / 2, -UI.S(10))
	local x2, y2 = rotp(kw / 2, -UI.S(10))
	local x3, y3 = rotp(kw / 2, kh)
	local x4, y4 = rotp(-kw / 2, kh)
	surface.DrawPoly({ { x = x1, y = y1 }, { x = x2, y = y2 }, { x = x3, y = y3 }, { x = x4, y = y4 } })
	local kx, ky = rotp(0, -UI.S(14))
	UI.Circle(kx, ky, UI.S(20), Color(18, 16, 14))
	-- натяжитель снизу (поворачивается с личинкой)
	local tx1, ty1 = rotp(-UI.S(4), UI.S(60))
	local tx2, ty2 = rotp(UI.S(4), UI.S(60))
	local tx3, ty3 = rotp(UI.S(4), R + UI.S(80))
	local tx4, ty4 = rotp(-UI.S(4), R + UI.S(80))
	surface.SetDrawColor(120, 124, 132)
	surface.DrawPoly({ { x = tx1, y = ty1 }, { x = tx2, y = ty2 }, { x = tx3, y = ty3 }, { x = tx4, y = ty4 } })
	-- отмычка: от скважины вверх, угол — g.angle, дрожит в живой зоне
	local shake = g.vib * UI.S(3) * math.sin(RealTime() * 70)
	local pa = math.rad(g.angle - 90 + rot) + shake * 0.004
	local len = R + UI.S(150)
	local ox, oy = kx, ky
	local ex, ey = ox + math.cos(pa) * len, oy + math.sin(pa) * len
	local nx, ny = -math.sin(pa) * UI.S(3), math.cos(pa) * UI.S(3)
	local pc = g.flash and RealTime() - g.flash < 0.4 and Color(230, 80, 70) or Color(205, 210, 218)
	surface.SetDrawColor(pc)
	surface.DrawPoly({ { x = ox - nx, y = oy - ny }, { x = ox + nx, y = oy + ny }, { x = ex + nx, y = ey + ny }, { x = ex - nx, y = ey - ny } })
	UI.Circle(ex, ey, UI.S(9), Color(40, 40, 46))
	-- крючок на конце в скважине
	UI.Circle(ox + math.cos(pa) * UI.S(4), oy + math.sin(pa) * UI.S(4), UI.S(4), pc)
	return cx, cy, R
end

local function open(door, hint, hintW, picks, lvl, name)
	if IsValid(pnl) then pnl:Remove() end
	lg = { door = door, hint = hint, hintW = hintW, picks = picks, lvl = lvl, name = name,
		angle = 0, turn = 0, turnTarget = 0, vib = 0, nextClick = 0 }
	local f = vgui.Create("EditablePanel")
	pnl = f
	f:SetSize(ScrW(), ScrH())
	f:MakePopup()
	f:SetKeyboardInputEnabled(true)
	f:SetCursor("blank")
	f.Born = RealTime()
	local lastX
	f.Think = function(s)
		local g = lg
		if not g then s:Remove() return end
		if not IsValid(g.door) or not LocalPlayer():Alive() or gui.IsGameUIVisible() then
			if gui.IsGameUIVisible() then gui.HideGameUI() end
			quit()
			return
		end
		-- мышь двигает отмычку (курсор возвращаем в центр — бесконечная «прокрутка»)
		local mx = gui.MouseX()
		if lastX and not g.busy then
			g.angle = math.Clamp(g.angle + (mx - lastX) * 0.22, -C.Lock.MaxAngle, C.Lock.MaxAngle)
		end
		input.SetCursorPos(ScrW() / 2, ScrH() / 2)
		lastX = ScrW() / 2
		-- вибрация в живой зоне
		local d = math.abs(g.angle - g.hint)
		local v = d < g.hintW and (1 - d / g.hintW) or 0
		g.vib = UI.Approach(g.vib, v, 6)
		if v > 0 and RealTime() > g.nextClick and not g.busy then
			g.nextClick = RealTime() + 0.45 - v * 0.3
			surface.PlaySound("buttons/lightswitch2.wav")
		end
		-- натяжение
		if g.busy and RealTime() - g.busy > 3 then g.busy = nil end -- сервер не ответил
		g.turn = UI.Approach(g.turn, g.turnTarget, g.done and 3 or 5)
		if g.backAt and RealTime() > g.backAt then g.backAt, g.turnTarget, g.busy = nil, 0, nil end
		if g.done and RealTime() - g.done > 1.1 then quit(false) end
		if g.out and RealTime() - g.out > 0.9 then quit(false) end
	end
	f.OnMousePressed = function(_, code)
		if code == MOUSE_LEFT then try() elseif code == MOUSE_RIGHT then quit() end
	end
	f.OnKeyCodePressed = function(_, key)
		if key == KEY_SPACE then try() elseif key == KEY_ESCAPE then quit() end
	end
	f.Paint = function(s, w, h)
		local g = lg
		if not g then return end
		local t = UI.Ease((RealTime() - s.Born) / 0.25)
		s:SetAlpha(255 * t)
		UI.BlurPanel(s, 3)
		surface.SetDrawColor(4, 5, 10, 200)
		surface.DrawRect(0, 0, w, h)
		local cx, cy, R = drawLock(g, w, h)
		-- шапка
		UI.DrawIcon("lock", cx - UI.S(150), UI.S(70), UI.S(26), UI.Col.accent)
		draw.SimpleText("ВЗЛОМ ЗАМКА", NYRP.Font("title", 28), cx - UI.S(128), UI.S(70), UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText(g.name .. " · ловкость " .. g.lvl, NYRP.Font("medium", 15), cx - UI.S(128), UI.S(98), UI.Col.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		-- отмычки
		local px = cx + UI.S(150)
		draw.SimpleText("Отмычек: " .. g.picks, NYRP.Font("semibold", 18), px, UI.S(70), g.picks <= 1 and UI.Col.red or UI.Col.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		-- подсказки
		local by = h - UI.S(90)
		local tips = { { "МЫШЬ", "повернуть отмычку" }, { "ЛКМ / ПРОБЕЛ", "провернуть замок" }, { "ПКМ / ESC", "бросить" } }
		local tw = 0
		local font, fk = NYRP.Font("regular", 14), NYRP.Font("bold", 13)
		for _, tp in ipairs(tips) do tw = tw + UI.TextSize(tp[1], fk) + UI.TextSize(tp[2], font) + UI.S(52) end
		local x = cx - tw / 2
		for _, tp in ipairs(tips) do
			local kw = UI.TextSize(tp[1], fk) + UI.S(14)
			UI.RoundedRect(UI.S(4), x, by - UI.S(11), kw, UI.S(22), Color(255, 255, 255, 230))
			draw.SimpleText(tp[1], fk, x + kw / 2, by, Color(12, 14, 20), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			draw.SimpleText(tp[2], font, x + kw + UI.S(8), by, UI.Col.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			x = x + kw + UI.S(8) + UI.TextSize(tp[2], font) + UI.S(30)
		end
		-- статус
		local st, col = "Ищите место, где отмычка дрожит", UI.Col.dim
		if g.vib > 0.5 then st, col = "Чувствуете отдачу — где-то здесь", UI.Col.accent end
		if g.msg and RealTime() - g.msgT < 1.6 then st, col = g.msg, g.msgCol end
		draw.SimpleText(st, NYRP.Font("semibold", 18), cx, cy + R + UI.S(110), col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end

net.Receive("nyrp.crime.lock", function()
	if not net.ReadBool() then
		if IsValid(pnl) then pnl:Remove() end
		pnl, lg = nil, nil
		return
	end
	local door, hint, hw, picks, lvl, name = net.ReadEntity(), net.ReadFloat(), net.ReadFloat(), net.ReadUInt(8), net.ReadUInt(8), net.ReadString()
	open(door, hint, hw, picks, lvl, name)
end)

net.Receive("nyrp.crime.lockRes", function()
	local code, frac, left = net.ReadUInt(2), net.ReadFloat(), net.ReadUInt(8)
	local g = lg
	if not g then return end
	g.picks = left
	g.msgT = RealTime()
	if code == 1 then
		g.turnTarget, g.done = 1, RealTime()
		g.msg, g.msgCol = "Щёлк! Замок открыт", UI.Col.green
		surface.PlaySound("doors/door_latch3.wav")
	elseif code == 2 then
		g.turnTarget = frac
		g.backAt = RealTime() + 0.6
		g.msg, g.msgCol = frac > 0.6 and "Почти! Совсем рядом" or "Личинка упёрлась", frac > 0.6 and UI.Col.accent or UI.Col.dim
	else
		g.turnTarget = frac
		g.backAt = RealTime() + 0.6
		g.flash = RealTime()
		g.msg, g.msgCol = "Отмычка сломалась!", UI.Col.red
		surface.PlaySound("physics/metal/metal_solid_impact_bullet" .. math.random(1, 4) .. ".wav")
		if left <= 0 then g.out = RealTime() end
	end
end)
