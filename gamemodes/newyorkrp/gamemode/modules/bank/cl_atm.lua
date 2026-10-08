--[[
	Банкомат на клиенте. Сеанс:
	  insert — камера подъезжает к банкомату, рука вставляет карту (v_atm, «insert»);
	  pin    — ввод PIN: цифры на клавиатуре или клик по кнопкам на экране, рука нажимает клавиши («type»);
	  menu   — камера отъезжает, видно весь экран: баланс, снять/внести наличные, штрафы, история;
	  take   — камера снова у клавиатуры, рука забирает карту («take»), затем вид возвращается игроку.
	Меню рисуется прямо на экране банкомата (3D2D), мышь свободна, клик — луч из камеры в плоскость экрана.
	Esc/ПКМ — назад или выход.
]]

local UI = NYRP.UI
local B = NYRP.Bank
local G = B.ATM

local A                     -- текущий сеанс
local confirmAmount         -- (ниже)
local SCALE = 0.02          -- 14 ед. экрана = 700 px
local PW = 700
local FPS = 30

local function now() return RealTime() end

-- ------------------------------------------------------------- модели рук --
local vm, hands

local function freeModels()
	if IsValid(hands) then hands:Remove() end
	if IsValid(vm) then vm:Remove() end
	vm, hands = nil, nil
end

local function ensureModels()
	if not IsValid(vm) then
		vm = ClientsideModel("models/nyrp/atm/v_atm.mdl", RENDERGROUP_OPAQUE)
		if not IsValid(vm) then return end
		vm:SetNoDraw(true)
		vm.RenderOverride = function(e) if e.nyrpDraw then e:DrawModel() end end
	end
	local ph = LocalPlayer():GetHands()
	local mdl = IsValid(ph) and ph:GetModel() or ""
	if mdl == "" then mdl = "models/weapons/c_arms_citizen.mdl" end
	if not IsValid(hands) or hands:GetModel() ~= mdl then
		if IsValid(hands) then hands:Remove() end
		hands = ClientsideModel(mdl, RENDERGROUP_OPAQUE)
		if not IsValid(hands) then return end
		hands:SetNoDraw(true)
		hands.RenderOverride = function(e) if e.nyrpDraw then e:DrawModel() end end
		hands:SetParent(vm)
		hands:AddEffects(EF_BONEMERGE)
		if IsValid(ph) then
			hands:SetSkin(ph:GetSkin())
			for i = 0, ph:GetNumBodyGroups() - 1 do hands:SetBodygroup(i, ph:GetBodygroup(i)) end
		end
	end
	return vm, hands
end

-- последовательность и её начало
local function playSeq(name)
	if not A then return end
	A.seq, A.seqT = name, now()
end

local SEQ_FRAMES = { insert = 34, reach = 12, type = 48, menu = 2, take = 34 }
local LOOP = { type = true, menu = true }

local function seqDone()
	return A and not LOOP[A.seq] and (now() - A.seqT) * FPS >= (SEQ_FRAMES[A.seq] or 1)
end

hook.Add("PostDrawOpaqueRenderables", "nyrp.atm.hands", function(depth, sky)
	if sky or depth or not A or not IsValid(A.ent) then return end
	local m, h = ensureModels()
	if not IsValid(m) or not IsValid(h) then return end
	local seq = m:LookupSequence(A.seq or "menu")
	if seq < 0 then return end
	if m:GetSequence() ~= seq then m:ResetSequence(seq) end
	local frames = SEQ_FRAMES[A.seq] or 1
	local t = (now() - A.seqT) * FPS / frames
	m:SetPlaybackRate(0)
	m:SetCycle(LOOP[A.seq] and t % 1 or math.Clamp(t, 0, 0.999))
	-- модель стоит в точке «камеры ввода PIN»: так карта всегда в щели, а руки — у клавиатуры
	local pos, ang = B.CamWorld(A.ent, G.camPin)
	m:SetPos(pos)
	m:SetAngles(ang)
	m:InvalidateBoneCache()
	m:SetupBones()
	h:InvalidateBoneCache()
	h:SetupBones()
	m.nyrpDraw = true
	m:DrawModel()
	m.nyrpDraw = false
	-- в меню руки опущены (камера дальше — их не показываем)
	if A.seq ~= "menu" then
		h.nyrpDraw = true
		h:DrawModel()
		h.nyrpDraw = false
	end
end)

