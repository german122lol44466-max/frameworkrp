--[[
	Клиент: полоска выносливости и иконки состояний справа сверху, подсказка при наведении
	(когда открыт чат — курсор свободен), эффекты экрана и звуки:
	  - выдохся после долгого бега: размытие, тяжёлое дыхание и сердцебиение — проходят, если постоять;
	  - меньше 50 HP: кровь по краям экрана, головокружение, сердцебиение громче с каждой потерей.
]]

local UI = NYRP.UI
local Cond = NYRP.Cond
Cond.HUDHeight = 0

local COL = {
	info = Color(110, 170, 225),
	warn = Color(214, 178, 140),
	danger = Color(220, 74, 66),
	bar = Color(214, 178, 140),
	barLow = Color(220, 96, 70),
	track = Color(90, 62, 40, 170),
}

local function statusMat(name) return UI.Mat("nyrp/status/" .. name .. ".png") end

local function drawIcon(mat, x, y, size, col)
	surface.SetMaterial(mat)
	surface.SetDrawColor(0, 0, 0, col.a * 0.55)
	surface.DrawTexturedRect(x - size / 2 + 1, y - size / 2 + 2, size, size)
	surface.SetDrawColor(col)
	surface.DrawTexturedRect(x - size / 2, y - size / 2, size, size)
end

-- ------------------------------------------------------------------- HUD --
local barAlpha, barFull, shown = 0, 0, 0
local slots = {}      -- [id] = { a = видимость, x = текущая позиция, pop = «выпрыгивание» }
local hoverId, tipA, tipFor = nil, 0, nil

local function levelOf(st, ply)
	if st.danger and st.danger(ply) then return "danger" end
	return st.level
end

