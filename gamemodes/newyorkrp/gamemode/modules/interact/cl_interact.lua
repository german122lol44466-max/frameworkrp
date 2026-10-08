--[[
	Подсказки взаимодействия: при приближении к двери, предмету или энтити появляется
	белый кружок с чёрной иконкой прямо «в мире» (у двери — на ручке), при наведении —
	крупнее, с подписью («Открыть дверь», «Взять ...», «Взаимодействовать с ...») и обводкой.
]]

local UI = NYRP.UI
NYRP.Interact = NYRP.Interact or {}
local I = NYRP.Interact

local doorClasses = { prop_door_rotating = true, func_door = true, func_door_rotating = true }
local states = {}
local scanAt = 0

-- Другие игроки: значок «E» на груди, по E — круговое меню (cl_player.lua).
local function playerTarget(ent)
	return ent:IsPlayer() and ent ~= LocalPlayer() and ent:Alive() and not ent:GetNoDraw() and NYRP.HasCharacter(ent)
		and not (NYRP.Cond and NYRP.Cond.KO(ent))
end
I.IsPlayerTarget = playerTarget

-- Тело: без сознания или труп — меню тела (cl_body.lua).
local function isBody(ent)
	if not ent:IsRagdoll() then return false end
	return ent:GetNW2Bool("nyrp.corpse") or IsValid(ent:GetNW2Entity("nyrp.koOwner"))
end
I.IsBody = isBody

function I.IsInteractable(ent)
	if not IsValid(ent) then return false end
	if ent:IsPlayer() then return playerTarget(ent) end
	if isBody(ent) then return ent:GetNW2Entity("nyrp.koOwner") ~= LocalPlayer() end
	if doorClasses[ent:GetClass()] then return true end
	return ent.NYRPInteract == true
end

local function info(ent)
	if ent:IsPlayer() then return "E", "Взаимодействовать" end
	if isBody(ent) then return "E", "Осмотреть тело" end
	if doorClasses[ent:GetClass()] then return "door", "Открыть дверь" end
	local text = ent.GetInteractText and ent:GetInteractText() or ("Взаимодействовать с: " .. (ent.PrintName or ent:GetClass()))
	return ent.NYRPIcon or "interact", text
end

-- Точка иконки: у двери — ручка, у остальных — центр чуть выше.
local function anchor(ent)
	local ply = LocalPlayer()
	if ent:IsPlayer() or ent:IsRagdoll() then
		local b = ent:LookupBone("ValveBiped.Bip01_Spine2")
		local p = b and ent:GetBonePosition(b)
		return (p or ent:WorldSpaceCenter()) + ent:GetForward() * 6
	end
	if ent:GetClass() == "prop_door_rotating" then
		local mn, mx = ent:OBBMins(), ent:OBBMaxs()
		local ext = mx - mn
		local axis = ext.y >= ext.x and "y" or "x"
		local thick = axis == "y" and "x" or "y"
		local far = math.abs(mx[axis]) > math.abs(mn[axis]) and mx[axis] - 5 or mn[axis] + 5
		local localPos = Vector(0, 0, mn.z + ext.z * 0.42)
		localPos[axis] = far
		local side = ent:WorldToLocal(ply:EyePos())[thick] > (mn[thick] + mx[thick]) / 2 and 1 or -1
		localPos[thick] = (mn[thick] + mx[thick]) / 2 + side * (ext[thick] / 2 + 1.5)
		return ent:LocalToWorld(localPos)
	end
	if doorClasses[ent:GetClass()] then
		local c = ent:LocalToWorld(ent:OBBCenter())
		local toPly = (ply:EyePos() - c):GetNormalized()
		return c + toPly * 4
	end
	local c = ent:LocalToWorld(ent:OBBCenter())
	return c + Vector(0, 0, math.min(ent:OBBMaxs().z - ent:OBBCenter().z, 30) + 4)
end

I.Anchor = anchor

-- Цель — то, на что смотрит луч, или ближайшая к центру экрана иконка в небольшом конусе.
local CONE = math.cos(math.rad(11))

hook.Add("Think", "nyrp.interact", function()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	I.Target = nil
	if NYRP.State ~= "playing" or not ply:Alive() then return end

	local eye, aim = ply:EyePos(), ply:GetAimVector()
	local range = NYRP.Config.Ranges.Interact
	local tr = util.TraceLine({ start = eye, endpos = eye + aim * range, filter = ply })

	if RealTime() > scanAt then
		scanAt = RealTime() + 0.15
		for _, ent in ipairs(ents.FindInSphere(eye, NYRP.Config.Ranges.Hint)) do
			if I.IsInteractable(ent) then
				local st = states[ent] or { a = 0, t = 0 }
				states[ent] = st
				local pos = anchor(ent)
				local vis = util.TraceLine({ start = eye, endpos = pos, filter = { ply, ent }, mask = MASK_VISIBLE }).Fraction > 0.97
				st.visible = vis and (pos - eye):GetNormalized():Dot(aim) > 0.3
				st.seen = RealTime()
			end
		end
	end

	local best, bestDot
	if I.IsInteractable(tr.Entity) then best, bestDot = tr.Entity, 2 end
	for ent, st in pairs(states) do
		if IsValid(ent) and st.visible and ent ~= best then
			local pos = anchor(ent)
			local to = pos - eye
			local dist = to:Length()
			local dot = to:GetNormalized():Dot(aim)
			if dist <= range + 25 and dot > CONE and (not bestDot or dot > bestDot) then best, bestDot = ent, dot end
		end
	end
	I.Target = best
	I.TraceHit = best ~= nil and tr.Entity == best

	for ent, st in pairs(states) do
		if not IsValid(ent) then states[ent] = nil
		else
			local inRange = RealTime() - st.seen < 0.3 and st.visible
			st.a = UI.Approach(st.a, inRange and 1 or 0, 8)
			st.t = UI.Approach(st.t, ent == I.Target and 1 or 0, 12)
			if st.a < 0.01 and not inRange then states[ent] = nil end
		end
	end
end)

