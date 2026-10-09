--[[
	Меню памяти (H). Мозг в центре внимания, «Думаю…» две секунды — мысли собираются, затем «Воспоминания»:
	  Знакомства — кого персонаж помнит: лицо, имя, описание, когда виделись;
	  Мысли      — задания от NPC: что сейчас на уме (активные) и что уже сделано.
	Задание «дойти до места» можно отметить — тогда на экране появится метка цели.
	H / Esc / ПКМ — закрыть.
]]

local UI = NYRP.UI
local M = {}
NYRP.Memory = M

local GOLD = Color(247, 198, 0)
local INK = Color(230, 228, 240)
local DIM = Color(160, 158, 180)
local VIOLET = Color(150, 120, 255)

M.People, M.Done, M.Now = {}, {}, os.time()
net.Receive("nyrp.memory", function()
	M.People = net.ReadTable()
	M.Done = net.ReadTable()
	M.Now = net.ReadDouble()
	M.Got = RealTime()
	if IsValid(M.Panel) and M.Panel.Rebuild then M.Panel.Rebuild() end
end)

local function ago(ts)
	local d = math.max(0, (M.Now or os.time()) - (ts or 0))
	if d < 3600 then return "виделись недавно" end
	if d < 86400 then return "виделись " .. math.floor(d / 3600) .. " ч назад" end
	local days = math.floor(d / 86400)
	return "виделись " .. days .. " дн. назад"
end

local function icon(name, x, y, s, col)
	surface.SetMaterial(UI.Mat("nyrp/status/" .. name .. ".png"))
	surface.SetDrawColor(col or color_white)
	surface.DrawTexturedRect(x - s / 2, y - s / 2, s, s)
end

-- «пылинки» мыслей на фоне
local motes = {}
for i = 1, 60 do motes[i] = { x = math.Rand(0, 1), y = math.Rand(0, 1), s = math.Rand(1, 3), v = math.Rand(0.005, 0.02), p = math.Rand(0, 6) } end

function M.Close()
	if IsValid(M.Panel) then
		local p = M.Panel
		p.Closing = RealTime()
		p:SetMouseInputEnabled(false)
		p:SetKeyboardInputEnabled(false)
		timer.Simple(0.25, function() if IsValid(p) then p:Remove() end end)
		UI.Sound("close")
	end
end