-- ---------------------------------------------------------------- камера --
local function camTarget()
	if not A then return end
	local cam = (A.stage == "menu") and G.camMenu or G.camPin
	return B.CamWorld(A.ent, cam)
end

hook.Add("NYRP.CalcView", "nyrp.atm", function(ply, origin, angles, fov)
	if not A or not IsValid(A.ent) then return end
	local tp, ta = camTarget()
	A.camPos = A.camPos or origin
	A.camAng = A.camAng or angles
	A.camFov = A.camFov or fov
	local k = 1 - math.exp(-FrameTime() * (A.leaving and 7 or 5))
	if A.leaving then tp, ta = origin, angles end
	A.camPos = LerpVector(k, A.camPos, tp)
	A.camAng = LerpAngle(k, A.camAng, ta)
	A.camFov = Lerp(k, A.camFov, A.leaving and fov or G.fov)
	A.viewPos, A.viewAng, A.viewFov = A.camPos, A.camAng, A.camFov
	return { origin = A.camPos, angles = A.camAng, fov = A.camFov, drawviewer = false, znear = 1 }
end)

-- ---------------------------------------------------------------- сеанс --
local function setClicker(on)
	if A then A.clicker = on end
	gui.EnableScreenClicker(on)
end

local function finish()
	if A and A.clicker then gui.EnableScreenClicker(false) end
	A = nil
	freeModels()
end

local function leave()
	if not A or A.stage == "take" then return end
	net.Start("nyrp.atm.op")
	net.WriteString("close")
	net.WriteDouble(0)
	net.SendToServer()
	A.stage = "take"
	A.page = nil
	setClicker(false)
	playSeq("take")
	UI.Sound("close")
end

net.Receive("nyrp.atm.open", function()
	local ent, bank, number, holder = net.ReadEntity(), net.ReadString(), net.ReadString(), net.ReadString()
	if not IsValid(ent) then return end
	finish()
	A = { ent = ent, bank = bank, number = number, holder = holder, stage = "insert", pin = "", amount = "", page = "main", born = now(), msg = "", msgT = 0,
		confirmAmount = function() confirmAmount() end }
	playSeq("insert")
	timer.Simple(0.75, function() if A and A.ent == ent then ent:EmitSound("buttons/lightswitch2.wav", 50, 140) end end)
end)

net.Receive("nyrp.atm.info", function()
	if not A then return end
	local authed, msg = net.ReadBool(), net.ReadString()
	if authed then
		A.info = { balance = net.ReadDouble(), cash = net.ReadDouble(), fines = net.ReadTable(), log = net.ReadTable() }
	end
	if msg ~= "" then A.msg, A.msgT = msg, now() end
	if authed and A.stage == "pin" then
		A.stage = "menu"
		A.page = "main"
		playSeq("menu")
		UI.Sound("success")
	elseif not authed then
		A.pin = ""
	end
	if A.page == "amount" and authed then A.amount = "" A.page = "main" end
end)

net.Receive("nyrp.atm.close", function()
	if A and A.stage ~= "take" then
		A.stage = "take"
		setClicker(false)
		playSeq("take")
	end
end)

local function op(name, arg)
	net.Start("nyrp.atm.op")
	net.WriteString(name)
	net.WriteDouble(arg or 0)
	net.SendToServer()
end

local function sendPin()
	if #A.pin < 4 then return end
	net.Start("nyrp.atm.pin")
	net.WriteString(A.pin)
	net.SendToServer()
	A.wait = now()
end

-- ход сеанса по времени
hook.Add("Think", "nyrp.atm.flow", function()
	if not A then return end
	if not IsValid(A.ent) or not LocalPlayer():Alive() then finish() return end
	if A.stage == "insert" and seqDone() then
		A.stage = "pin"
		playSeq("reach")
		setClicker(true)
	elseif A.stage == "pin" then
		-- рука «печатает», пока вводят цифры, иначе держится над клавиатурой
		if (A.typing or 0) > now() then
			if A.seq ~= "type" then playSeq("type") end
		elseif A.seq == "type" then
			playSeq("reach")
			A.seqT = now() - 1     -- сразу конец «reach»: рука над клавишами
		end
	elseif A.stage == "take" and seqDone() and not A.leaving then
		A.leaving = now()
		A.ent:EmitSound("buttons/lightswitch2.wav", 50, 120)
	end
	if A.leaving and now() - A.leaving > 0.7 then finish() end
end)

