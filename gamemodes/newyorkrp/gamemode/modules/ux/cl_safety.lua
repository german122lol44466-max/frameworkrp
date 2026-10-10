--[[
	Опущенное оружие на клиенте: модель оружия в руках плавно уходит вниз и в сторону,
	у прицела — подсказка «Оружие опущено · держите R», при подъёме — короткая «Оружие поднято».
	Удержание R показывает кольцо-прогресс вокруг прицела.
]]

local UI = NYRP.UI
local SF = NYRP.Safety

local lower = 0        -- 0 — поднято, 1 — опущено (плавно)
local hint = 0         -- прозрачность подсказки
local lastState, changedAt = nil, 0
local holdStart

hook.Add("CalcViewModelView", "nyrp.safety", function(wep, vm, oldPos, oldAng, pos, ang)
	local ply = LocalPlayer()
	if not IsValid(ply) or not IsValid(wep) then return end
	local target = SF.Lowered(ply, wep) and 1 or 0
	lower = UI.Approach(lower, target, target > lower and 5 or 7)
	if lower < 0.001 then return end
	local e = UI.EaseInOut and UI.EaseInOut(lower) or lower
	local a = Angle(ang.p, ang.y, ang.r)
	a:RotateAroundAxis(a:Right(), -28 * e)
	a:RotateAroundAxis(a:Up(), 16 * e)
	local p = pos - a:Up() * (4 * e) + a:Right() * (2 * e) - a:Forward() * (2 * e)
	return p, a
end)

hook.Add("HUDPaint", "nyrp.safety", function()
	local ply = LocalPlayer()
	if not IsValid(ply) or not ply:Alive() or NYRP.HUDHidden() then return end
	local wep = ply:GetActiveWeapon()
	local applies = SF.Applies(wep)
	local raised = SF.Raised(ply)
	local state = applies and (raised and "up" or "down") or nil
	if state ~= lastState then
		lastState = state
		changedAt = RealTime()
	end
	-- «опущено» видно постоянно (неярко), «поднято» — 1.5 с после подъёма
	local want = 0
	if state == "down" then want = 1 elseif state == "up" and RealTime() - changedAt < 1.5 then want = 1 end
	hint = UI.Approach(hint, want, 8)

	-- прогресс удержания R
	-- (ply:KeyDown не годится: у опущенного оружия IN_RELOAD вырезается из команды)
	local key = input.GetKeyCode(input.LookupBinding("+reload") or "r")
	local holding = applies and key and key > 0 and input.IsButtonDown(key) and not vgui.CursorVisible()
		and not IsValid(vgui.GetKeyboardFocus())
	if holding then holdStart = holdStart or RealTime() else holdStart = nil end

	if hint < 0.01 and not holdStart then return end
	local cx, cy = ScrW() / 2, ScrH() / 2
	if NYRP.Camera and NYRP.Camera.IsThirdPerson and NYRP.Camera.IsThirdPerson() then
		local s = ply:GetEyeTrace().HitPos:ToScreen()
		cx, cy = s.x, s.y
	end
	if holdStart then
		local f = math.Clamp((RealTime() - holdStart) / SF.HoldTime, 0, 1)
		if f < 1 then
			local r = UI.S(16)
			local seg = 32
			surface.SetDrawColor(247, 198, 0, 230)
			for i = 0, math.floor(seg * f) - 1 do
				local a0 = math.rad(i / seg * 360 - 90)
				local a1 = math.rad((i + 1) / seg * 360 - 90)
				surface.DrawLine(cx + math.cos(a0) * r, cy + math.sin(a0) * r, cx + math.cos(a1) * r, cy + math.sin(a1) * r)
				surface.DrawLine(cx + math.cos(a0) * (r + 1), cy + math.sin(a0) * (r + 1), cx + math.cos(a1) * (r + 1), cy + math.sin(a1) * (r + 1))
			end
		end
	end
	if hint < 0.01 then return end
	local down = state == "down"
	local text = down and "ОРУЖИЕ ОПУЩЕНО" or "ОРУЖИЕ ПОДНЯТО"
	local sub = down and "держите R — поднять" or "держите R — опустить"
	local font, sfont = NYRP.Font("bold", 12), NYRP.Font("regular", 11)
	local a = hint * (down and 0.85 or 1)
	local y = cy + UI.S(34)
	local tw = UI.TextSize(text, font)
	local isz = UI.S(14)
	local w = tw + isz + UI.S(30)
	local h = UI.S(24)
	UI.RoundedRect(h / 2, cx - w / 2, y, w, h, Color(10, 12, 20, 170 * a))
	local col = down and Color(200, 204, 214, 255 * a) or Color(255, 138, 36, 255 * a)
	UI.DrawIcon(down and "shield" or "crosshair", cx - w / 2 + UI.S(12) + isz / 2, y + h / 2, isz, col)
	draw.SimpleText(text, font, cx - w / 2 + UI.S(18) + isz, y + h / 2, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	draw.SimpleText(sub, sfont, cx, y + h + UI.S(4), Color(200, 204, 214, 140 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
end)
