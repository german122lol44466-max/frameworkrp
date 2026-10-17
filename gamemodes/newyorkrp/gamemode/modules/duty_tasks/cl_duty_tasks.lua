--[[
	Занятия для служб на дежурстве — клиент: панель задания слева сверху (под панелью работы),
	меню пострадавшего (EMS), подсветка улик и пострадавших у дежурных,
	вкладка «Задания» служебного компьютера (NYRP.DutyTasks.BuildTab — вызывает cl_factions.lua).
]]
NYRP.DutyTasks = NYRP.DutyTasks or {}
local D = NYRP.DutyTasks
local UI = NYRP.UI
local GOLD = Color(247, 198, 0)

D.Cur = D.Cur or nil

local function send(act)
	net.Start("nyrp.duty.act")
	net.WriteString(act)
	net.SendToServer()
end

net.Receive("nyrp.duty.task", function()
	local kind = net.ReadString()
	local title = net.ReadString()
	local text = net.ReadString()
	local idx = net.ReadUInt(8)
	local total = net.ReadUInt(8)
	if kind == "" then
		D.Cur = nil
		return
	end
	D.Cur = { kind = kind, title = title, text = text, idx = idx, total = total, born = RealTime() }
end)

local function statusIcon(name, x, y, s, col)
	surface.SetMaterial(UI.Mat("nyrp/status/" .. name .. ".png"))
	surface.SetDrawColor(col or color_white)
	surface.DrawTexturedRect(x - s / 2, y - s / 2, s, s)
end

-- под плашкой розыска и панелью работы (modules/jobs/cl_jobs.lua)
local function topY(ply)
	local y = UI.S(24)
	local J = NYRP.Jobs
	if not J then return y end
	if J.Wanted and J.Wanted(ply) then y = y + UI.S(48) end
	local txt = J.TaskText or ""
	if J.Of and J.Of(ply) and ply:GetNW2Bool("nyrp.onShift") and txt ~= "" then
		local lines = UI.Wrap(txt, NYRP.Font("medium", 14), UI.S(380) - UI.S(70))
		y = y + UI.S(46) + #lines * UI.S(19) + UI.S(10)
	end
	return y
end

