--[[
	Приложение «NY Homes»: помещения, которые сдаются (/doorownable), аренда с банковской карты,
	мои аренды — запереть/открыть дверь удалённо, отказаться от аренды.
]]

local UI = NYRP.UI
local P = NYRP.Phone
local C = P.Col
local function S(x) return UI.S(x) end

P.Homes = P.Homes or {}
net.Receive("nyrp.door.list", function() P.Homes = net.ReadTable() P.HomesT = RealTime() end)

local function request()
	net.Start("nyrp.door.list")
	net.SendToServer()
end

P.Register("homes", {
	enter = function(st) request() st.tab = 1 end,
	draw = function(st, x, y, w, h)
		local cy = P.Header("NY Homes", x, y, w, Color(90, 200, 140))
		-- вкладки
		local tw = (w - S(24)) / 2
		for i, t in ipairs({ "Сдаются", "Мои аренды" }) do
			local bx = x + S(12) + (i - 1) * tw
			local f = P.Btn("ht." .. i, bx, cy, tw, S(34), function() st.tab = i st.scroll = 0 end)
			UI.RoundedRect(S(10), bx + S(2), cy, tw - S(4), S(34), st.tab == i and Color(255, 255, 255, 34) or Color(255, 255, 255, 10))
			if f then UI.Outline(S(10), bx + S(2), cy, tw - S(4), S(34), C.yellow, S(2)) end
			P.Text(t, "semibold", 12, bx + tw / 2, cy + S(17), st.tab == i and color_white or C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		cy = cy + S(44)
		local list = {}
		for _, d in ipairs(P.Homes or {}) do
			if (st.tab == 1 and not d.rented) or (st.tab == 2 and d.mine) then list[#list + 1] = d end
		end
		if #list == 0 then
			P.Icon("home", x + w / 2, cy + S(80), S(48), C.faint)
			P.Text(st.tab == 1 and "Свободных помещений нет" or "У вас нет арендованных помещений", "medium", 13, x + w / 2, cy + S(126), C.faint, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			return
		end
		P.List(st, "row.hm.", #list, x + S(12), cy, w - S(18), y + h - cy - S(16), S(64), function(i, rx, ry, rw, rh, f)
			local d = list[i]
			local sub = NYRP.Money.Format(d.price) .. " / день" .. (d.dist and (" · " .. d.dist .. " м") or "")
			if d.mine then sub = (d.locked and "Заперто" or "Открыто") .. " · " .. sub end
			P.Row(rx, ry, rw, rh, f, d.mine and (d.locked and "lock" or "unlock") or "home", d.name, sub, nil, d.mine and C.yellow or Color(90, 200, 140))
		end, function(i)
			P.Push("homeitem", { d = list[i], from = "row.hm." .. i })
		end)
	end,
})

P.Register("homeitem", {
	draw = function(st, x, y, w, h)
		-- свежие данные по этому помещению
		for _, d in ipairs(P.Homes or {}) do if d.id == st.d.id then st.d = d end end
		local d = st.d
		local cy = P.Header(d.name, x, y, w, Color(90, 200, 140))
		UI.RoundedRect(S(16), x + S(14), cy, w - S(28), S(120), Color(90, 200, 140, 40))
		P.Icon("home", x + S(50), cy + S(60), S(40), color_white)
		P.Text(NYRP.Money.Format(d.price), "title", 30, x + S(86), cy + S(30), color_white)
		P.Text("в день · списывается в полночь", "medium", 11, x + S(88), cy + S(70), C.dim)
		if d.dist then P.Text(d.dist .. " м от вас", "medium", 11, x + S(88), cy + S(88), C.dim) end
		cy = cy + S(136)
		local bw = w - S(40)
		if d.mine then
			P.Pill("hm.lock", x + S(20), cy, bw, S(46), d.locked and "Открыть дверь" or "Запереть дверь", function()
				net.Start("nyrp.door.act") net.WriteString(d.id) net.WriteString(d.locked and "unlock" or "lock") net.SendToServer()
			end, { solid = true, color = C.yellow, icon = d.locked and "unlock" or "lock" })
			P.Pill("hm.mark", x + S(20), cy + S(56), bw, S(40), "Показать на карте", function()
				net.Start("nyrp.door.act") net.WriteString(d.id) net.WriteString("mark") net.SendToServer()
				P.Toast("Метка поставлена")
			end, { icon = "map_pin" })
			cy = cy + S(50)
			P.Pill("hm.end", x + S(20), cy + S(56), bw, S(46), "Отказаться от аренды", function()
				net.Start("nyrp.door.act") net.WriteString(d.id) net.WriteString("end") net.SendToServer()
				P.Back()
			end, { icon = "trash", textColor = C.red, iconColor = C.red })
			local bank = NYRP.Bank.Banks[d.bank or ""]
			if bank then P.Text("Оплата с карты " .. bank.name, "medium", 12, x + w / 2, cy + S(124), C.dim, TEXT_ALIGN_CENTER) end
		elseif not d.rented then
			P.Text("Оплата — с вашей банковской карты.", "regular", 12, x + S(20), cy, C.dim)
			P.Text("Первый день — сразу, дальше каждую полночь.", "regular", 12, x + S(20), cy + S(18), C.dim)
			P.Text("Не хватит денег — аренда прекратится.", "regular", 12, x + S(20), cy + S(36), C.dim)
			P.Pill("hm.rent", x + S(20), cy + S(70), bw, S(48), "Арендовать за " .. NYRP.Money.Format(d.price), function()
				net.Start("nyrp.door.rent") net.WriteString(d.id) net.SendToServer()
			end, { solid = true, color = Color(90, 200, 140), icon = "p_card" })
		else
			P.Text("Помещение уже арендовано", "semibold", 14, x + w / 2, cy + S(30), C.red, TEXT_ALIGN_CENTER)
		end
	end,
})
