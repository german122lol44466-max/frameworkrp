--[[
	Табличка на двери, которая сдаётся: название, цена в день, кто арендует. Видна, когда смотришь на дверь вблизи.
]]

local UI = NYRP.UI
local alpha = {}

hook.Add("HUDPaint", "nyrp.doors", function()
	if NYRP.HUDHidden() then return end
	local ply = LocalPlayer()
	local tr = ply:GetEyeTrace()
	local look = tr.Entity
	for ent, a in pairs(alpha) do
		if not IsValid(ent) then alpha[ent] = nil end
	end
	if IsValid(look) and look:GetNW2Int("nyrp.rent", 0) > 0 and tr.HitPos:Distance(ply:EyePos()) < 160 then
		alpha[look] = alpha[look] or 0
	end
	for ent, a in pairs(alpha) do
		local want = ent == look and tr.HitPos:Distance(ply:EyePos()) < 160
		a = UI.Approach(a, want and 1 or 0, want and 8 or 6)
		alpha[ent] = a
		if a <= 0.01 and not want then alpha[ent] = nil
		else
			local sc = (want and tr.HitPos or ent:WorldSpaceCenter()):ToScreen()
			local x, y = sc.x + UI.S(30), sc.y - UI.S(40)
			local name = ent:GetNW2String("nyrp.rentName", "Помещение")
			local owner = ent:GetNW2String("nyrp.rentOwnerName", "")
			local mine = ent:GetNW2Int("nyrp.rentOwner", 0) == ply:GetNW2Int("nyrp.charID", -1)
			local w, h = UI.S(300), UI.S(78)
			UI.RoundedRect(UI.S(12), x, y, w, h, Color(10, 12, 20, 220 * a))
			UI.RoundedRect(UI.S(2), x + UI.S(12), y + UI.S(14), UI.S(4), h - UI.S(28), UI.Alpha(owner == "" and UI.Col.green or Color(247, 198, 0), 255 * a))
			UI.DrawIcon(owner == "" and "home" or "lock", x + UI.S(38), y + h / 2, UI.S(24), Color(255, 255, 255, 230 * a))
			draw.SimpleText(name, NYRP.Font("bold", 17), x + UI.S(60), y + UI.S(14), Color(240, 241, 245, 255 * a))
			local sub
			if owner == "" then sub = "Сдаётся: " .. NYRP.Money.Format(ent:GetNW2Int("nyrp.rent", 0)) .. " в день · телефон → NY Homes"
			elseif mine then sub = "Ваша аренда · /lock, /unlock"
			else sub = "Арендовано" end
			draw.SimpleText(sub, NYRP.Font("medium", 13), x + UI.S(60), y + UI.S(42), Color(200, 204, 214, 230 * a))
		end
	end
end)