-- двигаться и стрелять во время сеанса нельзя
hook.Add("CreateMove", "nyrp.atm", function(cmd)
	if not A then return end
	cmd:ClearMovement()
	cmd:RemoveKey(IN_ATTACK)
	cmd:RemoveKey(IN_ATTACK2)
	cmd:RemoveKey(IN_USE)
	cmd:RemoveKey(IN_JUMP)
	cmd:RemoveKey(IN_DUCK)
end)

hook.Add("InputMouseApply", "nyrp.atm", function(cmd)
	if not A then return end
	cmd:SetMouseX(0)
	cmd:SetMouseY(0)
	return true
end)

hook.Add("PlayerBindPress", "nyrp.atm", function(_, bind, pressed)
	if not A then return end
	if pressed and bind:find("+attack2") then
		if A.page and A.page ~= "main" then A.page = "main" else leave() end
		return true
	end
	if bind:find("voicerecord") or bind:find("messagemode") then return end
	if bind:find("+") or bind:find("slot") or bind:find("inv") then return true end
end)

-- --------------------------------------------------------- ввод с клавиатуры --
local keys = {}
local function pressedKey(k)
	local d = input.IsKeyDown(k)
	local was = keys[k]
	keys[k] = d
	return d and not was
end

local function digit(d)
	if A.stage == "pin" then
		if #A.pin < 4 then
			A.pin = A.pin .. d
			A.typing = now() + 0.7
			A.ent:EmitSound("buttons/button17.wav", 45, 100 + math.random(-8, 8))
			if #A.pin == 4 then timer.Simple(0.25, function() if A and A.stage == "pin" then sendPin() end end) end
		end
	elseif A.page == "amount" and #A.amount < 6 then
		A.amount = A.amount .. d
		A.ent:EmitSound("buttons/button17.wav", 45, 110)
	end
end

local function backspace()
	if A.stage == "pin" then A.pin = A.pin:sub(1, -2)
	elseif A.page == "amount" then A.amount = A.amount:sub(1, -2) end
end

hook.Add("Think", "nyrp.atm.keys", function()
	if not A or gui.IsGameUIVisible() then
		if A and gui.IsGameUIVisible() then
			-- Esc — выйти из банкомата, а не открыть меню игры
			gui.HideGameUI()
			if A.page and A.page ~= "main" then A.page = "main" else leave() end
		end
		return
	end
	for d = 0, 9 do
		local a, b = pressedKey(KEY_0 + d), pressedKey(KEY_PAD_0 + d)
		if a or b then digit(tostring(d)) end
	end
	if pressedKey(KEY_BACKSPACE) then backspace() end
	if pressedKey(KEY_ENTER) or pressedKey(KEY_PAD_ENTER) then
		if A.stage == "pin" then sendPin()
		elseif A.page == "amount" then A.confirmAmount() end
	end
end)

-- -------------------------------------------------- экран: кнопки и клики --
local btns = {}
local hovered

local function mouseOnScreen(ent)
	if not A or ent ~= A.ent or not A.viewPos or not vgui.CursorVisible() and not NYRP.ScreenClicker then return end
	local mx, my = gui.MousePos()
	local w, h = ScrW(), ScrH()
	local tanH = math.tan(math.rad(A.viewFov or G.fov) / 2) * (w / h) / (4 / 3)
	local dx = (2 * mx / w - 1) * tanH
	local dy = (2 * my / h - 1) * tanH * h / w
	local ang = A.viewAng
	local dir = (ang:Forward() + ang:Right() * dx - ang:Up() * dy):GetNormalized()
	local origin = ent:LocalToWorld(Vector(G.screenX + 0.01, -G.screenY, G.screenTop))
	local hit = util.IntersectRayWithPlane(A.viewPos, dir, origin, ent:GetForward())
	if not hit then return end
	local d = hit - origin
	return d:Dot(-ent:GetRight()) / SCALE, d:Dot(-ent:GetUp()) / SCALE
