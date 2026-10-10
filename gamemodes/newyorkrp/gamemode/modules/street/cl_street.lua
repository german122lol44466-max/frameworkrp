local S = NYRP.Street
local UI = NYRP.UI

net.Receive("nyrp.street", function()
	local kind, data = net.ReadString(), net.ReadTable()
	if kind == "news" then
		local win, body = UI.Window("New York Daily News", "j_reporter", 640, 560, { sub = os.date("%d.%m") })
		local p = vgui.Create("DPanel", body)
		p:Dock(FILL)
		p.Paint = function(_, w, h)
			UI.RoundedRect(UI.S(6), 0, 0, w, h, Color(236, 232, 220))
			draw.SimpleText("NEW YORK DAILY NEWS", NYRP.Font("title", 30), w / 2, UI.S(14), Color(20, 20, 20), TEXT_ALIGN_CENTER)
			surface.SetDrawColor(20, 20, 20) surface.DrawRect(UI.S(20), UI.S(56), w - UI.S(40), 2)
			local y = UI.S(72)
			for i, t in ipairs(data) do
				local f = NYRP.Font(i == 1 and "bold" or "semibold", i == 1 and 20 or 15)
				for _, l in ipairs(UI.Wrap(t, f, w - UI.S(60))) do
					draw.SimpleText(l, f, UI.S(30), y, Color(25, 25, 30))
					y = y + UI.S(i == 1 and 26 or 20)
				end
				y = y + UI.S(10)
				if y > h - UI.S(30) then break end
			end
		end
	elseif kind == "food" then
		local ent = LocalPlayer():GetEyeTrace().Entity
		local win, body = UI.Window("Хот-доги «Joe's»", "food", 420, 120 + #data * 56, { sub = "наличные" })
		for _, f in ipairs(data) do
			local def = NYRP.Items.Get(f.id)
			if def then
				UI.AddButton(body, def.name .. " — " .. NYRP.Money.Format(f.price), "food", function()
					net.Start("nyrp.street.buy") net.WriteEntity(ent) net.WriteString(f.id) net.SendToServer()
				end, { h = 46 })
			end
		end
	elseif kind == "payphone" then
		if NYRP.E911 and NYRP.E911.OpenWindow then NYRP.E911.OpenWindow("Таксофон · 911") end
	end
end)
