--[[
	Вспышка при повышении навыка и при «озарении».
]]

local UI = NYRP.UI
local SK = NYRP.Skills
local fx = {}

local function skillDef(id)
	for _, s in ipairs(NYRP.Config.Skills) do if s.id == id then return s end end
end

net.Receive("nyrp.skills.fx", function()
	local id, up = net.ReadString(), net.ReadBool()
	local s = skillDef(id)
	if not s then return end
	fx[#fx + 1] = { s = s, up = up, born = RealTime(), level = SK.Level(LocalPlayer(), id) }
	surface.PlaySound(up and "nyrp/phone/game_record.wav" or "nyrp/phone/notify.wav")
	if SK.OnChange then SK.OnChange() end
end)

net.Receive("nyrp.skills", function()
	SK.Data = { skills = net.ReadTable(), xp = net.ReadTable(), today = net.ReadTable() }
	if SK.OnChange then SK.OnChange() end
end)

function SK.Request() net.Start("nyrp.skills") net.SendToServer() end

hook.Add("HUDPaint", "nyrp.skills.fx", function()
	local y = ScrH() * 0.22
	for i = #fx, 1, -1 do
		local f = fx[i]
		local t = RealTime() - f.born
		local life = f.up and 5 or 2.5
		if t > life then table.remove(fx, i)
		else
			local a = math.min(1, t / 0.3) * math.Clamp((life - t) / 0.5, 0, 1)
			local w, h = UI.S(f.up and 380 or 300), UI.S(f.up and 74 or 46)
			local x = ScrW() / 2 - w / 2
			surface.SetAlphaMultiplier(a)
			UI.RoundedRect(UI.S(12), x, y, w, h, Color(14, 12, 26, 230))
			UI.Glow(x + UI.S(36), y + h / 2, UI.S(90), UI.S(90), Color(247, 198, 0, 70))
			surface.SetMaterial(UI.Mat("nyrp/status/" .. (f.up and "skills" or "insight") .. ".png"))
			surface.SetDrawColor(247, 198, 0)
			local is = UI.S(f.up and 36 or 26)
			surface.DrawTexturedRect(x + UI.S(36) - is / 2, y + h / 2 - is / 2, is, is)
			if f.up then
				draw.SimpleText("НАВЫК ПОВЫШЕН", NYRP.Font("bold", 13), x + UI.S(70), y + UI.S(22), Color(247, 198, 0), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				draw.SimpleText(f.s.name .. " — уровень " .. f.level, NYRP.Font("title", 24), x + UI.S(70), y + UI.S(48), color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			else
				draw.SimpleText("Озарение! " .. f.s.name .. ": опыт ×2", NYRP.Font("bold", 16), x + UI.S(62), y + h / 2, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
			surface.SetAlphaMultiplier(1)
			y = y + h + UI.S(8)
		end
	end
end)
