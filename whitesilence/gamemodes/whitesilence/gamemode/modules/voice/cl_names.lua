--[[
	Ник при взгляде на игрока: над головой появляется имя (позывной), слева — иконка:
	свой отряд — щит, говорит — микрофон, остальные — силуэт. Плавно появляется и гаснет.
]]

local L = WS.Lobby
local UI = WS.UI
local target, alpha = nil, 0

local function icon(n) return UI.Mat("whitesilence/icons/" .. n .. ".png", "smooth") end

hook.Add("HUDPaint", "ws.names", function()
	local me = LocalPlayer()
	if not IsValid(me) or not me:Alive() or not WS.Lobby.InGame(me) then return end
	local tr = util.TraceLine({ start = me:EyePos(), endpos = me:EyePos() + me:GetAimVector() * 320, filter = me, mask = MASK_SHOT })
	local hit = tr.Entity
	if IsValid(hit) and hit:IsPlayer() and hit:Alive() and not hit:GetNoDraw() then target = hit end
	alpha = WS.Approach(alpha, (IsValid(hit) and hit == target) and 1 or 0, (IsValid(hit) and hit == target) and 6 or 2.5)
	if alpha <= 0 or not IsValid(target) then return end

	local bone = target:LookupBone("ValveBiped.Bip01_Head1")
	local pos = bone and target:GetBonePosition(bone) or target:EyePos()
	local sp = (pos + Vector(0, 0, 14)):ToScreen()
	if not sp.visible then return end
	local s = ScrH() / 1080
	local mate = L.Id(target) == L.Id(me) and L.Id(me) ~= 0
	local ic = target:IsSpeaking() and "mic" or (mate and "squad" or "user")
	local col = mate and Color(226, 190, 120) or Color(236, 239, 244)
	local font = WS.Font("menusemi", 20)
	local name = L.Name(target)
	surface.SetFont(font)
	local tw, th = surface.GetTextSize(name)
	local is = 20 * s
	local total = is + 8 * s + tw
	local x = sp.x - total / 2
	local y = sp.y - th / 2
	surface.SetMaterial(icon(ic))
	surface.SetDrawColor(0, 0, 0, 160 * alpha)
	surface.DrawTexturedRect(x + 1, y + th / 2 - is / 2 + 2, is, is)
	surface.SetDrawColor(col.r, col.g, col.b, 255 * alpha)
	surface.DrawTexturedRect(x, y + th / 2 - is / 2, is, is)
	draw.SimpleText(name, font, x + is + 8 * s + 1, sp.y + 2, Color(0, 0, 0, 170 * alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	draw.SimpleText(name, font, x + is + 8 * s, sp.y, Color(col.r, col.g, col.b, 255 * alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	if mate then
		draw.SimpleText("ваш отряд", WS.Font("menulight", 14), sp.x, sp.y + th * 0.75, Color(226, 190, 120, 200 * alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end)
