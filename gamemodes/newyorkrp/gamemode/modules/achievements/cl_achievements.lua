--[[
	Достижения на клиенте: всплывающее уведомление (иконка, название, награда, звук), окно «Достижения»
	(/achievements) и подкатегория «Достижения» в меню памяти (H → «Воспоминания»).
]]

NYRP.Ach = NYRP.Ach or {}
local A = NYRP.Ach
local UI = NYRP.UI

local GOLD = Color(247, 198, 0)
local INK = Color(230, 228, 240)
local DIM = Color(160, 158, 180)

A.Done = A.Done or {}
A.Prog = A.Prog or {}

net.Receive("nyrp.ach.data", function()
	A.Done = net.ReadTable()
	A.Prog = net.ReadTable()
	local open = net.ReadBool()
	if A.OnChange then A.OnChange() end
	if open then A.OpenWindow() end
end)

function A.Request(open)
	net.Start("nyrp.ach.req")
	net.WriteBool(open and true or false)
	net.SendToServer()
end

-- ---------------------------------------------------------- уведомление --
local toasts = {}
net.Receive("nyrp.ach.unlock", function()
	local id = net.ReadString()
	local a = A.ById[id]
	if not a then return end
	A.Done[id] = os.time()
	toasts[#toasts + 1] = { a = a, born = RealTime() }
	surface.PlaySound("nyrp/phone/game_record.wav")
	timer.Simple(0.35, function() surface.PlaySound("nyrp/fx/cash.wav") end)
	if A.OnChange then A.OnChange() end
end)

hook.Add("HUDPaint", "nyrp.ach.toast", function()
	local t0 = toasts[1]
	if not t0 then return end
	local t = RealTime() - t0.born
	local life = 6
	if t > life then table.remove(toasts, 1) if toasts[1] then toasts[1].born = RealTime() end return end
	local a = t0.a
	local inT = UI.Ease(math.Clamp(t / 0.4, 0, 1))
	local outT = math.Clamp((life - t) / 0.4, 0, 1)
	local w, h = UI.S(420), UI.S(86)
	local x = ScrW() / 2 - w / 2
	local y = UI.S(70) - (1 - inT) * UI.S(40)
	surface.SetAlphaMultiplier(inT * outT)
	UI.BlurRect(x, y, w, h, 4)
	UI.RoundedRect(UI.S(14), x, y, w, h, Color(14, 12, 26, 236))
	UI.Outline(UI.S(14), x, y, w, h, UI.Alpha(GOLD, 120), 1)
	-- блик пробегает по карточке
	local sweep = (t * 0.8) % 1.6
	if sweep < 1 then UI.Glow(x + w * sweep, y + h / 2, UI.S(120), h * 1.4, Color(255, 230, 140, 26)) end
	local pulse = (math.sin(RealTime() * 5) + 1) / 2
	UI.Glow(x + UI.S(44), y + h / 2, UI.S(110), UI.S(110), Color(247, 198, 0, 50 + 40 * pulse))
	UI.Circle(x + UI.S(44), y + h / 2, UI.S(28), UI.Alpha(GOLD, 40))
	UI.Ring(x + UI.S(44), y + h / 2, UI.S(28) + pulse * UI.S(2), UI.Alpha(GOLD, 160))
	UI.DrawIcon(a.icon, x + UI.S(44), y + h / 2, UI.S(30), GOLD)
	draw.SimpleText("ДОСТИЖЕНИЕ ПОЛУЧЕНО", NYRP.Font("bold", 12), x + UI.S(86), y + UI.S(20), GOLD, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	draw.SimpleText(a.name, NYRP.Font("title", 24), x + UI.S(86), y + UI.S(44), color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	draw.SimpleText(a.desc .. (a.reward > 0 and ("  ·  +" .. NYRP.Money.Format(a.reward)) or ""), NYRP.Font("regular", 13), x + UI.S(86), y + UI.S(67), DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	surface.SetAlphaMultiplier(1)
end)

-- ----------------------------------------------------------- список --
local function doneCount()
	local n = 0
	for _ in pairs(A.Done) do n = n + 1 end
	return n
end

-- Заполнить панель списком достижений (используется и в окне, и в меню памяти)
function A.BuildList(parent, dark)
	local head = vgui.Create("DPanel", parent)
	head:Dock(TOP)
	head:SetTall(UI.S(dark and 70 or 44))
	head.Paint = function(_, w, h)
		local n, all = doneCount(), #A.List
		if dark then
			UI.DrawIcon("certificate", UI.S(22), UI.S(26), UI.S(30), GOLD)
			draw.SimpleText("ДОСТИЖЕНИЯ", NYRP.Font("title", 30), UI.S(52), UI.S(26), INK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText("Получено " .. n .. " из " .. all .. ". За каждое — награда наличными.", NYRP.Font("regular", 14), UI.S(2), UI.S(56), DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		else
			draw.SimpleText("Получено " .. n .. " из " .. all, NYRP.Font("semibold", 16), 0, UI.S(14), INK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			UI.RoundedRect(UI.S(3), 0, UI.S(30), w - UI.S(8), UI.S(6), Color(255, 255, 255, 16))
			UI.RoundedRect(UI.S(3), 0, UI.S(30), (w - UI.S(8)) * n / all, UI.S(6), GOLD)
		end
	end
	local scroll = vgui.Create("NYRP.Scroll", parent)
	scroll:Dock(FILL)
	-- сначала полученные, потом по близости к цели
	local list = {}
	for _, a in ipairs(A.List) do list[#list + 1] = a end
	local function frac(a) return math.min(1, (A.Prog[a.stat] or 0) / a.goal) end
	table.sort(list, function(x, y)
		local dx, dy = A.Done[x.id] and 1 or 0, A.Done[y.id] and 1 or 0
		if dx ~= dy then return dx > dy end
		if frac(x) ~= frac(y) then return frac(x) > frac(y) end
		return x.idx < y.idx
	end)
	for _, a in ipairs(list) do
		local row = scroll:Add("DPanel")
		row:Dock(TOP)
		row:SetTall(UI.S(70))
		row:DockMargin(0, 0, UI.S(8), UI.S(8))
		row.Paint = function(s, w, h)
			local done = A.Done[a.id]
			local f = frac(a)
			UI.RoundedRect(UI.S(12), 0, 0, w, h, Color(255, 255, 255, s:IsHovered() and 20 or 10))
			if done then UI.RoundedRect(UI.S(2), UI.S(8), UI.S(14), UI.S(4), h - UI.S(28), GOLD) end
			UI.Circle(UI.S(44), h / 2, UI.S(22), done and UI.Alpha(GOLD, 40) or Color(255, 255, 255, 10))
			UI.DrawIcon(done and a.icon or (f > 0 and a.icon or "lock"), UI.S(44), h / 2, UI.S(24), done and GOLD or Color(120, 120, 140))
			draw.SimpleText(a.name, NYRP.Font("title", 19), UI.S(78), UI.S(20), done and INK or Color(190, 188, 205), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText(a.desc, NYRP.Font("regular", 13), UI.S(78), UI.S(42), DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			-- награда / дата
			local right = done and ("Получено " .. os.date("%d.%m.%Y", done)) or ("+" .. NYRP.Money.Format(a.reward))
			draw.SimpleText(right, NYRP.Font("semibold", 14), w - UI.S(18), UI.S(20), done and UI.Col.green or GOLD, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
			if not done and a.goal > 1 then
				local bw = UI.S(160)
				local cur = math.min(A.Prog[a.stat] or 0, a.goal)
				UI.RoundedRect(UI.S(3), w - UI.S(18) - bw, UI.S(44), bw, UI.S(6), Color(255, 255, 255, 16))
				UI.RoundedRect(UI.S(3), w - UI.S(18) - bw, UI.S(44), bw * f, UI.S(6), GOLD)
				draw.SimpleText(math.floor(cur) .. " / " .. a.goal, NYRP.Font("medium", 11), w - UI.S(18), UI.S(58), DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
			end
		end
	end
end

function A.OpenWindow()
	if IsValid(A.Win) then A.Win:Close() end
	local win, body = UI.Window("Достижения", "certificate", 760, 640, { sub = "Награды зачисляются наличными" })
	A.Win = win
	A.BuildList(body, false)
end

concommand.Add("nyrp_achievements", function() A.Request(true) end)

-- ------------------------------------------------- вкладка в меню памяти (H) --
-- Меню памяти (modules/recognition) строит подкатегории в f.ShowMain; добавляем свою кнопку следом.
local function injectMemory()
	local M = NYRP.Memory
	if not M or not M.Open or M.nyrpAchWrapped then return end
	M.nyrpAchWrapped = true
	local orig = M.Open
	M.Open = function(...)
		local r = orig(...)
		local f = M.Panel
		if not IsValid(f) or not f.ShowMain then return r end
		local showMain = f.ShowMain
		f.ShowMain = function(...)
			showMain(...)
			local subs = f.Subs
			if not subs or not IsValid(subs[1]) then return end
			local col = subs[1]:GetParent()
			-- правая панель содержимого — ребёнок окна, начинающийся правее колонки
			local content
			for _, ch in ipairs(f:GetChildren()) do
				if ch ~= col and ch:GetClassName() ~= "Label" and ch:GetX() > col:GetX() + col:GetWide() then content = ch end
			end
			if not IsValid(content) then return end
			local last = subs[#subs]
			local b = vgui.Create("DButton", col)
			b:SetText("")
			b:SetPos(last:GetX(), last:GetY() + last:GetTall() + UI.S(8))
			b:SetSize(last:GetWide(), last:GetTall())
			b:SetCursor("hand")
			b.Hover = 0
			local function sel() return f.Cat == "achievements" end
			b.Paint = function(s, w, h)
				s.Hover = UI.Approach(s.Hover, (s:IsHovered() or sel()) and 1 or 0, 10)
				UI.RoundedRect(UI.S(12), 0, 0, w, h, Color(255, 255, 255, 10 + 22 * s.Hover))
				if sel() then UI.RoundedRect(UI.S(2), UI.S(8), UI.S(12), UI.S(4), h - UI.S(24), GOLD) end
				UI.DrawIcon("certificate", UI.S(40), h / 2, UI.S(26), sel() and GOLD or Color(210, 200, 255))
				draw.SimpleText("Достижения", NYRP.Font("title", 20), UI.S(70), h / 2, INK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
			b.OnCursorEntered = function() UI.Sound("hover") end
			b.DoClick = function()
				UI.Sound("click")
				f.Cat = "achievements"
				-- свежий прогресс придёт с сервера — тогда перестроим список
				A.OnChange = function()
					A.OnChange = nil
					if IsValid(content) and IsValid(f) and f.Cat == "achievements" then
						content:Clear()
						A.BuildList(content, true)
					end
				end
				A.Request(false)
				content:Clear()
				content:SetAlpha(0)
				content:AlphaTo(255, 0.25)
				A.BuildList(content, true)
			end
			b:SetAlpha(0)
			b:SetVisible(false)
			if col:GetTall() < b:GetY() + b:GetTall() then col:SetTall(b:GetY() + b:GetTall()) end
			subs[#subs + 1] = b   -- раскрывается/сворачивается вместе с остальными подкатегориями
		end
		return r
	end
end
hook.Add("InitPostEntity", "nyrp.ach.memory", injectMemory)
timer.Simple(0, injectMemory)
