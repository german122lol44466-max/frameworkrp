--[[
	Клиент: состояние игры и экраны до спавна.
	NYRP.State: loading -> intro -> menu -> select -> create -> playing
]]

local UI = NYRP.UI
NYRP.State = NYRP.State or "loading"
NYRP.Chars = NYRP.Chars or {}
local Chars = NYRP.Chars
Chars.List = Chars.List or {}
Chars.Max = Chars.Max or 3
NYRP.ClientPoints = NYRP.ClientPoints or { intro = {}, spots = {}, create = {} }
NYRP.PointsConfigured = NYRP.PointsConfigured or false

local function V(t) return Vector(t[1], t[2], t[3]) end
local function A(t) return Angle(t[1], t[2], t[3]) end

function Chars.SetState(state)
	local old = NYRP.State
	NYRP.State = state
	hook.Run("NYRP.StateChanged", state, old)
end

-- ---------------------------------------------------------------- сеть --
hook.Add("InitPostEntity", "nyrp.chars", function()
	net.Start("nyrp.ready")
	net.SendToServer()
end)

net.Receive("nyrp.points", function()
	NYRP.ClientPoints = net.ReadTable()
	NYRP.PointsConfigured = net.ReadBool()
	if NYRP.State == "loading" and NYRP.PointsConfigured then
		if #NYRP.ClientPoints.intro >= 2 then
			Chars.StartIntro()
		else
			Chars.OpenMenu()
		end
	end
	if NYRP.State == "select" then Chars.BuildScene() end
end)

net.Receive("nyrp.char.list", function()
	local list = {}
	for i = 1, net.ReadUInt(8) do
		list[i] = { id = net.ReadUInt(32), name = net.ReadString(), description = net.ReadString(), gender = net.ReadString(),
			model = net.ReadString(), height = net.ReadUInt(8), bag = net.ReadString() }
	end
	Chars.List = list
	Chars.Max = net.ReadUInt(8)
	if NYRP.State == "select" then Chars.BuildScene() end
end)

net.Receive("nyrp.char.state", function()
	local s = net.ReadString()
	if s == "create_failed" and IsValid(Chars.CreatePanel) then Chars.CreatePanel.Busy = false end
end)

net.Receive("nyrp.char.loaded", function()
	local gender = net.ReadString()
	Chars.CloseAll()
	Chars.SetState("playing")
	if NYRP.Wakeup then NYRP.Wakeup(gender) end
end)

-- ------------------------------------------------------------- камеры --
local view = { pos = Vector(), ang = Angle(), fov = 70 }
local camFrom, camTo, camStart, camDur

local function camPoint(t) return V(t.pos), A(t.ang) end

-- Плавный перелёт по списку точек (Catmull-Rom).
local path
local function catmull(p0, p1, p2, p3, t)
	local t2, t3 = t * t, t * t * t
	return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
end

function Chars.FlyPath(points, segTime, onDone)
	if #points == 0 then if onDone then onDone() end return end
	if #points == 1 then
		view.pos, view.ang = camPoint(points[1])
		path = nil
		if onDone then onDone() end
		return
	end
	path = { pts = points, seg = segTime or 3, start = RealTime(), done = onDone }
end

function Chars.SetCamera(point)
	path = nil
	camFrom = nil
	view.pos, view.ang = camPoint(point)
end

-- Плавный переезд камеры к точке.
function Chars.MoveCamera(point, dur)
	path = nil
	camFrom = { pos = view.pos, ang = view.ang }
	camTo = { camPoint(point) }
	camStart, camDur = RealTime(), dur or 1.2
end

local function updatePath()
	if camFrom then
		local t = UI.EaseInOut((RealTime() - camStart) / camDur)
		view.pos = LerpVector(t, camFrom.pos, camTo[1])
		view.ang = LerpAngle(t, camFrom.ang, camTo[2])
		if t >= 1 then camFrom = nil end
		return
	end
	if not path then return end
	local n = #path.pts
	local total = (n - 1) * path.seg
	local el = RealTime() - path.start
	local tt = math.Clamp(el / total, 0, 1)
	tt = UI.EaseInOut(tt) * (n - 1)
	local i = math.min(math.floor(tt) + 1, n - 1)
	local f = tt - (i - 1)
	local P = function(k) return V(path.pts[math.Clamp(k, 1, n)].pos) end
	local AA = function(k) return A(path.pts[math.Clamp(k, 1, n)].ang) end
	view.pos = catmull(P(i - 1), P(i), P(i + 1), P(i + 2), f)
	view.ang = LerpAngle(f, AA(i), AA(i + 1))
	if el >= total then
		local done = path.done
		path = nil
		if done then done() end
	end