-- Экранная точка цели — к ней «тянется» прицел.
function I.TargetScreenPos()
	if not IsValid(I.Target) then return end
	local sc = anchor(I.Target):ToScreen()
	if sc.visible then return sc.x, sc.y end
end

-- E по цели, даже если луч прошёл чуть мимо: просим сервер нажать за нас.
hook.Add("PlayerBindPress", "nyrp.interact", function(ply, bind, pressed)
	if not pressed or not string.find(bind, "+use", 1, true) then return end
	-- открыт диалог или круговое меню — E обрабатывают они
	if (NYRP.NPC and NYRP.NPC.InDialog and NYRP.NPC.InDialog()) or (NYRP.WorldRadial and NYRP.WorldRadial.IsOpen()) then return end
	if IsValid(I.Target) and I.Target:IsPlayer() then
		if I.OpenPlayerMenu then I.OpenPlayerMenu(I.Target) end
		return true
	end
	if IsValid(I.Target) and isBody(I.Target) then
		if I.OpenBodyMenu then I.OpenBodyMenu(I.Target) end
		return true
	end
	if IsValid(I.Target) and not I.TraceHit then
		net.Start("nyrp.interact.use")
		net.WriteEntity(I.Target)
		net.SendToServer()
		return true
	end
end)

hook.Add("PreDrawHalos", "nyrp.interact", function()
	if IsValid(I.Target) and NYRP.State == "playing" then
		halo.Add({ I.Target }, Color(255, 255, 255, 200), 2, 2, 1, true, false)
	end
end)

hook.Add("HUDPaint", "nyrp.interact", function()
	if NYRP.HUDHidden() then return end
	if NYRP.Inventory and NYRP.Inventory.IsOpen and NYRP.Inventory.IsOpen() then return end
	local eye = LocalPlayer():EyePos()
	for ent, st in pairs(states) do
		if IsValid(ent) and st.a > 0.01 then
			local pos = anchor(ent)
			local sc = pos:ToScreen()
			if sc.visible then
				local dist = eye:Distance(pos)
				local k = math.Clamp(1 - dist / NYRP.Config.Ranges.Hint, 0.45, 1)
				local pop = UI.Ease(st.a)
				local r = (UI.S(11) + st.t * UI.S(8)) * k * (0.6 + 0.4 * pop)
				local icon, text = info(ent)
				local a = st.a * (0.9 + st.t * 0.1) -- иконки почти непрозрачные — их хорошо видно
				UI.Circle(sc.x, sc.y + UI.S(2), r + UI.S(3), Color(0, 0, 0, 70 * a))
				UI.Circle(sc.x, sc.y, r, Color(255, 255, 255, 245 * a))
				if icon == "E" then
					draw.SimpleText("E", NYRP.Font("bold", r > UI.S(15) and 22 or 15), sc.x, sc.y, Color(12, 14, 20, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				else
					UI.DrawIcon(icon, sc.x, sc.y, r * 1.15, Color(12, 14, 20, 255 * a))
				end
				if st.t > 0.02 then
					local ta = st.t * st.a
					local font = NYRP.Font("semibold", 17)
					local ty = sc.y + r + UI.S(10) + (1 - st.t) * UI.S(6)
					draw.SimpleText(text, font, sc.x + 1, ty + 2, Color(0, 0, 0, 160 * ta), TEXT_ALIGN_CENTER)
					draw.SimpleText(text, font, sc.x, ty, Color(255, 255, 255, 255 * ta), TEXT_ALIGN_CENTER)
					local key = string.upper(input.LookupBinding("+use") or "E")
					local kw = UI.TextSize(key, NYRP.Font("bold", 13)) + UI.S(12)
					local tw = UI.TextSize(text, font)
					UI.RoundedRect(UI.S(4), sc.x - tw / 2 - kw - UI.S(8), ty + UI.S(1), kw, UI.S(20), Color(255, 255, 255, 230 * ta))
					draw.SimpleText(key, NYRP.Font("bold", 13), sc.x - tw / 2 - kw / 2 - UI.S(8), ty + UI.S(11), Color(10, 12, 18, 255 * ta), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
			end
		end
	end
end)