function M.Open()
	if IsValid(M.Panel) then M.Close() return end
	net.Start("nyrp.memory")
	net.SendToServer()
	local f = vgui.Create("EditablePanel")
	M.Panel = f
	f:SetSize(ScrW(), ScrH())
	f:MakePopup()
	f:SetKeyboardInputEnabled(false)
	f.Born = RealTime()
	f.Stage = "think"      -- think → ready → open
	f.Cat = nil
	UI.Sound("open")

	local W, H = ScrW(), ScrH()
	local leftW = UI.S(420)
	f.Paint = function(s, w, h)
		local t = RealTime() - s.Born
		local a = s.Closing and math.max(0, 1 - (RealTime() - s.Closing) / 0.25) or math.min(1, t / 0.35)
		s:SetAlpha(255 * a)
		UI.BlurPanel(s, 6)
		surface.SetDrawColor(6, 5, 14, 225)
		surface.DrawRect(0, 0, w, h)
		-- фиолетовое свечение «мысли» слева
		UI.Glow(leftW * 0.5, h * 0.42, leftW * 1.8, h * 0.9, Color(110, 80, 220, 26))
		UI.Vignette(-UI.S(40), -UI.S(40), w + UI.S(80), h + UI.S(80), 200)
		for _, m in ipairs(motes) do
			local y = (m.y - RealTime() * m.v) % 1
			local al = 40 + 40 * math.sin(RealTime() + m.p)
			surface.SetDrawColor(190, 170, 255, al)
			surface.DrawRect(m.x * w, y * h, m.s, m.s)
		end
		-- мозг
		local cx, cy = leftW * 0.5, h * 0.28
		local pulse = 0.5 + math.sin(RealTime() * 2.2) * 0.5
		UI.Glow(cx, cy, UI.S(320), UI.S(320), Color(140, 110, 255, 40 + pulse * 30))
		UI.Ring(cx, cy, UI.S(84) + pulse * UI.S(4), Color(170, 150, 255, 60))
		if s.Stage == "think" then
			-- бегущая дуга «думаю»
			local p = math.Clamp(t / 2, 0, 1)
			for i = 0, 40 do
				local a1 = math.rad(-90 + 360 * p * i / 40)
				surface.SetDrawColor(GOLD.r, GOLD.g, GOLD.b, 220)
				local r = UI.S(96)
				surface.DrawRect(cx + math.cos(a1) * r - 2, cy + math.sin(a1) * r - 2, 4, 4)
			end
		end
		icon("mem_brain", cx, cy, UI.S(120) * (1 + pulse * 0.03), Color(225, 215, 255))
		if s.Stage == "think" then
			local dots = string.rep(".", math.floor(t * 3) % 4)
			draw.SimpleText("Думаю" .. dots, NYRP.Font("titlelight", 34), cx - UI.S(54), cy + UI.S(130), INK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText("мысли собираются в голове", NYRP.Font("regular", 15), cx, cy + UI.S(168), DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			if t >= 2 then
				s.Stage = "ready"
				s.ReadyT = RealTime()
				UI.Sound("expand")
				s.ShowMain()
			end
		else
			draw.SimpleText("Голова ясная", NYRP.Font("titlelight", 30), cx, cy + UI.S(130), INK, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			draw.SimpleText(NYRP.CharName and NYRP.CharName(LocalPlayer()) or "", NYRP.Font("medium", 15), cx, cy + UI.S(164), DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		-- подсказка
		draw.SimpleText("H, Esc или ПКМ — закрыть", NYRP.Font("regular", 13), cx, h - UI.S(36), Color(255, 255, 255, 80), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		-- разделитель
		surface.SetDrawColor(255, 255, 255, 14)
		surface.DrawRect(leftW, UI.S(70), 1, h - UI.S(140))
	end
	f.OnMousePressed = function(s, code) if code == MOUSE_RIGHT then M.Close() end end
	f.Think = function(s)
		if input.IsKeyDown(KEY_ESCAPE) then
			M.Close()
			if gui.IsGameUIVisible() then gui.HideGameUI() end
		end
	end

	-- левая колонка: «Воспоминания» и подкатегории
	local col = vgui.Create("DPanel", f)
	col:SetPos(UI.S(40), H * 0.28 + UI.S(210))
	col:SetSize(leftW - UI.S(80), UI.S(380))
	col.Paint = nil
	col:SetAlpha(0)

	local content = vgui.Create("DPanel", f)
	content:SetPos(leftW + UI.S(50), UI.S(70))
	content:SetSize(W - leftW - UI.S(100), H - UI.S(140))
	content.Paint = nil

	local function catButton(parent, y, h, title, sub, ic, sel, fn, indent)
		local b = vgui.Create("DButton", parent)
		b:SetText("")
		b:SetPos(indent or 0, y)
		b:SetSize(parent:GetWide() - (indent or 0), h)
		b:SetCursor("hand")
		b.Hover = 0
		b.Paint = function(s, w, hh)
			s.Hover = UI.Approach(s.Hover, (s:IsHovered() or sel()) and 1 or 0, 10)
			UI.RoundedRect(UI.S(12), 0, 0, w, hh, Color(255, 255, 255, 10 + 22 * s.Hover))
			if sel() then
				UI.RoundedRect(UI.S(2), UI.S(8), UI.S(12), UI.S(4), hh - UI.S(24), GOLD)
			end
			icon(ic, UI.S(40), hh / 2, UI.S(30), sel() and GOLD or Color(210, 200, 255))
			draw.SimpleText(title, NYRP.Font("title", indent and 20 or 24), UI.S(70), hh / 2 - (sub and UI.S(9) or 0), INK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			if sub then draw.SimpleText(sub, NYRP.Font("regular", 13), UI.S(70), hh / 2 + UI.S(13), DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
		end
		b.OnCursorEntered = function() UI.Sound("hover") end
		b.DoClick = function() UI.Sound("click") fn() end
		return b
	end

	local function buildContent() end

	f.ShowMain = function()
		col:AlphaTo(255, 0.35)
		f.MemOpen = false
		local subs = {}
		catButton(col, 0, UI.S(70), "Воспоминания", "что осталось в памяти", "mem_memories", function() return f.MemOpen end, function()
			f.MemOpen = not f.MemOpen
			for _, s in ipairs(subs) do
				s:SetVisible(true)
				s:AlphaTo(f.MemOpen and 255 or 0, 0.2, 0, function() if not f.MemOpen then s:SetVisible(false) end end)
			end
			if f.MemOpen and not f.Cat then f.Cat = "people" buildContent() end
		end)
		subs[1] = catButton(col, UI.S(82), UI.S(58), "Знакомства", nil, "mem_people", function() return f.Cat == "people" end,
			function() f.Cat = "people" buildContent() end, UI.S(26))
		subs[2] = catButton(col, UI.S(148), UI.S(58), "Мысли", nil, "mem_thought", function() return f.Cat == "thoughts" end,
			function() f.Cat = "thoughts" buildContent() end, UI.S(26))
		subs[3] = catButton(col, UI.S(214), UI.S(58), "Навыки", nil, "skills", function() return f.Cat == "skills" end,
			function() f.Cat = "skills" if NYRP.Skills.Request then NYRP.Skills.Request() end buildContent() end, UI.S(26))
		for _, s in ipairs(subs) do s:SetAlpha(0) s:SetVisible(false) end
		f.Subs = subs
	end

	-- правая часть
	buildContent = function()
		content:Clear()
		content:SetAlpha(0)
		content:AlphaTo(255, 0.25)
		local cw = content:GetWide()
		if f.Cat == "skills" then
			M.BuildSkills(content)
			return
		end
		if f.Cat == "people" then
			local head = vgui.Create("DPanel", content)
			head:Dock(TOP)
			head:SetTall(UI.S(70))
			head.Paint = function(_, w, h)
				icon("mem_people", UI.S(22), UI.S(26), UI.S(34), GOLD)
				draw.SimpleText("ЗНАКОМСТВА", NYRP.Font("title", 30), UI.S(52), UI.S(26), INK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				draw.SimpleText("Лица и имена, которые вы помните. Давно не виделись — имя может забыться.", NYRP.Font("regular", 14), UI.S(2), UI.S(56), DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
			local scroll = vgui.Create("NYRP.Scroll", content)
			scroll:Dock(FILL)
			if #M.People == 0 then
				local e = scroll:Add("DPanel")
				e:Dock(TOP)
				e:SetTall(UI.S(200))
				e.Paint = function(_, w, h)
					icon("mem_eye", w / 2, UI.S(70), UI.S(64), Color(255, 255, 255, 60))
					draw.SimpleText(M.Got and "Вы пока ни с кем не знакомы" or "Вспоминаю…", NYRP.Font("medium", 18), w / 2, UI.S(130), DIM, TEXT_ALIGN_CENTER)
					draw.SimpleText("Познакомьтесь с человеком: /познакомиться или покажите удостоверение", NYRP.Font("regular", 13), w / 2, UI.S(158), Color(140, 138, 160), TEXT_ALIGN_CENTER)
				end
				return
			end
			local cardW, cardH = UI.S(230), UI.S(330)
			local perRow = math.max(1, math.floor((cw - UI.S(10)) / (cardW + UI.S(16))))
			local grid = vgui.Create("DIconLayout", scroll)
			grid:Dock(TOP)
			grid:SetSpaceX(UI.S(16))
			grid:SetSpaceY(UI.S(16))
			for i, p in ipairs(M.People) do
				local card = grid:Add("DPanel")
				card:SetSize(cardW, cardH)
				card.Born = RealTime() + i * 0.04
				card.Paint = function(s, w, h)
					local a = math.Clamp((RealTime() - s.Born) / 0.3, 0, 1)
					s:SetAlpha(255 * a)
					UI.RoundedRect(UI.S(14), 0, 0, w, h, Color(255, 255, 255, 12))
					UI.RoundedRect(UI.S(14), 0, 0, w, UI.S(220), Color(30, 24, 52, 200))
					UI.Glow(w / 2, UI.S(150), w * 1.2, UI.S(200), Color(150, 120, 255, 30))
				end
				local mdl = vgui.Create("DModelPanel", card)
				mdl:SetPos(0, 0)
				mdl:SetSize(cardW, UI.S(220))
				mdl:SetModel(p.model or "models/player/group01/male_01.mdl")
				mdl:SetFOV(26)
				mdl:SetMouseInputEnabled(false)
				local e = mdl:GetEntity()
				if IsValid(e) then
					local seq = e:LookupSequence("idle_all_01")
					if seq >= 0 then e:ResetSequence(seq) end
					local b = e:LookupBone("ValveBiped.Bip01_Head1")
					local hp = b and e:GetBonePosition(b) or Vector(0, 0, 64)
					if hp == e:GetPos() then hp = Vector(0, 0, 64) end
					mdl:SetLookAt(hp - Vector(0, 0, 2))
					mdl:SetCamPos(hp + Vector(40, 8, 2))
				end
				mdl.LayoutEntity = function(s, ent)
					ent:SetAngles(Angle(0, 12 + math.sin(RealTime() * 0.6 + i) * 6, 0))
					s:RunAnimation()
				end
				local info = vgui.Create("DPanel", card)
				info:SetPos(UI.S(14), UI.S(228))
				info:SetSize(cardW - UI.S(28), cardH - UI.S(236))
				info.Paint = function(_, w, h)
					draw.SimpleText(p.name or "?", NYRP.Font("title", 20), 0, 0, INK)
					local lines = UI.Wrap(p.desc or "", NYRP.Font("regular", 12), w)
					for k = 1, math.min(3, #lines) do
						draw.SimpleText(lines[k] .. ((k == 3 and #lines > 3) and "…" or ""), NYRP.Font("regular", 12), 0, UI.S(26) + (k - 1) * UI.S(15), DIM)
					end
					icon("mem_eye", UI.S(8), h - UI.S(10), UI.S(14), Color(200, 190, 255, 160))
					draw.SimpleText(ago(p.seen), NYRP.Font("medium", 12), UI.S(20), h - UI.S(10), Color(190, 185, 210), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				end
			end
			grid:InvalidateLayout(true)
			grid:SetTall(math.ceil(#M.People / perRow) * (cardH + UI.S(16)))
		else
			local head = vgui.Create("DPanel", content)
			head:Dock(TOP)
			head:SetTall(UI.S(70))
			head.Paint = function(_, w, h)
				icon("mem_thought", UI.S(22), UI.S(26), UI.S(34), GOLD)
				draw.SimpleText("МЫСЛИ", NYRP.Font("title", 30), UI.S(52), UI.S(26), INK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				draw.SimpleText("Что поручили люди в городе — и что уже сделано.", NYRP.Font("regular", 14), UI.S(2), UI.S(56), DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
			local scroll = vgui.Create("NYRP.Scroll", content)
			scroll:Dock(FILL)
			local N = NYRP.NPC
			local active = N and N.Quests or {}
			local function section(title)
				local s = scroll:Add("DPanel")
				s:Dock(TOP)
				s:SetTall(UI.S(40))
				s:DockMargin(0, UI.S(6), 0, 0)
				s.Paint = function(_, w, h) draw.SimpleText(title, NYRP.Font("title", 16), UI.S(2), h / 2, GOLD, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
			end
			section("СЕЙЧАС НА УМЕ")
			if #active == 0 then
				local e = scroll:Add("DPanel")
				e:Dock(TOP)
				e:SetTall(UI.S(60))
				e.Paint = function(_, w, h) draw.SimpleText("Ни о чём не нужно помнить. Поговорите с людьми в городе.", NYRP.Font("regular", 15), UI.S(2), h / 2, DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
			end
			for _, q in ipairs(active) do
				local row = scroll:Add("DPanel")
				row:Dock(TOP)
				row:SetTall(UI.S(104))
				row:DockMargin(0, 0, UI.S(8), UI.S(10))
				row.Paint = function(s, w, h)
					UI.RoundedRect(UI.S(14), 0, 0, w, h, Color(255, 255, 255, s:IsChildHovered() and 22 or 12))
					UI.RoundedRect(UI.S(2), UI.S(10), UI.S(14), UI.S(4), h - UI.S(28), q.ready and UI.Col.green or VIOLET)
					icon(q.ready and "quest" or "mem_think", UI.S(48), h / 2, UI.S(34), q.ready and UI.Col.green or Color(200, 190, 255))
					draw.SimpleText(q.name, NYRP.Font("title", 21), UI.S(80), UI.S(16), INK)
					draw.SimpleText(q.goal or "", NYRP.Font("medium", 14), UI.S(80), UI.S(46), q.ready and UI.Col.green or Color(220, 215, 235))
					draw.SimpleText((q.npc and q.npc ~= "" and ("Попросил: " .. q.npc) or "") .. (q.desc and q.desc ~= "" and ("  ·  " .. q.desc) or ""),
						NYRP.Font("regular", 13), UI.S(80), UI.S(72), DIM)
				end
				if q.point then
					local tr = vgui.Create("NYRP.Button", row)
					tr:Dock(RIGHT)
					tr:DockMargin(0, UI.S(30), UI.S(16), UI.S(30))
					tr:SetWide(UI.S(180))
					tr:SetFontStyle("bold", 14)
					tr:SetAlign(TEXT_ALIGN_CENTER)
					local function upd()
						local on = N.Tracked == q.key
						tr:SetLabel(on and "МЕТКА ВКЛЮЧЕНА" or "ОТМЕТИТЬ ЦЕЛЬ")
						tr:SetStyle(on and "solid" or "ghost")
						tr:SetAccent(GOLD)
					end
					upd()
					tr.DoClick = function()
						N.Tracked = (N.Tracked ~= q.key) and q.key or nil
						UI.Sound("click")
						upd()
					end
				end
			end
			section("ПРОШЛОЕ")
			if #M.Done == 0 then
				local e = scroll:Add("DPanel")
				e:Dock(TOP)
				e:SetTall(UI.S(50))
				e.Paint = function(_, w, h) draw.SimpleText(M.Got and "Пока нечего вспомнить." or "Вспоминаю…", NYRP.Font("regular", 15), UI.S(2), h / 2, DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
			end
			for _, q in ipairs(M.Done) do
				local row = scroll:Add("DPanel")
				row:Dock(TOP)
				row:SetTall(UI.S(64))
				row:DockMargin(0, 0, UI.S(8), UI.S(8))
				row.Paint = function(_, w, h)
					UI.RoundedRect(UI.S(12), 0, 0, w, h, Color(255, 255, 255, 7))
					icon("mem_done", UI.S(36), h / 2, UI.S(26), Color(170, 165, 190))
					draw.SimpleText(q.name, NYRP.Font("semibold", 17), UI.S(64), UI.S(12), Color(200, 198, 215))
					draw.SimpleText((q.npc ~= "" and ("Для: " .. q.npc .. "  ·  ") or "") .. "выполнено", NYRP.Font("regular", 13), UI.S(64), UI.S(38), Color(140, 138, 160))
				end
			end
		end
	end
	f.Rebuild = function() if f.Cat then buildContent() end end
end

-- клавиша H
local wasDown = false
hook.Add("Think", "nyrp.memory.key", function()
	local down = input.IsKeyDown(KEY_H)
	local pressed = down and not wasDown
	wasDown = down
	if not pressed then return end
	if NYRP.State ~= "playing" or gui.IsGameUIVisible() then return end
	if IsValid(vgui.GetKeyboardFocus()) then return end
	if NYRP.Chat and NYRP.Chat.IsOpen and NYRP.Chat.IsOpen() then return end
	if NYRP.Phone and NYRP.Phone.Prompt then return end
	if NYRP.Bank and NYRP.Bank.ATMActive and NYRP.Bank.ATMActive() then return end
	if not LocalPlayer():Alive() then return end
	M.Open()
end)

-- ------------------------------------------------------------------ Навыки --
-- уровни, опыт до следующего, «практика дня», как качать и что даёт каждый уровень
function M.BuildSkills(content)
	local SK = NYRP.Skills
	local head = vgui.Create("DPanel", content)
	head:Dock(TOP)
	head:SetTall(UI.S(70))
	head.Paint = function(_, w, h)
		icon("skills", UI.S(22), UI.S(26), UI.S(34), GOLD)
		draw.SimpleText("НАВЫКИ", NYRP.Font("title", 30), UI.S(52), UI.S(26), INK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText("Навыки растут от дела. За сутки первые " .. SK.DailyFull .. " опыта навыка идут полностью, дальше — вполовину. Иногда приходит озарение ×2.",
			NYRP.Font("regular", 14), UI.S(2), UI.S(56), DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	local scroll = vgui.Create("NYRP.Scroll", content)
	scroll:Dock(FILL)
	local cap = NYRP.Config.SkillCap or 10
	for i, s in ipairs(NYRP.Config.Skills) do
		local info = SK.Info[s.id] or { how = {}, perks = {} }
		local card = scroll:Add("DPanel")
		card:Dock(TOP)
		card:DockMargin(0, 0, UI.S(10), UI.S(12))
		local perkN = table.Count(info.perks)
		card:SetTall(UI.S(118) + math.max(#info.how, perkN) * UI.S(20))
		card.Born = RealTime() + i * 0.05
		card.Paint = function(p, w, h)
			p:SetAlpha(255 * math.Clamp((RealTime() - p.Born) / 0.3, 0, 1))
			local d = SK.Data
			local lvl = d and d.skills[s.id] or SK.Level(LocalPlayer(), s.id)
			local xp = d and d.xp[s.id] or 0
			local need = SK.Need(lvl)
			local got = d and d.today[s.id] or 0
			UI.RoundedRect(UI.S(14), 0, 0, w, h, Color(255, 255, 255, 10))
			UI.DrawIcon(s.icon, UI.S(30), UI.S(32), UI.S(28), GOLD)
			draw.SimpleText(s.name, NYRP.Font("title", 24), UI.S(56), UI.S(20), INK)
			draw.SimpleText(s.desc, NYRP.Font("regular", 13), UI.S(56), UI.S(48), DIM)
			draw.SimpleText("Уровень " .. lvl .. " / " .. cap, NYRP.Font("bold", 18), w - UI.S(20), UI.S(18), GOLD, TEXT_ALIGN_RIGHT)
			-- шкала опыта
			local bx, by, bw = UI.S(56), UI.S(74), w - UI.S(76)
			UI.RoundedRect(UI.S(4), bx, by, bw, UI.S(8), Color(0, 0, 0, 120))
			local fr = lvl >= cap and 1 or math.Clamp(xp / need, 0, 1)
			if fr > 0 then UI.RoundedRect(UI.S(4), bx, by, math.max(UI.S(8), bw * fr), UI.S(8), Color(150, 120, 255)) end
			draw.SimpleText(lvl >= cap and "Максимум" or (math.floor(xp) .. " / " .. need .. " опыта"), NYRP.Font("medium", 12), bx, by + UI.S(12), DIM)
			local tired = got >= SK.DailyFull
			draw.SimpleText("Сегодня: " .. math.floor(got) .. (tired and " — устал, опыт вполовину" or (" из " .. SK.DailyFull .. " полного")),
				NYRP.Font("medium", 12), bx + bw, by + UI.S(12), tired and Color(230, 150, 90) or DIM, TEXT_ALIGN_RIGHT)
			-- как качать / перки
			local y = UI.S(110)
			local half = (w - UI.S(76)) / 2
			draw.SimpleText("КАК КАЧАТЬ", NYRP.Font("bold", 11), bx, y - UI.S(6), Color(200, 190, 255))
			for k, t in ipairs(info.how) do draw.SimpleText("• " .. t, NYRP.Font("regular", 13), bx, y + k * UI.S(20) - UI.S(8), INK) end
			draw.SimpleText("ЧТО ДАЁТ", NYRP.Font("bold", 11), bx + half, y - UI.S(6), Color(200, 190, 255))
			local lv = table.GetKeys(info.perks)
			table.sort(lv)
			for k, L in ipairs(lv) do
				local open = lvl >= L
				draw.SimpleText((open and "• " or "· ") .. "ур. " .. L .. ": " .. info.perks[L], NYRP.Font("regular", 13), bx + half, y + k * UI.S(20) - UI.S(8),
					open and Color(150, 230, 140) or Color(150, 148, 170))
			end
		end
	end
	SK.OnChange = function() end
end
