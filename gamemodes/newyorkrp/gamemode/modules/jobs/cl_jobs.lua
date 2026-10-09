--[[
	Центр занятости: карточки профессий (иконка, оплата, требования, сколько людей работает),
	«Устроиться» / «Начать смену» / «Уволиться». Во время смены — панель задания слева сверху.
]]

local UI = NYRP.UI
local J = NYRP.Jobs
local GOLD = Color(247, 198, 0)

local TYPE_TEXT = {
	deliver = "доставка по адресам", taxi = "перевозка пассажиров", collect = "сбор по району", repair = "ремонт по вызову",
	carry = "погрузка ящиков", report = "выезды на события", rob = "криминал",
}

local function payText(j)
	if j.Type == "rob" then return "добыча " .. NYRP.Money.Format(j.Reward and j.Reward[1] or 0) .. "–" .. NYRP.Money.Format(j.Reward and j.Reward[2] or 0) end
	local s = NYRP.Money.Format(j.Pay or 0) .. (j.Count and " за штуку" or " за задание")
	if (j.PayPerMeter or 0) > 0 then s = s .. " + " .. NYRP.Money.Format(math.floor(j.PayPerMeter * 100)) .. " за 100 м" end
	return s
end

net.Receive("nyrp.jobs", function()
	local list, earned, tasks = net.ReadTable(), net.ReadUInt(32), net.ReadUInt(16)
	if IsValid(J.Win) then J.Win:Remove() end
	local win, body = UI.Window("Центр занятости", "briefcase", 1040, 680, { sub = "заработано всего " .. NYRP.Money.Format(earned) .. " · заданий " .. tasks })
	J.Win = win
	local mine = LocalPlayer():GetNW2String("nyrp.job", "")
	local onShift = LocalPlayer():GetNW2Bool("nyrp.onShift")
	-- текущая работа
	if mine ~= "" and J.List[mine] then
		local j = J.List[mine]
		local cur = vgui.Create("DPanel", body)
		cur:Dock(TOP)
		cur:SetTall(UI.S(64))
		cur:DockMargin(0, 0, 0, UI.S(12))
		cur.Paint = function(_, w, h)
			UI.RoundedRect(UI.S(12), 0, 0, w, h, Color(j.Color.r, j.Color.g, j.Color.b, 28))
			UI.DrawIcon(j.Icon, UI.S(34), h / 2, UI.S(28), j.Color)
			draw.SimpleText("Ваша работа: " .. j.Name, NYRP.Font("title", 22), UI.S(64), UI.S(10), color_white)
			draw.SimpleText(onShift and "Смена идёт · закончить — кнопка справа или /shift" or "Смена не начата", NYRP.Font("medium", 13), UI.S(64), UI.S(38), UI.Col.dim)
		end
		local q = UI.AddButton(cur, "Уволиться", "logout", function()
			net.Start("nyrp.jobs.act") net.WriteString("quit") net.WriteString(mine) net.SendToServer()
		end, { dock = RIGHT, accent = UI.Col.red })
		q:SetWide(UI.S(150)) q:DockMargin(UI.S(8), UI.S(12), UI.S(12), UI.S(12))
		local s = UI.AddButton(cur, onShift and "Закончить смену" or "Начать смену", onShift and "p_stop" or "play", function()
			net.Start("nyrp.jobs.act") net.WriteString("shift") net.WriteString(mine) net.SendToServer()
			win:Close()
		end, { dock = RIGHT, style = "solid", accent = j.Color })
		s:SetWide(UI.S(190)) s:DockMargin(0, UI.S(12), 0, UI.S(12))
	end
	local scroll = vgui.Create("DScrollPanel", body)
	scroll:Dock(FILL)
	local grid = vgui.Create("DIconLayout", scroll)
	grid:Dock(TOP)
	grid:SetSpaceX(UI.S(12))
	grid:SetSpaceY(UI.S(12))
	local cols = 3
	local cw = math.floor((UI.S(1040) - UI.S(44) - UI.S(16) - (cols - 1) * UI.S(12)) / cols)
	for i, e in ipairs(list) do
		local j = J.List[e.id]
		if j then
			local card = grid:Add("DPanel")
			card:SetSize(cw, UI.S(250))
			card.Born = RealTime() + i * 0.03
			card.Paint = function(s, w, h)
				s:SetAlpha(255 * math.Clamp((RealTime() - s.Born) / 0.25, 0, 1))
				UI.RoundedRect(UI.S(12), 0, 0, w, h, j.Criminal and Color(60, 14, 18, 200) or Color(255, 255, 255, 10))
				if mine == e.id then UI.Outline(UI.S(12), 0, 0, w, h, j.Color, 2) end
				UI.Circle(UI.S(36), UI.S(36), UI.S(22), Color(j.Color.r, j.Color.g, j.Color.b, 40))
				UI.DrawIcon(j.Icon, UI.S(36), UI.S(36), UI.S(24), j.Color)
				draw.SimpleText(j.Name, NYRP.Font("bold", 18), UI.S(68), UI.S(16), color_white)
				draw.SimpleText(TYPE_TEXT[j.Type] or "", NYRP.Font("medium", 12), UI.S(68), UI.S(40), j.Criminal and Color(240, 120, 110) or UI.Col.dim)
				local y = UI.S(70)
				for k, l in ipairs(UI.Wrap(j.Description or "", NYRP.Font("regular", 12), w - UI.S(28))) do
					if k > 5 then break end
					draw.SimpleText(l, NYRP.Font("regular", 12), UI.S(14), y, Color(205, 207, 215))
					y = y + UI.S(16)
				end
				draw.SimpleText(payText(j), NYRP.Font("semibold", 13), UI.S(14), h - UI.S(78), GOLD)
				draw.SimpleText((e.workers or 0) .. " работают" .. ((e.problems and #e.problems > 0) and ("  ·  " .. e.problems[1]) or ""),
					NYRP.Font("medium", 12), UI.S(14), h - UI.S(58), (e.problems and #e.problems > 0) and Color(230, 120, 100) or UI.Col.dim)
			end
			if mine ~= e.id then
				local ok = not e.problems or #e.problems == 0
				local b = UI.AddButton(card, "Устроиться", "briefcase", function()
					if not ok then UI.Sound("error") return end
					net.Start("nyrp.jobs.act") net.WriteString("hire") net.WriteString(e.id) net.SendToServer()
				end, { dock = false, style = ok and "solid" or "ghost", accent = ok and j.Color or nil })
				b:SetSize(cw - UI.S(28), UI.S(34))
				b:SetPos(UI.S(14), UI.S(250) - UI.S(46))
			end
		end
	end
end)

-- ------------------------------------------------------------ панель задания --
J.TaskText, J.TaskIcon, J.Earned = "", "", 0
net.Receive("nyrp.jobs.task", function()
	J.TaskText, J.TaskIcon, J.Earned = net.ReadString(), net.ReadString(), net.ReadUInt(32)
	J.TaskBorn = RealTime()
end)

hook.Add("HUDPaint", "nyrp.jobs", function()
	if NYRP.HUDHidden and NYRP.HUDHidden() then return end
	local ply = LocalPlayer()
	local x, y = UI.S(24), UI.S(24)
	if J.Wanted(ply) then
		local left = math.ceil(ply:GetNW2Float("nyrp.wantedUntil") - CurTime())
		local pulse = 0.6 + 0.4 * math.abs(math.sin(RealTime() * 4))
		UI.RoundedRect(UI.S(10), x, y, UI.S(300), UI.S(40), Color(120, 20, 24, 220 * pulse))
		draw.SimpleText("В РОЗЫСКЕ · " .. string.format("%d:%02d", math.floor(left / 60), left % 60), NYRP.Font("bold", 16), x + UI.S(16), y + UI.S(20), color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		y = y + UI.S(48)
	end
	local j = J.Of(ply)
	if not j or not ply:GetNW2Bool("nyrp.onShift") or J.TaskText == "" then return end
	local w = UI.S(380)
	local lines = UI.Wrap(J.TaskText, NYRP.Font("medium", 14), w - UI.S(70))
	local h = UI.S(46) + #lines * UI.S(19)
	local a = math.min(1, (RealTime() - (J.TaskBorn or 0)) / 0.3)
	surface.SetAlphaMultiplier(a)
	UI.RoundedRect(UI.S(12), x, y, w, h, Color(10, 12, 20, 215))
	UI.RoundedRect(UI.S(3), x, y + UI.S(12), UI.S(4), h - UI.S(24), j.Color)
	UI.DrawIcon(j.Icon, x + UI.S(32), y + UI.S(26), UI.S(24), j.Color)
	draw.SimpleText(j.Name .. "  ·  смена: " .. NYRP.Money.Format(J.Earned), NYRP.Font("bold", 14), x + UI.S(58), y + UI.S(12), j.Color)
	for i, l in ipairs(lines) do draw.SimpleText(l, NYRP.Font("medium", 14), x + UI.S(58), y + UI.S(14) + i * UI.S(19), color_white) end
	surface.SetAlphaMultiplier(1)
end)