end

hook.Add("NYRP.CalcView", "nyrp.chars", function(ply, origin, angles, fov)
	if Chars.EditorActive then return end
	local st = NYRP.State
	if st == "playing" then return end
	updatePath()
	if st == "loading" then
		return { origin = origin, angles = angles, fov = fov, drawviewer = false }
	end
	local pos, ang = view.pos, view.ang
	if st == "menu" then
		-- лёгкое «дыхание» камеры в меню
		local t = RealTime()
		ang = ang + Angle(math.sin(t * 0.35) * 0.6, math.sin(t * 0.22) * 1.2, 0)
	end
	return { origin = pos, angles = ang, fov = 70, drawviewer = false }
end)

function Chars.ViewPos() return view.pos, view.ang end

-- В меню вместо мира — чёрный экран, пока камера не задана (загрузка).
hook.Add("HUDPaintBackground", "nyrp.chars.loading", function()
	if NYRP.State ~= "loading" then return end
	surface.SetDrawColor(6, 7, 12)
	surface.DrawRect(0, 0, ScrW(), ScrH())
	local t = RealTime()
	UI.Glow(ScrW() / 2, ScrH() / 2, UI.S(500), UI.S(500), Color(247, 198, 0, 14))
	surface.SetMaterial(UI.Mat("nyrp/logo.png"))
	surface.SetDrawColor(255, 255, 255, 200 + math.sin(t * 2) * 40)
	local s = UI.S(160)
	surface.DrawTexturedRect(ScrW() / 2 - s / 2, ScrH() / 2 - s / 2 - UI.S(20), s, s)
	local dots = string.rep(".", math.floor(t * 2) % 4)
	draw.SimpleText("Загрузка города" .. dots, NYRP.Font("medium", 18), ScrW() / 2, ScrH() / 2 + s / 2 + UI.S(10), UI.Col.dim, TEXT_ALIGN_CENTER)
end)

function Chars.CloseAll()
	for _, p in ipairs({ Chars.MenuPanel, Chars.SelectPanel, Chars.CreatePanel, Chars.IntroPanel }) do
		if IsValid(p) then p:Remove() end
	end
	Chars.ClearScene()
end

