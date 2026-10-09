--[[
	Ратуша: вкладка «Лицензия» — заявление (вид деятельности, название, данные заявителя, пошлина, подпись мышью)
	или уже выданное свидетельство; вкладка «Помещения» — свободные коммерческие помещения, аренда, метка.
]]

local UI = NYRP.UI
local B = NYRP.Business
local GOLD = Color(247, 198, 0)
local PAPER = Color(242, 236, 222)
local INK = Color(30, 34, 52)

local function act(a, b, c)
	net.Start("nyrp.biz.act") net.WriteString(a) net.WriteString(b or "") net.WriteString(c or "") net.SendToServer()
end

net.Receive("nyrp.biz", function()
	local L, prem, bank, balance, name, cid = net.ReadTable(), net.ReadTable(), net.ReadString(), net.ReadDouble(), net.ReadString(), net.ReadUInt(32)
	if IsValid(B.Win) then B.Win:Remove() end
	local win, body = UI.Window("Городская ратуша", "bank", 980, 680, { sub = "отдел лицензирования", keyboard = true })
	B.Win = win
	local tab = B.Tab or (L.number and 2 or 1)
	local tabs = vgui.Create("DPanel", body)
	tabs:Dock(TOP)
	tabs:SetTall(UI.S(40))
	tabs.Paint = function() end
	local page = vgui.Create("DPanel", body)
	page:Dock(FILL)
	page:DockMargin(0, UI.S(12), 0, 0)
	page.Paint = function() end
	local build
	for i, t in ipairs({ { "Лицензия на бизнес", "license" }, { "Коммерческие помещения", "store" } }) do
		local b = UI.AddButton(tabs, t[1], t[2], function() tab = i B.Tab = i build() end, { dock = LEFT, h = 40 })
		b:SetWide(UI.S(260))
		b:DockMargin(0, 0, UI.S(8), 0)
		b.Think = function(s) s:SetStyle(tab == i and "solid" or "ghost") s:SetAccent(GOLD) end
	end

	build = function()
		page:Clear()
		if tab == 1 and L.number then
			-- выданное свидетельство
			local cert = vgui.Create("DPanel", page)
			cert:Dock(FILL)
			cert:DockMargin(UI.S(120), 0, UI.S(120), UI.S(10))
			cert.Paint = function(_, w, h)
				UI.RoundedRect(UI.S(6), 0, 0, w, h, PAPER)
				UI.Outline(UI.S(6), UI.S(10), UI.S(10), w - UI.S(20), h - UI.S(20), Color(150, 120, 60), 2)
				draw.SimpleText("CITY OF NEW YORK", NYRP.Font("bold", 14), w / 2, UI.S(36), Color(120, 90, 40), TEXT_ALIGN_CENTER)
				draw.SimpleText("ЛИЦЕНЗИЯ НА ПРЕДПРИНИМАТЕЛЬСКУЮ ДЕЯТЕЛЬНОСТЬ", NYRP.Font("title", 22), w / 2, UI.S(64), INK, TEXT_ALIGN_CENTER)
				draw.SimpleText("№ " .. L.number, NYRP.Font("bold", 18), w / 2, UI.S(100), Color(150, 40, 40), TEXT_ALIGN_CENTER)
				local t = B.TypeById[L.type] or {}
				local rows = { { "Владелец", L.holder or name }, { "Вид деятельности", t.name or "?" }, { "Название", "«" .. (L.name or "") .. "»" }, { "Дата выдачи", L.issued or "" } }
				for i, r in ipairs(rows) do
					draw.SimpleText(r[1], NYRP.Font("medium", 14), UI.S(60), UI.S(150) + i * UI.S(36), Color(110, 100, 80))
					draw.SimpleText(r[2], NYRP.Font("bold", 18), w - UI.S(60), UI.S(146) + i * UI.S(36), INK, TEXT_ALIGN_RIGHT)
				end
				-- печать
				local sx, sy = w - UI.S(130), h - UI.S(110)
				UI.Ring(sx, sy, UI.S(54), Color(40, 70, 170, 200))
				UI.Ring(sx, sy, UI.S(44), Color(40, 70, 170, 160))
				draw.SimpleText("CITY HALL", NYRP.Font("bold", 13), sx, sy - UI.S(8), Color(40, 70, 170, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				draw.SimpleText("NYC", NYRP.Font("bold", 16), sx, sy + UI.S(12), Color(40, 70, 170, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				draw.SimpleText("Далее: вкладка «Коммерческие помещения» — выберите, где открыться.", NYRP.Font("regular", 13), UI.S(60), h - UI.S(50), Color(110, 100, 80))
			end
			return
		end
		if tab == 1 then
			-- заявление
			local chosen, bizName, agree, sig = nil, "", false, {}
			local left = vgui.Create("DPanel", page)
			left:Dock(LEFT)
			left:SetWide(UI.S(380))
			left.Paint = function(_, w, h) draw.SimpleText("1. Вид деятельности", NYRP.Font("bold", 15), 0, 0, GOLD) end
			local types = vgui.Create("DScrollPanel", left)
			types:Dock(FILL)
			types:DockMargin(0, UI.S(26), UI.S(12), 0)
			for _, t in ipairs(B.Types) do
				local b = types:Add("DButton")
				b:SetText("")
				b:Dock(TOP)
				b:SetTall(UI.S(54))
				b:DockMargin(0, 0, 0, UI.S(6))
				b:SetCursor("hand")
				b.DoClick = function() chosen = t UI.Sound("click") end
				b.Paint = function(s, w, h)
					local sel = chosen == t
					UI.RoundedRect(UI.S(10), 0, 0, w, h, sel and Color(247, 198, 0, 40) or Color(255, 255, 255, s:IsHovered() and 20 or 10))
					if sel then UI.Outline(UI.S(10), 0, 0, w, h, GOLD, 2) end
					UI.DrawIcon(t.icon, UI.S(26), h / 2, UI.S(22), sel and GOLD or color_white)
					draw.SimpleText(t.name, NYRP.Font("semibold", 15), UI.S(50), UI.S(10), color_white)
					draw.SimpleText("пошлина " .. NYRP.Money.Format(t.fee) .. " · выручка ~" .. NYRP.Money.Format(t.income[1]) .. "–" .. NYRP.Money.Format(t.income[2]) .. " / 10 мин",
						NYRP.Font("regular", 11), UI.S(50), UI.S(32), UI.Col.dim)
				end
			end
			-- бланк
			local form = vgui.Create("DPanel", page)
			form:Dock(FILL)
			local entry = vgui.Create("DTextEntry", form)
			entry:SetFont(NYRP.Font("bold", 18))
			entry:SetPlaceholderText("Название бизнеса")
			entry.OnValueChange = function(_, v) bizName = v end
			entry.OnChange = function(s) bizName = s:GetValue() end
			local sigPad = vgui.Create("DPanel", form)
			local drawing = false
			sigPad:SetCursor("crosshair")
			sigPad.OnMousePressed = function() drawing = true sig[#sig + 1] = {} end
			sigPad.OnMouseReleased = function() drawing = false end
			sigPad.Think = function(s)
				if drawing and input.IsMouseDown(MOUSE_LEFT) then
					local mx, my = s:CursorPos()
					local st = sig[#sig]
					local last = st[#st]
					if not last or math.abs(last[1] - mx) + math.abs(last[2] - my) > 2 then st[#st + 1] = { mx, my } end
				elseif drawing then drawing = false end
			end
			sigPad.Paint = function(s, w, h)
				surface.SetDrawColor(INK.r, INK.g, INK.b, 255)
				for _, st in ipairs(sig) do
					for i = 2, #st do
						surface.DrawLine(st[i - 1][1], st[i - 1][2], st[i][1], st[i][2])
						surface.DrawLine(st[i - 1][1], st[i - 1][2] + 1, st[i][1], st[i][2] + 1)
					end
				end
				surface.SetDrawColor(110, 100, 80, 160)
				surface.DrawRect(UI.S(10), h - UI.S(14), w - UI.S(20), 1)
				if #sig == 0 then draw.SimpleText("Распишитесь здесь мышью", NYRP.Font("regular", 13), w / 2, h / 2, Color(150, 140, 120), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
			end
			local agreeBox = vgui.Create("DButton", form)
			agreeBox:SetText("")
			agreeBox:SetCursor("hand")
			agreeBox.DoClick = function() agree = not agree UI.Sound("toggle") end
			agreeBox.Paint = function(_, w, h)
				UI.RoundedRect(UI.S(4), 0, h / 2 - UI.S(9), UI.S(18), UI.S(18), Color(255, 255, 255, 220))
				if agree then UI.RoundedRect(UI.S(2), UI.S(4), h / 2 - UI.S(5), UI.S(10), UI.S(10), INK) end
				draw.SimpleText("Подтверждаю достоверность сведений и согласен с уплатой пошлины", NYRP.Font("medium", 12), UI.S(26), h / 2, INK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
			local submit = UI.AddButton(form, "Подать заявление и оплатить", "sign", function()
				if not chosen then NYRP.Notify("Выберите вид деятельности", "warning") return end
				if utf8.len(string.Trim(bizName)) < 2 then NYRP.Notify("Впишите название бизнеса", "warning") entry:RequestFocus() return end
				if bank == "" then NYRP.Notify("Нужна банковская карта для оплаты пошлины", "error") return end
				if not agree then NYRP.Notify("Поставьте отметку о достоверности сведений", "warning") return end
				if #sig == 0 or #sig[1] < 6 then NYRP.Notify("Распишитесь на бланке", "warning") return end
				act("license", chosen.id, string.Trim(bizName))
			end, { dock = false, style = "solid", accent = GOLD })
			form.PerformLayout = function(s, w, h)
				entry:SetPos(UI.S(40), UI.S(190)) entry:SetSize(w - UI.S(80), UI.S(36))
				sigPad:SetPos(w - UI.S(300), h - UI.S(200)) sigPad:SetSize(UI.S(260), UI.S(80))
				agreeBox:SetPos(UI.S(40), h - UI.S(110)) agreeBox:SetSize(w - UI.S(80), UI.S(24))
				submit:SetPos(UI.S(40), h - UI.S(70)) submit:SetSize(w - UI.S(80), UI.S(44))
			end
			form.Paint = function(_, w, h)
				UI.RoundedRect(UI.S(6), 0, 0, w, h - UI.S(80), PAPER)
				draw.SimpleText("ЗАЯВЛЕНИЕ НА ВЫДАЧУ ЛИЦЕНЗИИ", NYRP.Font("title", 20), w / 2, UI.S(22), INK, TEXT_ALIGN_CENTER)
				draw.SimpleText("Department of Consumer Affairs · City of New York", NYRP.Font("regular", 12), w / 2, UI.S(50), Color(110, 100, 80), TEXT_ALIGN_CENTER)
				local rows = {
					{ "Заявитель", name },
					{ "Номер в реестре жителей", tostring(cid) },
					{ "Вид деятельности", chosen and chosen.name or "— выберите слева —" },
				}
				for i, r in ipairs(rows) do
					draw.SimpleText(r[1], NYRP.Font("medium", 13), UI.S(40), UI.S(68) + i * UI.S(28), Color(110, 100, 80))
					draw.SimpleText(r[2], NYRP.Font("bold", 15), w - UI.S(40), UI.S(66) + i * UI.S(28), INK, TEXT_ALIGN_RIGHT)
				end
				draw.SimpleText("Название бизнеса", NYRP.Font("medium", 13), UI.S(40), UI.S(172), Color(110, 100, 80))
				local fee = chosen and chosen.fee or 0
				local bk = NYRP.Bank.Banks[bank]
				draw.SimpleText("Госпошлина", NYRP.Font("medium", 13), UI.S(40), UI.S(244), Color(110, 100, 80))
				draw.SimpleText(NYRP.Money.Format(fee), NYRP.Font("bold", 18), w - UI.S(40), UI.S(240), Color(150, 40, 40), TEXT_ALIGN_RIGHT)
				draw.SimpleText(bk and ("Оплата с карты " .. bk.name .. " · на счёте " .. NYRP.Money.Format(balance)) or "Нет банковской карты", NYRP.Font("medium", 12), UI.S(40), UI.S(270),
					(bk and balance >= fee) and Color(60, 120, 60) or Color(170, 60, 50))
				draw.SimpleText("Подпись заявителя:", NYRP.Font("medium", 13), UI.S(40), h - UI.S(190), Color(110, 100, 80))
			end
			return
		end
		-- помещения
		if not L.number then
			local n = vgui.Create("DPanel", page)
			n:Dock(TOP)
			n:SetTall(UI.S(40))
			n.Paint = function(_, w, h) draw.SimpleText("Арендовать помещение можно только с лицензией (вкладка «Лицензия на бизнес»).", NYRP.Font("medium", 14), 0, h / 2, Color(230, 150, 90), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
		end
		local scroll = vgui.Create("DScrollPanel", page)
		scroll:Dock(FILL)
		if #prem == 0 then
			local e = scroll:Add("DPanel") e:Dock(TOP) e:SetTall(UI.S(60))
			e.Paint = function(_, w, h) draw.SimpleText("Коммерческих помещений пока нет (админ: /doorbusiness <цена> [название]).", NYRP.Font("medium", 14), 0, h / 2, UI.Col.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
		end
		for _, p in ipairs(prem) do
			local row = scroll:Add("DPanel")
			row:Dock(TOP)
			row:SetTall(UI.S(64))
			row:DockMargin(0, 0, UI.S(8), UI.S(8))
			row.Paint = function(_, w, h)
				UI.RoundedRect(UI.S(10), 0, 0, w, h, p.mine and Color(240, 160, 60, 30) or Color(255, 255, 255, 10))
				UI.DrawIcon("store", UI.S(30), h / 2, UI.S(24), p.taken and UI.Col.dim or Color(240, 160, 60))
				draw.SimpleText(p.mine and ("«" .. (p.bizName or p.name) .. "» — ваш бизнес") or p.name, NYRP.Font("bold", 16), UI.S(58), UI.S(12), color_white)
				draw.SimpleText(NYRP.Money.Format(p.price) .. " в день" .. (p.dist and (" · " .. p.dist .. " м") or "") .. (p.taken and not p.mine and " · занято" or ""),
					NYRP.Font("medium", 12), UI.S(58), UI.S(38), UI.Col.dim)
			end
			local m = UI.AddButton(row, "На карте", "map_pin", function() act("mark", p.id) end, { dock = RIGHT })
			m:SetWide(UI.S(130)) m:DockMargin(UI.S(6), UI.S(12), UI.S(12), UI.S(12))
			if not p.taken then
				local r = UI.AddButton(row, "Арендовать", "sign", function() act("rent", p.id) end, { dock = RIGHT, style = "solid", accent = Color(240, 160, 60) })
				r:SetWide(UI.S(150)) r:DockMargin(0, UI.S(12), 0, UI.S(12))
			end
		end
	end
	build()
end)