hook.Add("HUDPaint", "nyrp.condition", function()
	local ply = LocalPlayer()
	if NYRP.HUDHidden() or not IsValid(ply) or not ply:Alive() or Cond.KO(ply) then
		Cond.HUDHeight = UI.Approach(Cond.HUDHeight, 0, 10)
		return
	end
	local right, top = ScrW() - UI.S(24), UI.S(22)

	-- полоска выносливости: видна, пока не полная
	local st = Cond.Stamina(ply)
	local tired = Cond.Exhausted(ply)
	if st >= 99.9 and not tired then barFull = barFull + FrameTime() else barFull = 0 end
	barAlpha = UI.Approach(barAlpha, barFull < 1.5 and 1 or 0, 8)
	shown = UI.Approach(shown, st / 100, 12)
	-- полоска выносливости — внизу по центру, жёлтая
	if barAlpha > 0.01 then
		surface.SetAlphaMultiplier(barAlpha)
		local bw, bh = UI.S(300), UI.S(5)
		local bx = ScrW() / 2 - bw / 2
		local by = ScrH() - UI.S(52) + (1 - UI.Ease(barAlpha)) * UI.S(10)
		local yellow = UI.Col.accent
		local col = tired and COL.barLow or UI.LerpColor(math.Clamp((st - 10) / 25, 0, 1), COL.barLow, yellow)
		drawIcon(statusMat("stamina"), bx - UI.S(20), by + bh / 2, UI.S(22), col)
		UI.RoundedRect(bh / 2, bx, by, bw, bh, Color(0, 0, 0, 140))
		UI.RoundedRect(bh / 2, bx, by, bw, bh, Color(247, 198, 0, 22))
		if shown > 0.005 then
			UI.RoundedRect(bh / 2, bx, by, math.max(bw * shown, bh), bh, col)
			UI.Glow(bx + bw * shown, by + bh / 2, UI.S(26), UI.S(16), UI.Alpha(col, 90))
		end
		surface.SetAlphaMultiplier(1)
	end
	local y = top

	-- иконки состояний (справа налево), с анимацией появления и ухода
	local size, gap = UI.S(30), UI.S(12)
	local x = right
	local any = false
	local mx, my = gui.MousePos()
	local canHover = vgui.CursorVisible() or NYRP.ScreenClicker
	local newHover
	for _, def in ipairs(Cond.Statuses) do
		local on = def.check(ply)
		local s = slots[def.id]
		if on and not s then
			s = { a = 0, x = x - size / 2, pop = 1 }
			slots[def.id] = s
			if def.level == "danger" then UI.Sound("warning") end
		end
		if s then
			s.a = UI.Approach(s.a, on and 1 or 0, on and 10 or 8)
			s.pop = UI.Approach(s.pop, 0, 6)
			if not on and s.a < 0.02 then
				slots[def.id] = nil
			else
				local cx = x - size / 2
				s.x = UI.Approach(s.x, cx, 12)
				local cy = y + UI.S(14)
				local lvl = levelOf(def, ply)
				local col = UI.Alpha(COL[lvl], 255 * s.a)
				local sz = size * (0.6 + 0.4 * UI.Ease(s.a)) * (1 + s.pop * 0.25)
				if lvl == "danger" then
					-- опасные слегка пульсируют
					local p = (math.sin(RealTime() * 5) + 1) / 2
					UI.Glow(s.x, cy, sz * 2.2, sz * 2.2, UI.Alpha(COL.danger, 40 * p * s.a))
				end
				drawIcon(statusMat(def.icon), s.x + (1 - s.a) * UI.S(30), cy, sz, col)
				if canHover and on and math.abs(mx - s.x) <= size / 2 + 4 and math.abs(my - cy) <= size / 2 + 4 then
					newHover = def
				end
				if on then x = x - size - gap any = true end
			end
		end
	end
	local h = any and UI.S(48) or 0
	Cond.HUDHeight = UI.Approach(Cond.HUDHeight, h, 10)

	-- подсказка при наведении
	if newHover then hoverId, tipFor = newHover.id, newHover end
	tipA = UI.Approach(tipA, newHover and 1 or 0, newHover and 14 or 10)
	if tipA > 0.01 and tipFor and slots[tipFor.id] then
		local def = tipFor
		local s = slots[def.id]
		local lvl = levelOf(def, ply)
		local w = UI.S(300)
		local lines = UI.Wrap(def.desc, NYRP.Font("regular", 14), w - UI.S(32))
		local th = UI.S(76) + #lines * UI.S(18)
		local tx = math.min(s.x - w / 2, right - w)
		local ty = y + UI.S(38) + (1 - UI.Ease(tipA)) * UI.S(8)
		surface.SetAlphaMultiplier(tipA)
		UI.BlurRect(tx, ty, w, th, 4)
		UI.RoundedRect(UI.S(12), tx, ty, w, th, Color(10, 11, 16, 236))
		UI.Outline(UI.S(12), tx, ty, w, th, UI.Alpha(COL[lvl], 70), 1)
		UI.RoundedRect(UI.S(2), tx + UI.S(16), ty, UI.S(40), UI.S(3), COL[lvl])
		UI.Circle(tx + UI.S(34), ty + UI.S(36), UI.S(18), UI.Alpha(COL[lvl], 34))
		drawIcon(statusMat(def.icon), tx + UI.S(34), ty + UI.S(36), UI.S(22), COL[lvl])
		draw.SimpleText(def.name, NYRP.Font("bold", 17), tx + UI.S(62), ty + UI.S(28), UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		if def.value then
			draw.SimpleText(def.value(ply), NYRP.Font("medium", 13), tx + UI.S(62), ty + UI.S(47), COL[lvl], TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		for i, l in ipairs(lines) do
			draw.SimpleText(l, NYRP.Font("regular", 14), tx + UI.S(16), ty + UI.S(64) + (i - 1) * UI.S(18), UI.Col.dim)
		end
		surface.SetAlphaMultiplier(1)
	end
end)

-- ------------------------------------------------------- эффекты и звуки --
local fatigue, wound = 0, 0
local breath, heart

local function loopSound(snd, path)
	local ply = LocalPlayer()
	if snd and snd:IsPlaying() then return snd end
	snd = CreateSound(ply, path)
	snd:SetSoundLevel(0)
	snd:PlayEx(0, 100)
	return snd
end

hook.Add("Think", "nyrp.condition.fx", function()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local alive = ply:Alive() and NYRP.State == "playing"
	local st = Cond.Stamina(ply)
	-- выдохся: эффекты держатся, пока выносливость не восстановится (стоя — быстро, на ходу — медленно)
	local wantF = alive and (Cond.Exhausted(ply) and 1 or math.Clamp((30 - st) / 30, 0, 1)) or 0
	fatigue = UI.Approach(fatigue, wantF, wantF > fatigue and 2 or 0.8)
	local hp = ply:Health()
	local wantW = alive and math.Clamp((50 - hp) / 45, 0, 1) or 0
	if Cond.KO(ply) then wantW = math.max(wantW, ply:GetNW2Bool("nyrp.koCritical") and 0.85 or 0.3) end
	wound = UI.Approach(wound, wantW, 3)

	local conc = alive and math.Clamp(Cond.Until(ply, "concussion") / 20, 0, 1) or 0
	NYRP.Camera.Dizzy = math.max(wound * 0.9, conc * 0.7, fatigue * 0.25)

	-- дыхание после бега
	if fatigue > 0.01 then
		breath = loopSound(breath, "nyrp/fx/breath_run.wav")
		breath:ChangeVolume(math.min(fatigue, 1) * 0.75, 0.1)
		breath:ChangePitch(ply:GetNW2String("nyrp.gender", "") == "female" and 112 or 100, 0)
	elseif breath then
		breath:Stop()
		breath = nil
	end
	-- сердцебиение: после бега и при ранении (чем меньше здоровья — тем громче)
	local hv = math.max(fatigue * 0.55, wound * 0.95)
	if hv > 0.01 then
		heart = loopSound(heart, "nyrp/fx/heartbeat_loop.wav")
		heart:ChangeVolume(hv, 0.2)
		-- спокойный ~95 уд/мин при ранении, быстрый — после бега
		heart:ChangePitch(math.Round(Lerp(fatigue / math.max(fatigue + wound, 0.001), 82 + wound * 12, 100)), 0.3)
	elseif heart then
		heart:Stop()
		heart = nil
	end
end)

hook.Add("HUDPaintBackground", "nyrp.condition.fx", function()
	local w, h = ScrW(), ScrH()
	if fatigue > 0.01 then
		local p = (math.sin(RealTime() * 3.2) + 1) / 2
		UI.BlurRect(0, 0, w, h, 2.5 * fatigue + p * 1.2 * fatigue)
		UI.Vignette(-UI.S(10), -UI.S(10), w + UI.S(20), h + UI.S(20), 140 * fatigue)
	end
	if wound > 0.01 then
		-- кровь «пульсирует» в такт сердцу
		local beat = math.max(0, math.sin(RealTime() * math.pi * 2 * (1.3 + wound * 0.5))) ^ 6
		local a = (150 + 90 * beat) * wound
		local grow = UI.S(30) * (1 - wound)
		surface.SetMaterial(UI.Mat("nyrp/ui/blood_edges.png"))
		surface.SetDrawColor(255, 255, 255, math.min(a, 255))
		surface.DrawTexturedRect(-grow, -grow, w + grow * 2, h + grow * 2)
	end
end)

hook.Add("RenderScreenspaceEffects", "nyrp.condition.fx", function()
	if wound <= 0.01 and fatigue <= 0.01 then return end
	DrawColorModify({
		["$pp_colour_addr"] = 0.02 * wound, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
		["$pp_colour_brightness"] = -0.03 * wound, ["$pp_colour_contrast"] = 1 + 0.06 * wound,
		["$pp_colour_colour"] = 1 - 0.45 * wound - 0.1 * fatigue,
		["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
	})
	if wound > 0.3 then DrawMotionBlur(0.2, 0.35 * wound, 0.01) end
end)
