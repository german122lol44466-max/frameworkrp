--[[
	Круговое меню «в мире» (игрок, тело): кнопки раскрываются вокруг точки на объекте и следуют за ним.
	Курсора нет: выбор — движением мыши (камера в это время стоит), подтверждение — E или ЛКМ,
	отмена — ПКМ или отойти. Справа внизу подсказка «ВЫБРАТЬ [E]».

	NYRP.WorldRadial.Open({
		anchor = function() return Vector end,   -- точка в мире
		valid = function() return bool end,       -- пока true — меню открыто
		options = { { id, name, icon, disabled = bool, note = "почему нельзя" } },
		onSelect = function(opt) end,
	})
]]

local UI = NYRP.UI
local WR = {}
NYRP.WorldRadial = WR

local cur

function WR.IsOpen() return cur ~= nil and not cur.closing end

function WR.Close()
	if cur and not cur.closing then
		cur.closing = RealTime()
		UI.Sound("close")
	end
end

function WR.Open(menu)
	if WR.IsOpen() then WR.Close() return end
	cur = menu
	cur.born = RealTime()
	cur.aim = Vector(0, 0, 0)
	cur.hover = {}
	cur.sel = nil
	UI.Sound("open")
end

local function choose()
	local m = cur
	if not m or m.closing or not m.sel then return end
	local opt = m.options[m.sel]
	if opt.disabled then
		UI.Sound("error")
		if opt.note then NYRP.Notify(opt.note, "warning", 3) end
		return
	end
	UI.Sound("click")
	m.closing = RealTime()
	m.onSelect(opt)
end

-- Мышь двигает «указатель» выбора, а не камеру.
hook.Add("InputMouseApply", "nyrp.worldradial", function(cmd, x, y, ang)
	if not WR.IsOpen() then return end
	local m = cur
	m.aim = m.aim + Vector(x, y, 0) * 0.012
	if m.aim:Length() > 1 then m.aim = m.aim:GetNormalized() end
	local n = #m.options
	local sel
	if m.aim:Length() > 0.35 then
		local a = (math.deg(math.atan2(m.aim.x, -m.aim.y)) + 360 + 180 / n) % 360
		sel = math.floor(a / (360 / n)) + 1
	end
	if sel and sel ~= m.sel then UI.Sound("hover") end
	m.sel = sel
	cmd:SetMouseX(0)
	cmd:SetMouseY(0)
	return true
end)

hook.Add("PlayerBindPress", "nyrp.worldradial", function(ply, bind, pressed)
	if not WR.IsOpen() or not pressed then return end
	if string.find(bind, "+attack2", 1, true) then WR.Close() return true end
	if string.find(bind, "+use", 1, true) or string.find(bind, "+attack", 1, true) then
		choose()
		return true
	end
	if string.find(bind, "invnext", 1, true) or string.find(bind, "invprev", 1, true) or string.find(bind, "slot", 1, true) then return true end
end)

hook.Add("Think", "nyrp.worldradial", function()
	local m = cur
	if not m then return end
	if m.closing then
		if RealTime() - m.closing > 0.2 then cur = nil end
		return
	end
	if not LocalPlayer():Alive() or (m.valid and not m.valid()) or gui.IsGameUIVisible() then WR.Close() end
end)

hook.Add("HUDPaint", "nyrp.worldradial", function()
	local m = cur
	if not m then return end
	local t = UI.Ease((RealTime() - m.born) / 0.25)
	if m.closing then t = t * (1 - UI.Ease((RealTime() - m.closing) / 0.2)) end
	local pos = m.anchor and m.anchor()
	if not pos then return end
	local sc = pos:ToScreen()
	local cx, cy = sc.x, sc.y
	local n = #m.options
	local R = UI.S(118) * (0.5 + 0.5 * t)
	surface.SetAlphaMultiplier(t)
	UI.Glow(cx, cy, R * 3.4, R * 3.4, Color(0, 0, 0, 170))
	-- центр: «E» и стрелка выбора
	UI.Circle(cx, cy, UI.S(24), Color(255, 255, 255, 245))
	draw.SimpleText("E", NYRP.Font("bold", 22), cx, cy, Color(12, 14, 20), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	if m.aim:Length() > 0.05 then
		local d = m.aim:GetNormalized()
		local px, py = cx + d.x * UI.S(36) * math.min(m.aim:Length() / 0.35, 1), cy + d.y * UI.S(36) * math.min(m.aim:Length() / 0.35, 1)
		UI.Circle(px, py, UI.S(4), UI.Col.accent)
	end
	for i, opt in ipairs(m.options) do
		m.hover[i] = UI.Approach(m.hover[i] or 0, m.sel == i and 1 or 0, 16)
		local hv = m.hover[i]
		local a = math.rad(-90 + (i - 1) * 360 / n)
		local x, y = cx + math.cos(a) * R, cy + math.sin(a) * R
		surface.SetDrawColor(255, 255, 255, 25 + 60 * hv)
		surface.DrawLine(cx, cy, x, y)
		local r = UI.S(32) + hv * UI.S(5)
		local dis = opt.disabled
		UI.Circle(x, y + UI.S(2), r + UI.S(3), Color(0, 0, 0, 90))
		UI.Circle(x, y, r, dis and Color(20, 20, 24, 200) or UI.LerpColor(hv, Color(14, 16, 24, 235), Color(247, 198, 0, 255)))
		UI.Ring(x, y, r, Color(255, 255, 255, 30 + 60 * (1 - hv)))
		UI.DrawIcon(opt.icon, x, y, UI.S(24), dis and Color(110, 112, 120) or UI.LerpColor(hv, Color(236, 237, 242), Color(14, 14, 18)))
		local font = NYRP.Font("semibold", 15)
		local ty = y + r + UI.S(14)
		draw.SimpleText(opt.name, font, x + 1, ty + 2, Color(0, 0, 0, 170), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		draw.SimpleText(opt.name, font, x, ty, dis and Color(130, 132, 140) or UI.LerpColor(hv, Color(225, 227, 233), UI.Col.accent), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		if dis and opt.note and hv > 0.05 then
			draw.SimpleText(opt.note, NYRP.Font("regular", 12), x, ty + UI.S(16), Color(214, 120, 110, 230 * hv), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end
	-- подсказка как в референсе
	local kx, ky = ScrW() - UI.S(60), ScrH() - UI.S(70)
	UI.Outline(UI.S(4), kx, ky - UI.S(14), UI.S(28), UI.S(28), Color(255, 255, 255, 220), 1)
	draw.SimpleText("E", NYRP.Font("bold", 15), kx + UI.S(14), ky, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText("ВЫБРАТЬ", NYRP.Font("title", 18), kx - UI.S(12), ky, color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	draw.SimpleText("мышь — выбор · ПКМ — отмена", NYRP.Font("regular", 12), kx + UI.S(28), ky + UI.S(26), UI.Col.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	surface.SetAlphaMultiplier(1)
end)
