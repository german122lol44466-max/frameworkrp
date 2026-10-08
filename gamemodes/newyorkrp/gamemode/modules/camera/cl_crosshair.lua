--[[
	Динамичный прицел-кружок: маленькое кольцо по центру, при наведении на то,
	с чем можно взаимодействовать, плавно увеличивается и становится оранжевым.
]]

local UI = NYRP.UI
local hover, size, alpha = 0, 0, 0

hook.Add("HUDPaint", "nyrp.crosshair", function()
	local ply = LocalPlayer()
	if NYRP.HUDHidden() or not IsValid(ply) or not ply:Alive() then return end
	if NYRP.Inventory and NYRP.Inventory.IsOpen and NYRP.Inventory.IsOpen() then return end

	local target = NYRP.Interact and NYRP.Interact.Target
	hover = UI.Approach(hover, IsValid(target) and 1 or 0, 12)
	size = UI.Approach(size, 1, 10)
	local moving = math.Clamp(ply:GetVelocity():Length2D() / 220, 0, 1)
	alpha = UI.Approach(alpha, 1 - moving * 0.35, 8)

	local cx, cy = ScrW() / 2, ScrH() / 2
	if NYRP.Camera.IsThirdPerson() then
		local tr = ply:GetEyeTrace()
		local s = tr.HitPos:ToScreen()
		cx, cy = s.x, s.y
	end
	local r = UI.S(4 + hover * 6) * size
	local col = UI.LerpColor(hover, Color(255, 255, 255, 210 * alpha), Color(255, 138, 36, 255))
	UI.Circle(cx, cy, r + UI.S(2), Color(0, 0, 0, 60 * alpha))
	UI.Ring(cx, cy, r, col)
	if hover > 0.05 then
		UI.Circle(cx, cy, UI.S(2) * hover, col)
	end
end)
