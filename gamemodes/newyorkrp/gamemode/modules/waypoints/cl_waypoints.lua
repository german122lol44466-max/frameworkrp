local W = NYRP.Waypoint
local UI = NYRP.UI
W.List = W.List or {}

net.Receive("nyrp.wp", function()
	local id, on = net.ReadString(), net.ReadBool()
	if not on then W.List[id] = nil return end
	W.List[id] = { pos = net.ReadVector(), label = net.ReadString(), icon = net.ReadString(), color = net.ReadColor(), born = RealTime() }
	surface.PlaySound("nyrp/phone/notify.wav")
end)

-- клиентская метка (без сервера): W.Local("id", pos, label, icon, color)
function W.Local(id, pos, label, icon, color)
	W.List[id] = { pos = pos, label = label or "", icon = icon or "map_pin", color = color or Color(247, 198, 0), born = RealTime() }
end
function W.Remove(id) W.List[id] = nil end

hook.Add("HUDPaint", "nyrp.waypoints", function()
	if NYRP.HUDHidden and NYRP.HUDHidden() then return end
	local eye = EyePos()
	local w, h = ScrW(), ScrH()
	local m = UI.S(60)
	for id, wp in pairs(W.List) do
		local p = wp.pos + Vector(0, 0, 40)
		local sc = p:ToScreen()
		local dist = math.floor(eye:Distance(wp.pos) * 0.019)
		local behind = (p - eye):GetNormalized():Dot(EyeAngles():Forward()) < 0
		local x, y = sc.x, sc.y
		local off = behind or x < m or x > w - m or y < m or y > h - m
		if behind then x, y = w - x, h - y end
		local pulse = 0.85 + 0.15 * math.sin(RealTime() * 4 + #id)
		local a = math.min(1, (RealTime() - wp.born) / 0.4)
		surface.SetAlphaMultiplier(a)
		if off then
			-- стрелка у края экрана
			local cx, cy = w / 2, h / 2
			local dx, dy = x - cx, y - cy
			local k = math.min((w / 2 - m) / math.max(math.abs(dx), 1), (h / 2 - m) / math.max(math.abs(dy), 1))
			x, y = cx + dx * k, cy + dy * k
			local ang = math.atan2(dy, dx)
			UI.Circle(x, y, UI.S(20), Color(10, 12, 20, 220))
			UI.Ring(x, y, UI.S(20), wp.color)
			UI.DrawIcon(wp.icon, x, y, UI.S(20), wp.color)
			local ax, ay = x + math.cos(ang) * UI.S(30), y + math.sin(ang) * UI.S(30)
			draw.NoTexture()
			surface.SetDrawColor(wp.color)
			surface.DrawPoly({
				{ x = ax + math.cos(ang) * UI.S(8), y = ay + math.sin(ang) * UI.S(8) },
				{ x = ax + math.cos(ang + 2.4) * UI.S(7), y = ay + math.sin(ang + 2.4) * UI.S(7) },
				{ x = ax + math.cos(ang - 2.4) * UI.S(7), y = ay + math.sin(ang - 2.4) * UI.S(7) },
			})
			draw.SimpleText(dist .. " м", NYRP.Font("bold", 12), x, y + UI.S(30), color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		else
			UI.Glow(x, y, UI.S(70), UI.S(70), Color(wp.color.r, wp.color.g, wp.color.b, 60))
			UI.Circle(x, y, UI.S(22) * pulse, Color(10, 12, 20, 225))
			UI.Ring(x, y, UI.S(22) * pulse, wp.color)
			UI.DrawIcon(wp.icon, x, y, UI.S(22), wp.color)
			draw.SimpleTextOutlined(wp.label, NYRP.Font("bold", 15), x, y - UI.S(36), color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 200))
			draw.SimpleTextOutlined(dist .. " м", NYRP.Font("semibold", 13), x, y + UI.S(34), wp.color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 200))
		end
		surface.SetAlphaMultiplier(1)
	end
end)