hook.Add("HUDPaint", "nyrp.dutytasks", function()
	if NYRP.HUDHidden and NYRP.HUDHidden() then return end
	local t = D.Cur
	local ply = LocalPlayer()
	if not t or not IsValid(ply) then return end
	local R = NYRP.Roles and NYRP.Roles.List[ply:GetNW2String("nyrp.role", "")]
	local col = R and R.Color or GOLD
	local x, y, w = UI.S(24), topY(ply), UI.S(380)
	local font = NYRP.Font("medium", 14)
	local lines = UI.Wrap(t.text or "", font, w - UI.S(70))
	local dots = (t.total or 0) > 0
	local h = UI.S(46) + #lines * UI.S(19) + (dots and UI.S(20) or 0) + UI.S(16)
	local a = math.min(1, (RealTime() - (t.born or 0)) / 0.3)
	surface.SetAlphaMultiplier(a)
	UI.RoundedRect(UI.S(12), x, y, w, h, Color(10, 12, 20, 215))
	UI.RoundedRect(UI.S(3), x, y + UI.S(12), UI.S(4), h - UI.S(24), col)
	if R and R.Icon then statusIcon(R.Icon, x + UI.S(32), y + UI.S(26), UI.S(26), col) end
	draw.SimpleText(t.title or "", NYRP.Font("bold", 14), x + UI.S(58), y + UI.S(12), col)
	for i, l in ipairs(lines) do
		draw.SimpleText(l, font, x + UI.S(58), y + UI.S(14) + i * UI.S(19), color_white)
	end
	local yy = y + UI.S(14) + (#lines + 1) * UI.S(19)
	if dots then
		local r = UI.S(5)
		for i = 1, t.total do
			local cx = x + UI.S(58) + r + (i - 1) * UI.S(18)
			local c
			if i < t.idx then
				c = col
			elseif i == t.idx then
				c = UI.Alpha(col, 120 + 100 * math.abs(math.sin(RealTime() * 3)))
			else
				c = Color(255, 255, 255, 30)
			end
			UI.Circle(cx, yy + UI.S(6), r, c)
		end
		yy = yy + UI.S(20)
	end
	draw.SimpleText("/dutycancel — отменить задание", NYRP.Font("regular", 12), x + UI.S(58), yy, UI.Col.dim)
	surface.SetAlphaMultiplier(1)
end)

-- ------------------------------------------------------ меню пострадавшего --
local function patientAct(e, act)
	net.Start("nyrp.duty.patient.act")
	net.WriteEntity(e)
	net.WriteString(act)
	net.SendToServer()
end

net.Receive("nyrp.duty.patient", function()
	local e = net.ReadEntity()
	local diag = net.ReadString()
	local hasBandage = net.ReadBool()
	local hasDefib = net.ReadBool()
	if not IsValid(e) then return end
	local examined = diag ~= ""
	local opts = {}
	if examined then
		opts[#opts + 1] = { text = diag, icon = "info", disabled = true }
		opts[#opts + 1] = { divider = true }
	end
	opts[#opts + 1] = { text = examined and "Осмотреть снова" or "Осмотреть", icon = "eye", func = function() patientAct(e, "examine") end }
	opts[#opts + 1] = { text = hasBandage and "Перевязать" or "Перевязать (нет бинта)", icon = "bandage",
		disabled = not hasBandage or not examined, func = function() patientAct(e, "bandage") end }
	opts[#opts + 1] = { text = hasDefib and "Дефибриллятор" or "Дефибриллятор (в руки)", icon = "heart",
		disabled = not hasDefib or not examined, func = function() patientAct(e, "defib") end }
	UI.Menu(opts, ScrW() / 2 + UI.S(20), ScrH() / 2)
end)

-- ----------------------------------------------------- подсветка у дежурных --
hook.Add("PreDrawHalos", "nyrp.dutytasks", function()
	local ply = LocalPlayer()
	if not IsValid(ply) or not ply:GetNW2Bool("nyrp.onDuty") then return end
	local r = ply:GetNW2String("nyrp.role", "")
	local cls = (r == "police" and "nyrp_evidence") or (r == "medic" and "nyrp_patient") or nil
	if not cls then return end
	local list = {}
	for _, e in ipairs(ents.FindByClass(cls)) do
		if IsValid(e) and e:GetPos():DistToSqr(ply:GetPos()) < 1500 * 1500 then list[#list + 1] = e end
	end
	if #list > 0 then halo.Add(list, r == "police" and Color(80, 140, 230) or Color(230, 90, 90), 2, 2, 1, true, false) end
end)

-- ------------------------------------------- вкладка «Задания» в компьютере --
D.Tab = {
	police = {
		{ id = "patrol", name = "Патрулирование", icon = "shield", pay = "$60 за маршрут",
			text = "Маршрут из 4–6 точек района. Метки по очереди: дошли до точки — отметка засчитана." },
		{ name = "Происшествия", icon = "eye", pay = "$40 за отчёт",
			text = "Раз в 6–10 минут диспетчер передаёт сигнал «Подозрительная активность». На месте — улика: E, 4 секунды — осмотр и отчёт." },
	},
	medic = {
		{ name = "Вызовы к пострадавшим", icon = "medkit", pay = "$70 за вызов",
			text = "Раз в 6–10 минут диспетчер передаёт вызов «Человеку плохо». На месте: E — осмотреть, затем перевязать (бинт) или дефибриллятор в руках. Через 10 минут вызов снимается." },
	},
	fire = {
		{ id = "hydrants", name = "Обход гидрантов", icon = "droplet", pay = "$50 за обход",
			text = "3–5 ближайших гидрантов. Метки по очереди: у гидранта E, 3 секунды — проверено." },
	},
}

function D.BuildTab(canvas, roleId, col, win)
	local list = D.Tab[roleId]
	if not list then return end
	local onDuty = LocalPlayer():GetNW2Bool("nyrp.onDuty")
	-- текущее задание / подсказка про дежурство
	local head = vgui.Create("DPanel", canvas)
	head:Dock(TOP)
	head:SetTall(UI.S(58))
	head:DockMargin(0, 0, 0, UI.S(10))
	head.Paint = function(_, w, h)
		UI.RoundedRect(UI.S(10), 0, 0, w, h, UI.Alpha(col, 22))
		local cur = D.Cur
		local title = cur and ("Текущее задание: " .. (cur.title or "")) or (onDuty and "Задания нет" or "Вы не на дежурстве")
		local sub = cur and (cur.text or "") or (onDuty and "Выберите занятие ниже" or "Заступите на дежурство — кнопка слева внизу")
		draw.SimpleText(title, NYRP.Font("semibold", 15), UI.S(16), UI.S(10), color_white)
		draw.SimpleText(sub, NYRP.Font("regular", 12), UI.S(16), UI.S(33), UI.Col.dim)
	end
	if D.Cur then
		local c = UI.AddButton(head, "Отменить", "close", function() send("cancel") end, { dock = RIGHT, accent = UI.Col.red })
		c:SetWide(UI.S(140))
		c:DockMargin(UI.S(6), UI.S(10), UI.S(10), UI.S(10))
	end
	for _, task in ipairs(list) do
		local p = vgui.Create("DPanel", canvas)
		p:Dock(TOP)
		p:DockMargin(0, 0, 0, UI.S(8))
		local lines = UI.Wrap(task.text, NYRP.Font("regular", 13), UI.S(480))
		p:SetTall(UI.S(48) + #lines * UI.S(17) + UI.S(12))
		p.Paint = function(_, w, h)
			UI.RoundedRect(UI.S(10), 0, 0, w, h, Color(255, 255, 255, 8))
			surface.SetDrawColor(col)
			surface.DrawRect(0, UI.S(8), 3, h - UI.S(16))
			UI.DrawIcon(task.icon, UI.S(30), UI.S(26), UI.S(22), col)
			draw.SimpleText(task.name, NYRP.Font("bold", 16), UI.S(54), UI.S(14), color_white)
			draw.SimpleText(task.pay, NYRP.Font("semibold", 13), UI.S(54) + UI.TextSize(task.name, NYRP.Font("bold", 16)) + UI.S(12), UI.S(17), GOLD)
			for i, l in ipairs(lines) do
				draw.SimpleText(l, NYRP.Font("regular", 13), UI.S(54), UI.S(26) + i * UI.S(17), UI.Col.dim)
			end
		end
		if task.id then
			local b = UI.AddButton(p, "Взять", "play", function()
				send(task.id)
				if IsValid(win) then win:Close() end
			end, { dock = RIGHT, style = "solid", accent = col })
			b:SetWide(UI.S(130))
			b:DockMargin(UI.S(6), UI.S(12), UI.S(10), UI.S(12))
			if D.Cur or not onDuty then b:SetEnabled(false) end
		end
	end
end