end

local function btn(id, x, y, w, h, fn)
	btns[#btns + 1] = { id = id, x = x, y = y, w = w, h = h, fn = fn }
	return hovered == id
end

hook.Add("GUIMousePressed", "nyrp.atm", function(code)
	if not A then return end
	if code == MOUSE_RIGHT then
		if A.page and A.page ~= "main" then A.page = "main" else leave() end
		return
	end
	if code ~= MOUSE_LEFT then return end
	for i = #btns, 1, -1 do
		local b = btns[i]
		if b.id == hovered then
			A.ent:EmitSound("buttons/button15.wav", 45, 110)
			A.typing = now() + 0.4
			b.fn()
			return
		end
	end
end)

-- ---------------------------------------------------------------- рисование --
local function T(text, size, x, y, col, ax, ay, style)
	draw.SimpleText(text, NYRP.FontRaw(style or "semibold", size), x, y, col or color_white, ax or TEXT_ALIGN_LEFT, ay or TEXT_ALIGN_TOP)
end

local function box(x, y, w, h, col, r)
	draw.RoundedBox(r or 10, x, y, w, h, col)
end

local function bigButton(id, x, y, w, h, label, sub, col, fn, icon)
	local hv = btn(id, x, y, w, h, fn)
	box(x, y, w, h, hv and Color(255, 255, 255, 40) or Color(255, 255, 255, 16), 12)
	if hv then
		surface.SetDrawColor(col.r, col.g, col.b, 255)
		surface.DrawRect(x, y + 10, 5, h - 20)
	end
	local tx = x + 24
	if icon then
		surface.SetMaterial(UI.Icon(icon))
		surface.SetDrawColor(col)
		surface.DrawTexturedRect(x + 20, y + h / 2 - 18, 36, 36)
		tx = x + 72
	end
	T(label, 30, tx, y + (sub and h / 2 - 2 or h / 2), color_white, TEXT_ALIGN_LEFT, sub and TEXT_ALIGN_BOTTOM or TEXT_ALIGN_CENTER, "bold")
	if sub then T(sub, 20, tx, y + h / 2 + 4, Color(200, 205, 220), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, "medium") end
end

local function money(n) return NYRP.Money.Format(n or 0) end

local function drawIdle(ent, bank, busy)
	local t = now()
	box(0, 0, PW, PW, bank.dark, 0)
	surface.SetMaterial(UI.Mat("vgui/gradient-d"))
	surface.SetDrawColor(bank.color.r, bank.color.g, bank.color.b, 120)
	surface.DrawTexturedRect(0, PW * 0.4, PW, PW * 0.6)
	T(bank.name, 64, PW / 2, 120, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, "title")
	T(bank.tag, 24, PW / 2, 178, Color(255, 255, 255, 170), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, "medium")
	if busy then
		T("Идёт обслуживание клиента", 34, PW / 2, PW / 2 + 40, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, "bold")
		T("Пожалуйста, подождите", 24, PW / 2, PW / 2 + 86, Color(255, 255, 255, 160), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, "medium")
		return
	end
	-- карта «заходит» в щель
	local k = (t % 2.4) / 2.4
	local cy = PW / 2 + 30 + math.sin(k * math.pi) * -40
	box(PW / 2 - 110, cy - 70, 220, 140, Color(255, 255, 255, 230), 14)
	box(PW / 2 - 80, cy - 30, 46, 34, Color(214, 172, 70), 6)
	box(PW / 2 - 90, cy + 26, 180, 10, Color(40, 44, 60), 3)
	T("Вставьте карту", 40, PW / 2, PW - 150, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, "bold")
	T("Подойдите и нажмите E", 24, PW / 2, PW - 104, Color(255, 255, 255, 170), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, "medium")
end

local function header(bank)
	box(0, 0, PW, 96, bank.color, 0)
	T(bank.name, 38, 28, 48, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, "title")
	T(B.MaskCard(A.number), 24, PW - 28, 32, Color(255, 255, 255, 220), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, "bold")
	T(A.holder, 18, PW - 28, 62, Color(255, 255, 255, 180), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, "medium")
end

local function drawPin(bank)
	box(0, 0, PW, PW, Color(10, 12, 20), 0)
	header(bank)
	-- всё нужное — в нижней половине: при вводе PIN камера ниже и видит её
	T("Введите PIN-код", 40, PW / 2, 300, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, "bold")
	for i = 1, 4 do
		local cx = PW / 2 + (i - 2.5) * 70
		box(cx - 26, 340, 52, 64, Color(255, 255, 255, 24), 10)
		if i <= #A.pin then
			draw.NoTexture()
			UI.Circle(cx, 372, 12, color_white)
		end
	end
	local msg = (now() - A.msgT < 3) and A.msg or ""
	if msg ~= "" then T(msg, 22, PW / 2, 432, Color(255, 120, 110), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, "semibold") end
	-- экранные цифры
	local kw, kh = 120, 54
	local gx, gy = PW / 2 - (kw * 5 + 16 * 4) / 2, 470
	for i = 0, 9 do
		local col, row = i % 5, math.floor(i / 5)
		local x, y = gx + col * (kw + 16), gy + row * (kh + 12)
		local d = tostring((i + 1) % 10)
		local hv = btn("d" .. d, x, y, kw, kh, function() digit(d) end)
		box(x, y, kw, kh, hv and Color(255, 255, 255, 60) or Color(255, 255, 255, 22), 10)
		T(d, 32, x + kw / 2, y + kh / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, "bold")
	end
	local by = gy + 2 * (kh + 12)
	local hv1 = btn("cancel", gx, by, 300, 56, leave)
	box(gx, by, 300, 56, hv1 and Color(220, 60, 50) or Color(170, 40, 35), 10)
	T("Отмена", 28, gx + 150, by + 28, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, "bold")
	local hv2 = btn("enter", PW - gx - 300, by, 300, 56, sendPin)
	box(PW - gx - 300, by, 300, 56, hv2 and Color(60, 200, 100) or Color(40, 160, 80), 10)
	T("Ввод", 28, PW - gx - 150, by + 28, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, "bold")
end

local QUICK = { 20, 50, 100, 200, 500 }

local function drawMenu(bank, ent)
	box(0, 0, PW, PW, Color(10, 12, 20), 0)
	header(bank)
	local info = A.info or {}
	-- баланс
	box(28, 120, PW - 56, 110, Color(255, 255, 255, 14), 14)
	T("Баланс счёта", 22, 52, 138, Color(200, 205, 220), nil, nil, "medium")
	T(money(info.balance), 54, 52, 164, color_white, nil, nil, "title")
	T("Наличные: " .. money(info.cash), 22, PW - 52, 140, Color(200, 205, 220), TEXT_ALIGN_RIGHT, nil, "medium")
	local foreign = ent:GetBank() ~= A.bank
	if foreign then T("Банкомат другого банка: комиссия " .. money(B.ForeignFee), 18, PW - 52, 200, Color(247, 198, 0), TEXT_ALIGN_RIGHT, nil, "semibold") end

	local page = A.page or "main"
	local y0 = 252
	if page == "main" then
		local fines = info.fines or {}
		local w2 = (PW - 56 - 16) / 2
		bigButton("w", 28, y0, w2, 100, "Снять", "наличными", bank.color, function() A.page = "amount" A.mode = "withdraw" A.amount = "" end, "p_cash")
		bigButton("dp", 28 + w2 + 16, y0, w2, 100, "Внести", "наличные на счёт", bank.color, function() A.page = "amount" A.mode = "deposit" A.amount = "" end, "p_card")
		bigButton("f", 28, y0 + 116, w2, 100, "Штрафы", #fines > 0 and (#fines .. " к оплате") or "нет штрафов", #fines > 0 and Color(230, 80, 60) or bank.color,
			function() A.page = "fines" end, "warning")
		bigButton("h", 28 + w2 + 16, y0 + 116, w2, 100, "История", "последние операции", bank.color, function() A.page = "history" end, "p_recent")
		local hv = btn("exit", 28, y0 + 240, PW - 56, 80, leave)
		box(28, y0 + 240, PW - 56, 80, hv and Color(220, 60, 50) or Color(255, 255, 255, 16), 12)
		T("Забрать карту и завершить", 28, PW / 2, y0 + 280, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, "bold")
	elseif page == "amount" then
		local wd = A.mode == "withdraw"
		T(wd and "Сумма снятия" or "Сумма внесения", 30, 28, y0, color_white, nil, nil, "bold")
		local bw = (PW - 56 - 4 * 12) / 5
		for i, v in ipairs(QUICK) do
			local x = 28 + (i - 1) * (bw + 12)
			local hv = btn("q" .. v, x, y0 + 48, bw, 70, function() A.amount = tostring(v) end)
			box(x, y0 + 48, bw, 70, (A.amount == tostring(v)) and bank.color or (hv and Color(255, 255, 255, 50) or Color(255, 255, 255, 18)), 10)
			T("$" .. v, 30, x + bw / 2, y0 + 83, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, "bold")
		end
		box(28, y0 + 136, PW - 56, 80, Color(255, 255, 255, 10), 12)
		local txt = A.amount == "" and "Введите сумму цифрами" or ("$" .. A.amount)
		T(txt, A.amount == "" and 26 or 44, PW / 2, y0 + 176, A.amount == "" and Color(150, 155, 170) or color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, "bold")
		if math.floor(now() * 2) % 2 == 0 and A.amount ~= "" then
			surface.SetFont(NYRP.FontRaw("bold", 44))
			local tw = surface.GetTextSize(txt)
			surface.SetDrawColor(247, 198, 0)
			surface.DrawRect(PW / 2 + tw / 2 + 6, y0 + 154, 4, 44)
		end
		local w2 = (PW - 56 - 16) / 2
		local hv1 = btn("back", 28, y0 + 236, w2, 76, function() A.page = "main" end)
		box(28, y0 + 236, w2, 76, hv1 and Color(255, 255, 255, 50) or Color(255, 255, 255, 18), 12)
		T("Назад", 28, 28 + w2 / 2, y0 + 274, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, "bold")
		local hv2 = btn("ok", 44 + w2, y0 + 236, w2, 76, A.confirmAmount)
		box(44 + w2, y0 + 236, w2, 76, hv2 and Color(60, 200, 100) or Color(40, 160, 80), 12)
		T(wd and "Снять" or "Внести", 28, 44 + w2 + w2 / 2, y0 + 274, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, "bold")
		if wd and foreign then T("+ комиссия " .. money(B.ForeignFee), 20, PW / 2, y0 + 336, Color(247, 198, 0), TEXT_ALIGN_CENTER, nil, "semibold") end
	elseif page == "fines" then
		T("Штрафы", 30, 28, y0, color_white, nil, nil, "bold")
		local fines = info.fines or {}
		if #fines == 0 then T("Неоплаченных штрафов нет", 26, PW / 2, y0 + 120, Color(120, 220, 140), TEXT_ALIGN_CENTER, nil, "semibold") end
		for i, f in ipairs(fines) do
			if i > 4 then break end
			local y = y0 + 44 + (i - 1) * 76
			box(28, y, PW - 56, 66, Color(255, 255, 255, 14), 10)
			T(f.reason ~= "" and f.reason or "Штраф", 24, 46, y + 10, color_white, nil, nil, "bold")
			T(NYRP.Phone and NYRP.Phone.DateText(f.day) or "", 18, 46, y + 38, Color(170, 175, 190), nil, nil, "medium")
			local hv = btn("pay" .. f.id, PW - 228, y + 10, 182, 46, function() op("fine", f.id) end)
			box(PW - 228, y + 10, 182, 46, hv and Color(60, 200, 100) or Color(40, 160, 80), 10)
			T("Оплатить " .. money(f.amount), 20, PW - 137, y + 33, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, "bold")
		end
		local hv = btn("back", 28, PW - 96, 200, 70, function() A.page = "main" end)
		box(28, PW - 96, 200, 70, hv and Color(255, 255, 255, 50) or Color(255, 255, 255, 18), 12)
		T("Назад", 26, 128, PW - 61, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, "bold")
	elseif page == "history" then
		T("История операций", 30, 28, y0, color_white, nil, nil, "bold")
		local log = info.log or {}
		if #log == 0 then T("Операций пока не было", 24, PW / 2, y0 + 120, Color(170, 175, 190), TEXT_ALIGN_CENTER, nil, "medium") end
		for i, l in ipairs(log) do
			if i > 6 then break end
			local y = y0 + 44 + (i - 1) * 52
			T(l.text, 22, 40, y, color_white, nil, nil, "semibold")
			T((NYRP.Phone and NYRP.Phone.DateText(l.day) or "") .. " " .. (l.time or ""), 16, 40, y + 26, Color(150, 155, 170), nil, nil, "medium")
			T((l.amount > 0 and "+" or "") .. money(l.amount), 24, PW - 40, y + 8, l.amount > 0 and Color(110, 220, 130) or color_white, TEXT_ALIGN_RIGHT, nil, "bold")
		end
		local hv = btn("back", 28, PW - 96, 200, 70, function() A.page = "main" end)
		box(28, PW - 96, 200, 70, hv and Color(255, 255, 255, 50) or Color(255, 255, 255, 18), 12)
		T("Назад", 26, 128, PW - 61, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, "bold")
	end
	-- сообщение банка
	local msg = (now() - A.msgT < 3.5) and A.msg or ""
	if msg ~= "" then
		local a = math.min(1, (3.5 - (now() - A.msgT)) * 3)
		box(60, PW - 180, PW - 120, 64, Color(20, 24, 36, 240 * a), 14)
		T(msg, 24, PW / 2, PW - 148, Color(255, 255, 255, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, "bold")
	end
end

function B.DrawScreen(ent)
	local bank = B.Banks[ent:GetBank()] or B.Banks.liberty
	local origin = ent:LocalToWorld(Vector(G.screenX + 0.02, -G.screenY, G.screenTop))
	local ang = ent:LocalToWorldAngles(Angle(0, 90, 90))
	local mine = A and A.ent == ent
	if not mine and EyePos():DistToSqr(ent:GetPos()) > 600 * 600 then return end
	if mine then
		btns = {}
		local mx, my = mouseOnScreen(ent)
		hovered = nil
		A.mouse = mx and { mx, my }
	end
	cam.Start3D2D(origin, ang, SCALE)
	render.PushFilterMag(TEXFILTER.ANISOTROPIC)
	render.PushFilterMin(TEXFILTER.ANISOTROPIC)
	if not mine then
		drawIdle(ent, bank, IsValid(ent:GetUser()))
	elseif A.stage == "insert" or A.stage == "take" then
		box(0, 0, PW, PW, Color(10, 12, 20), 0)
		header(bank)
		T(A.stage == "insert" and "Читаем карту…" or "Заберите карту", 40, PW / 2, PW / 2 + 80, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, "bold")
		T("Спасибо, что выбрали " .. bank.name, 22, PW / 2, PW / 2 + 130, Color(200, 205, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, "medium")
	elseif A.stage == "pin" then
		drawPin(B.Banks[A.bank] or bank)
	else
		drawMenu(B.Banks[A.bank] or bank, ent)
	end
	render.PopFilterMin()
	render.PopFilterMag()
	cam.End3D2D()
	if mine and A.mouse then
		-- наведение решаем после того, как кнопки зарегистрированы
		for i = #btns, 1, -1 do
			local b = btns[i]
			if A.mouse[1] >= b.x and A.mouse[1] <= b.x + b.w and A.mouse[2] >= b.y and A.mouse[2] <= b.y + b.h then
				if A.lastHover ~= b.id then A.lastHover = b.id surface.PlaySound("nyrp/phone/key.wav") end
				hovered = b.id
				break
			end
		end
	end
end

-- подтверждение суммы
confirmAmount = function()
	if not A then return end
	local n = tonumber(A.amount)
	if not n or n <= 0 then A.msg, A.msgT = "Введите сумму", now() return end
	op(A.mode, n)
end

-- во время сеанса не рисуем лишний HUD
hook.Add("HUDShouldDraw", "nyrp.atm", function(name)
	if A and (name == "CHudCrosshair" or name == "CHudWeaponSelection") then return false end
end)

function B.ATMActive() return A ~= nil end