-- --------------------------------------------------------------- интро --
function Chars.StartIntro()
	Chars.SetState("intro")
	local pts = NYRP.ClientPoints.intro
	Chars.SetCamera(pts[1])
	local pnl = vgui.Create("DPanel")
	Chars.IntroPanel = pnl
	pnl:SetSize(ScrW(), ScrH())
	pnl:MakePopup()
	pnl:SetKeyboardInputEnabled(true)
	pnl:SetCursor("blank")
	gui.EnableScreenClicker(false)
	pnl.Born = RealTime()
	local finished = false
	local function finish()
		if finished then return end
		finished = true
		UI.Fade(0.6, 0.3, 0.8, function()
			if IsValid(pnl) then pnl:Remove() end
			Chars.OpenMenu(true)
		end)
	end
	pnl.OnKeyCodePressed = function(_, key)
		if key == KEY_SPACE or key == KEY_ESCAPE or key == KEY_ENTER then finish() end
	end
	pnl.Paint = function(s, w, h)
		local t = RealTime() - s.Born
		-- полосы «кино»
		local bar = UI.S(90) * UI.Ease(t / 1.5)
		surface.SetDrawColor(0, 0, 0, 255)
		surface.DrawRect(0, 0, w, bar)
		surface.DrawRect(0, h - bar, w, bar)
		UI.Vignette(-UI.S(60), -UI.S(60), w + UI.S(120), h + UI.S(120), 200)
		-- заголовок
		local a = math.Clamp((t - 1.2) / 1.5, 0, 1) * (1 - math.Clamp((t - 9) / 2, 0, 1))
		if a > 0 then
			draw.SimpleText("NEW-YORK", NYRP.Font("title", 96), w / 2, h / 2 - UI.S(30), Color(245, 246, 250, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			local tw = UI.S(260) * UI.Ease((t - 1.6) / 1.2)
			UI.RoundedRect(0, w / 2 - tw / 2, h / 2 + UI.S(30), tw, UI.S(40), Color(247, 198, 0, 255 * a))
			draw.SimpleText("R O L E P L A Y", NYRP.Font("bold", 22), w / 2, h / 2 + UI.S(50), Color(10, 14, 28, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		draw.SimpleText("ПРОБЕЛ — пропустить", NYRP.Font("medium", 15), w - UI.S(30), h - bar / 2, Color(255, 255, 255, 90), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end
	UI.Fade(0, 0.2, 1.5)
	Chars.FlyPath(pts, 5, finish)
end

-- --------------------------------------------------------- главное меню --
function Chars.OpenMenu(fromIntro)
	Chars.CloseAll()
	Chars.SetState("menu")
	if NYRP.ClientPoints.menu then Chars.SetCamera(NYRP.ClientPoints.menu) end

	local pnl = vgui.Create("DPanel")
	Chars.MenuPanel = pnl
	pnl:SetSize(ScrW(), ScrH())
	pnl:MakePopup()
	pnl:SetKeyboardInputEnabled(false)
	pnl.Born = RealTime()
	pnl.Paint = function(s, w, h)
		local t = UI.Ease((RealTime() - s.Born) / 0.8)
		-- микровиньетка и затемнение слева под кнопками
		UI.Vignette(-UI.S(30), -UI.S(30), w + UI.S(60), h + UI.S(60), 190)
		surface.SetMaterial(UI.Mat("vgui/gradient-l"))
		surface.SetDrawColor(5, 6, 12, 200 * t)
		surface.DrawTexturedRect(0, 0, w * 0.45, h)
		-- отдельный чистый баннер меню, слева сверху
		local bw = math.min(w * 0.42, UI.S(780))
		local bh = bw * 440 / 1500
		surface.SetMaterial(UI.Mat("nyrp/menu_banner.png"))
		surface.SetDrawColor(255, 255, 255, 255 * t)
		surface.DrawTexturedRect(UI.S(48) - (1 - t) * UI.S(30), UI.S(48), bw, bh)
		draw.SimpleText("v" .. NYRP.Version .. "  ·  работа в процессе", NYRP.Font("regular", 14), UI.S(60), h - UI.S(40), Color(255, 255, 255, 70 * t))
	end

	local buttons = {
		{ "ПЕРСОНАЖИ", "users", function() Chars.OpenSelect() end },
		{ "СООБЩЕСТВО", "world", function() gui.OpenURL(NYRP.Config.CommunityURL) end },
		{ "ОТКЛЮЧИТЬСЯ", "logout", function()
			UI.Confirm("Отключиться?", "Вы покинете сервер New-York Roleplay.", "Отключиться", function() RunConsoleCommand("disconnect") end)
		end },
	}
	local bx, by = UI.S(60), math.max(ScrH() * 0.42, UI.S(48) + math.min(ScrW() * 0.42, UI.S(780)) * 440 / 1500 + UI.S(60))
	for i, b in ipairs(buttons) do
		local btn = vgui.Create("NYRP.Button", pnl)
		btn:SetSize(UI.S(340), UI.S(58))
		btn:SetPos(bx, by + (i - 1) * UI.S(68))
		btn:SetLabel(b[1])
		btn:SetIcon(b[2])
		btn:SetFontStyle("title", 26)
		btn.DoClick = b[3]
		btn:SetAlpha(0)
		btn:AlphaTo(255, 0.4, 0.15 + i * 0.08)
	end
	if not fromIntro then UI.Fade(0, 0.1, 0.8) end
end

-- -------------------------------------------------------- выбор персонажа --
Chars.Scene = Chars.Scene or {}

function Chars.ClearScene()
	if IsValid(Chars.Card) then Chars.Card:Remove() end
	Chars.Selected, Chars.Hovered = nil, nil
	for _, s in ipairs(Chars.Scene) do
		if IsValid(s.ent) then s.ent:Remove() end
		if IsValid(s.panel) then s.panel:Remove() end
	end
	Chars.Scene = {}
end

local function spawnModel(model, pos, ang, silhouette)
	local ent = ClientsideModel(model, RENDERGROUP_OPAQUE)
	if not IsValid(ent) then return end
	ent:SetPos(pos)
	ent:SetAngles(ang)
	local seq = ent:LookupSequence(silhouette and "idle_all_02" or "idle_all_01")
	if seq and seq >= 0 then ent:ResetSequence(seq) end
	ent.nyrpSil = silhouette
	ent.RenderOverride = function(self)
		if self.nyrpSil then
			render.SetColorModulation(0.015, 0.015, 0.02)
			render.MaterialOverride(Material("models/debug/debugwhite"))
			self:DrawModel()
			render.MaterialOverride(nil)
			render.SetColorModulation(1, 1, 1)
		else
			self:DrawModel()
		end
	end
	return ent
end

function Chars.BuildScene()
	Chars.ClearScene()
	local spots = NYRP.ClientPoints.spots or {}
	for i, spot in ipairs(spots) do
		local c = Chars.List[i]
		local pos, ang = V(spot.pos), A(spot.ang)
		local s = { index = i, char = c, pos = pos, ang = ang }
		if c then
			s.ent = spawnModel(c.model, pos, ang, false)
			if IsValid(s.ent) then s.ent:SetModelScale(NYRP.Chars.HeightScale and NYRP.Chars.HeightScale(c.height) or 1, 0) end
		elseif i <= Chars.Max then
			s.ent = spawnModel(NYRP.Config.Models.male[1], pos, ang, true)
		end
		Chars.Scene[#Chars.Scene + 1] = s
	end
end

-- Карточка над персонажем.
function Chars.MakeCharCard(s)
	local card = vgui.Create("DPanel", Chars.SelectPanel)
	card:SetSize(UI.S(330), UI.S(176))
	card.Born = RealTime()
	card.Paint = function(p, w, h)
		local t = UI.Ease((RealTime() - p.Born) / 0.4)
		p:SetAlpha(255 * t)
		UI.RoundedBlurPanel(p, UI.S(12), 4)
		UI.RoundedRect(UI.S(12), 0, 0, w, h, Color(10, 12, 20, 215))
		UI.Outline(UI.S(12), 0, 0, w, h, Color(255, 255, 255, 18), 1)
		UI.RoundedRect(UI.S(2), UI.S(16), UI.S(16), UI.S(4), UI.S(26), UI.Col.accent)
		draw.SimpleText(s.char.name, NYRP.Font("title", 24), UI.S(28), UI.S(29), UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		local lines = UI.Wrap(s.char.description, NYRP.Font("regular", 14), w - UI.S(32))
		for i = 1, math.min(#lines, 3) do
			local l = lines[i]
			if i == 3 and #lines > 3 then l = l .. "…" end
			draw.SimpleText(l, NYRP.Font("regular", 14), UI.S(16), UI.S(50) + (i - 1) * UI.S(18), UI.Col.dim)
		end
		if Chars.Selected ~= s then
			draw.SimpleText("Нажмите на персонажа, чтобы выбрать", NYRP.Font("regular", 12), w - UI.S(14), UI.S(29), UI.Col.faint, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
	end
	-- карточка — панель интерфейса сбоку от персонажа на экране
	card.Think = function(p)
		if not IsValid(s.ent) then return end
		local sc = (s.ent:GetPos() + Vector(0, 0, 48 * s.ent:GetModelScale())):ToScreen()
		local x = sc.x + UI.S(110)
		if x + p:GetWide() > ScrW() - UI.S(20) then x = sc.x - UI.S(110) - p:GetWide() end
		local tx = math.Clamp(x, UI.S(20), ScrW() - p:GetWide() - UI.S(20))
		local ty = math.Clamp(sc.y - p:GetTall() / 2, UI.S(120), ScrH() - p:GetTall() - UI.S(120))
		local cx, cy = p:GetPos()
		if not p.Placed then cx, cy = tx, ty p.Placed = true end
		p:SetPos(UI.Approach(cx, tx, 18), UI.Approach(cy, ty, 18))
	end
	local take = vgui.Create("NYRP.Button", card)
	take:SetPos(UI.S(16), card:GetTall() - UI.S(54))
	take:SetSize(UI.S(200), UI.S(40))
	take:SetLabel("ВЗЯТЬ")
	take:SetIcon("play")
	take:SetStyle("solid")
	take:SetFontStyle("bold", 16)
	take.DoClick = function()
		UI.Sound("start")
		UI.Fade(0.6, 0, 0.01, function()
			Chars.HoldBlack = true
			timer.Create("nyrp.holdblack", 8, 1, function() Chars.HoldBlack = false end)
			net.Start("nyrp.char.load")
			net.WriteUInt(s.char.id, 32)
			net.SendToServer()
		end)
	end
	local del = vgui.Create("NYRP.Button", card)
	del:SetPos(UI.S(226), card:GetTall() - UI.S(54))
	del:SetSize(UI.S(88), UI.S(40))
	del:SetLabel("")
	del:SetIcon("trash")
	del:SetAlign(TEXT_ALIGN_CENTER)
	del:SetStyle("ghost")
	del:SetAccent(UI.Col.red)
	del.DoClick = function()
		UI.Confirm("Удалить персонажа?", "«" .. s.char.name .. "» будет удалён навсегда вместе с инвентарём.", "Удалить", function()
			UI.Sound("delete")
			net.Start("nyrp.char.delete")
			net.WriteUInt(s.char.id, 32)
			net.SendToServer()
		end)
	end
	return card
end

function Chars.OpenSelect()
	UI.Sound("swipe")
	UI.Fade(0.4, 0.25, 0.6, function()
		Chars.CloseAll()
		Chars.SetState("select")
		if NYRP.ClientPoints.chars then Chars.SetCamera(NYRP.ClientPoints.chars) end

		local pnl = vgui.Create("DPanel")
		Chars.SelectPanel = pnl
		pnl:SetSize(ScrW(), ScrH())
		pnl:MakePopup()
		pnl:SetKeyboardInputEnabled(false)
		pnl.Paint = function(_, w, h)
			UI.Vignette(-UI.S(30), -UI.S(30), w + UI.S(60), h + UI.S(60), 170)
			draw.SimpleText("ВЫБОР ПЕРСОНАЖА", NYRP.Font("title", 34), UI.S(60), UI.S(50), UI.Col.text)
			draw.SimpleText(#Chars.List .. " / " .. Chars.Max .. " персонажей", NYRP.Font("medium", 16), UI.S(62), UI.S(94), UI.Col.dim)
			-- «?» над пустыми местами
			for _, s in ipairs(Chars.Scene) do
				if not s.char and IsValid(s.ent) then
					local sc = (s.ent:GetPos() + Vector(0, 0, 90)):ToScreen()
					local hov = s == Chars.Hovered
					s.hover = UI.Approach(s.hover or 0, hov and 1 or 0, 10)
					local bob = math.sin(RealTime() * 2 + s.index) * UI.S(4)
					local r = UI.S(22) + s.hover * UI.S(5)
					UI.Circle(sc.x, sc.y + bob, r, Color(255, 255, 255, 230))
					UI.DrawIcon("question", sc.x, sc.y + bob, r * 1.1, Color(10, 12, 18))
					if s.hover > 0.05 then
						draw.SimpleText("Создать персонажа", NYRP.Font("semibold", 17), sc.x, sc.y + bob + r + UI.S(10),
							Color(255, 255, 255, 255 * s.hover), TEXT_ALIGN_CENTER)
					end
				end
			end
		end
		pnl.Think = function()
			pnl.UpdateCard()
			Chars.Hovered = nil
			if vgui.GetHoveredPanel() ~= pnl then return end
			local pos, ang = Chars.ViewPos()
			local dir = Chars.ScreenRay(ang, 70, gui.MouseX(), gui.MouseY())
			local best, bestD
			for _, s in ipairs(Chars.Scene) do
				if IsValid(s.ent) then
					local mn, mx = s.ent:GetModelBounds()
					local hit = util.IntersectRayWithOBB(pos, dir * 4000, s.ent:GetPos(), s.ent:GetAngles(), mn, mx)
					if hit and (not bestD or hit:DistToSqr(pos) < bestD) then best, bestD = s, hit:DistToSqr(pos) end
				end
			end
			if best ~= Chars.LastHovered and best then UI.Sound("hover") end
			Chars.LastHovered = best
			Chars.Hovered = best
			pnl:SetCursor(best and "hand" or "arrow")
		end
		pnl.UpdateCard = function()
			local card = Chars.Card
			local target = Chars.Hovered and Chars.Hovered.char and Chars.Hovered or nil
			if IsValid(card) and (card:IsHovered() or card:IsChildHovered()) then target = card.Spot end
			target = target or Chars.Selected
			if target == (IsValid(card) and card.Spot or nil) then return end
			if IsValid(card) then card:Remove() end
			if target then
				Chars.Card = Chars.MakeCharCard(target)
				Chars.Card.Spot = target
			end
		end
		pnl.OnMousePressed = function(_, code)
			if code ~= MOUSE_LEFT then return end
			local h = Chars.Hovered
			if h and h.char then
				Chars.Selected = h
				UI.Sound("click")
			elseif h then
				UI.Sound("expand")
				Chars.OpenCreate(h)
			else
				Chars.Selected = nil
			end
		end

		local back = vgui.Create("NYRP.Button", pnl)
		back:SetSize(UI.S(200), UI.S(48))
		back:SetPos(UI.S(60), ScrH() - UI.S(100))
		back:SetLabel("НАЗАД")
		back:SetIcon("arrow_left")
		back:SetFontStyle("title", 20)
		back.DoClick = function()
			UI.Fade(0.35, 0.2, 0.6, function() Chars.OpenMenu(true) end)
		end
		Chars.BuildScene()
	end)
end

hook.Add("PreDrawHalos", "nyrp.chars", function()
	if NYRP.State ~= "select" then return end
	local h, sel = Chars.Hovered, Chars.Selected
	if sel and IsValid(sel.ent) then halo.Add({ sel.ent }, UI.Col.accent, 2, 2, 2, true, false) end
	if h and h ~= sel and IsValid(h.ent) then halo.Add({ h.ent }, Color(255, 255, 255), 2, 2, 2, true, false) end
end)

-- Анимация моделей сцены.
hook.Add("Think", "nyrp.chars.scene", function()
	for _, s in ipairs(Chars.Scene) do
		if IsValid(s.ent) then
			local d = s.ent:SequenceDuration()
			s.ent:SetCycle(d > 0 and ((RealTime() + s.index) / d) % 1 or 0)
		end
	end
end)

-- Луч из камеры через точку экрана (fov задан для 4:3, как в CalcView).
function Chars.ScreenRay(ang, fov, x, y)
	local w, h = ScrW(), ScrH()
	local tanH = math.tan(math.rad(fov) / 2) * (w / h) / (4 / 3)
	local dx = (2 * x / w - 1) * tanH
	local dy = (2 * y / h - 1) * tanH * h / w
	return (ang:Forward() + ang:Right() * dx - ang:Up() * dy):GetNormalized()
end

-- Чёрный экран между «Взять/Создать» и появлением персонажа.
hook.Add("PostRenderVGUI", "nyrp.chars.hold", function()
	if Chars.HoldBlack then
		surface.SetDrawColor(0, 0, 0, 255)
		surface.DrawRect(0, 0, ScrW(), ScrH())
	end
end)

-- Страховка: если модели сцены выбора пропали (их удалила очистка карты / другая часть
-- интерфейса) или сцена не построилась — пересобираем её.
hook.Add("Think", "nyrp.chars.scene", function()
	if NYRP.State ~= "select" then return end
	local spots = NYRP.ClientPoints.spots or {}
	if #spots == 0 then return end
	local broken = #Chars.Scene == 0
	for _, s in ipairs(Chars.Scene) do
		if (s.char or s.index <= (Chars.Max or 0)) and not IsValid(s.ent) then broken = true break end
	end
	if broken and (Chars.NextRebuild or 0) < RealTime() then
		Chars.NextRebuild = RealTime() + 1
		Chars.BuildScene()
	end
end)
