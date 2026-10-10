--[[
	Сидящий игрок: корпус развёрнут по месту, таз — на сиденье (смещение модели подбирается по кости таза,
	поэтому подходит любая модель), подсказка «Пробел — встать». С зажатым Alt — подсказка «E — сесть».
]]
local S = NYRP.Sit
local UI = NYRP.UI
local PELVIS_ABOVE = 5        -- кость таза над поверхностью сиденья
local offsets = {}            -- модель -> положение таза относительно ног в позе сидя

local function target(ply)
	local seat = ply:GetNW2Vector("nyrp.sitPos")
	local ang = Angle(0, ply:GetNW2Float("nyrp.sitYaw"), 0)
	local key = ply:GetModel() .. (S.Ground(ply) and "#g" or "")
	local lp = offsets[key] or Vector(-4, 0, S.Ground(ply) and 8 or 18)
	local origin = seat + Vector(0, 0, PELVIS_ABOVE) - LocalToWorld(lp, angle_zero, vector_origin, ang)
	return origin, ang, key
end

hook.Add("PrePlayerDraw", "nyrp.sit", function(ply)
	if not S.Sitting(ply) then return end
	local origin, ang = target(ply)
	ply:SetRenderOrigin(origin)
	ply:SetRenderAngles(ang)
	ply:InvalidateBoneCache()
	ply.nyrpSitDrawn = true
end)

hook.Add("PostPlayerDraw", "nyrp.sit", function(ply)
	if not ply.nyrpSitDrawn then return end
	ply.nyrpSitDrawn = nil
	if S.Sitting(ply) then
		local _, ang, key = target(ply)
		local b = ply:LookupBone("ValveBiped.Bip01_Pelvis")
		local m = b and ply:GetBoneMatrix(b)
		if m then
			local lp = WorldToLocal(m:GetTranslation(), angle_zero, ply:GetRenderOrigin() or ply:GetPos(), ang)
			local old = offsets[key]
			offsets[key] = old and LerpVector(0.2, old, lp) or lp
		end
	end
	ply:SetRenderOrigin()
	ply:SetRenderAngles()
end)

hook.Add("HUDPaint", "nyrp.sit", function()
	local ply = LocalPlayer()
	if not IsValid(ply) or not ply:Alive() or NYRP.State ~= "playing" then return end
	local text
	if S.Sitting(ply) then
		text = "Пробел — встать"
	elseif input.IsKeyDown(KEY_LALT) and not vgui.CursorVisible() then
		local tr = ply:GetEyeTrace()
		if tr.Hit and tr.HitNormal.z > 0.7 and tr.HitPos:DistToSqr(ply:EyePos()) < 110 * 110 then
			local h = tr.HitPos.z - ply:GetPos().z
			if h <= 42 and h >= -24 then text = h < 8 and "E — сесть на пол" or "E — сесть" end
		end
	end
	if not text then return end
	local font = NYRP.Font("semibold", 15)
	local w = UI.TextSize(text, font) + UI.S(28)
	local x, y = ScrW() / 2 - w / 2, ScrH() - UI.S(210)
	UI.RoundedRect(UI.S(10), x, y, w, UI.S(32), Color(10, 12, 20, 200))
	draw.SimpleText(text, font, ScrW() / 2, y + UI.S(16), color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)
