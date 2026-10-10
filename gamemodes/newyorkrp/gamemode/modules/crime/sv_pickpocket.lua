--[[
	Карманная кража (сервер). Начинается из кругового меню игрока («Обчистить карманы», только со спины).
	  4 секунды вор шарит по карманам — каждые 0.2 с проверяем: жертва не обернулась, не отошла, вор рядом.
	  Итог решает бросок: 40% + 5% за уровень «Ловкости» (макс. 92%), минус 15%, если жертва идёт.
	  Успех: 10–30% наличных (не больше $300) или случайная вещь из сумки; жертва узнаёт о пропаже через 30–90 с.
	  Провал: жертва сразу получает «Вас пытались обокрасть» с приметами вора, с шансом 35% — вызов полиции.
	Кулдауны: вор — 90 с между попытками, одного и того же человека — раз в 10 минут.
]]

NYRP.Crime = NYRP.Crime or {}
local C = NYRP.Crime

local active = {}   -- [вор] = { victim, start, startPos, victimPos }

local function charId(ply) return ply.nyrpChar and ply.nyrpChar.id end

-- Приметы вора глазами жертвы: имя, если знакомы, иначе пол, рост, маска и описание внешности.
function C.Describe(victim, thief)
	local tid = thief:GetNW2Int("nyrp.charID", 0)
	local masked = thief:GetNW2Bool("nyrp.masked")
	if not masked and victim.nyrpRecog and victim.nyrpRecog[tid] then
		return NYRP.CharName(thief)
	end
	local female = thief:GetNW2String("nyrp.gender", "male") == "female"
	local parts = { female and "женщина" or "мужчина" }
	local h = thief.nyrpChar and tonumber(thief.nyrpChar.height)
	if h then parts[#parts + 1] = h >= 185 and "высокого роста" or (h <= 165 and "невысокого роста" or "среднего роста") end
	if masked then parts[#parts + 1] = "лицо скрыто" end
	local desc = thief:GetNW2String("nyrp.desc", "")
	if desc ~= "" and not masked then
		desc = string.gsub(desc, "[\r\n]+", " ")
		if utf8 and utf8.len(desc) and utf8.len(desc) > 60 then desc = string.sub(desc, 1, utf8.offset(desc, 61) - 1) .. "…" end
		parts[#parts + 1] = "«" .. desc .. "»"
	end
	return table.concat(parts, ", ")
end

local function setState(thief, victim, on)
	net.Start("nyrp.crime.pickState")
	net.WriteBool(on)
	net.WriteEntity(victim or NULL)
	net.WriteFloat(C.Pick.Time)
	net.Send(thief)
end

local function stop(thief)
	local s = active[thief]
	active[thief] = nil
	if IsValid(thief) then
		NYRP.CancelAction(thief)
		setState(thief, s and s.victim, false)
	end
end

local function policeCall(pos, why)
	if NYRP.E911 and NYRP.E911.Auto then NYRP.E911.Auto("police", pos, why) end
end

-- провал: жертва заметила (или неудачный бросок)
local function fail(thief, victim, why)
	stop(thief)
	if not IsValid(thief) then return end
	NYRP.Notify(thief, why or "Не вышло — человек почувствовал руку в кармане", "error", 5)
	NYRP.Skills.AddXP(thief, "agility", 4, "попытка кражи")
	if not IsValid(victim) then return end
	victim:EmitSound("physics/body/body_medium_impact_soft" .. math.random(1, 7) .. ".wav", 60)
	NYRP.Notify(victim, "Вас пытались обокрасть! Вор: " .. C.Describe(victim, thief), "error", 12)
	if math.random() < C.Pick.PoliceChance then
		policeCall(victim:GetPos(), "Попытка карманной кражи")
		NYRP.Notify(thief, "Кто-то из прохожих звонит в 911 — уходите!", "warning", 6)
	end
end

-- что можно стащить из сумки
local function stealableSlots(victim)
	local inv = NYRP.Inv.Get(victim)
	local keys = {}
	for k, it in pairs(inv.slots) do
		local def = NYRP.Items.Get(it.id)
		if def and not def.noDrop and it.id ~= "idcard" then keys[#keys + 1] = k end
	end
	return keys
end

local function success(thief, victim)
	stop(thief)
	local cash = NYRP.Money.Get(victim)
	local slots = stealableSlots(victim)
	local takeItem = (#slots > 0) and (cash < 10 or math.random() < 0.3)
	local loss
	if takeItem then
		local slot = slots[math.random(#slots)]
		local it = NYRP.Inv.Get(victim).slots[slot]
		local def = NYRP.Items.Get(it.id)
		local data = it.n <= 1 and table.Copy(it.data or {}) or nil
		if NYRP.Inv.Add(thief, it.id, 1, data) <= 0 then
			NYRP.Notify(thief, "Нащупали «" .. def.name .. "», но в сумке нет места — пришлось оставить", "warning", 6)
			return
		end
		NYRP.Inv.Take(victim, slot, 1)
		loss = "Пропала вещь: " .. def.name
		NYRP.Notify(thief, "Вы незаметно вытащили: " .. def.name, "success", 5)
	else
		local pct = C.Pick.MinPct + math.random() * (C.Pick.MaxPct - C.Pick.MinPct)
		local n = math.min(math.floor(cash * pct), C.Pick.MaxCash)
		if n <= 0 then
			NYRP.Notify(thief, "Карманы пусты — ни денег, ни вещей", "warning", 5)
			NYRP.Skills.AddXP(thief, "agility", 6, "чистая работа")
			return
		end
		NYRP.Money.Add(victim, -n)
		NYRP.Money.Add(thief, n)
		thief:EmitSound("nyrp/fx/money.wav", 40)
		loss = "У вас пропали деньги: " .. NYRP.Money.Format(n)
		NYRP.Notify(thief, "Вы незаметно вытащили " .. NYRP.Money.Format(n), "success", 5)
	end
	NYRP.Skills.AddXP(thief, "agility", 15, "карманная кража")
	hook.Run("NYRP.Pickpocketed", thief, victim, loss)
	-- жертва замечает пропажу не сразу
	timer.Simple(math.random(30, 90), function()
		if IsValid(victim) then NYRP.Notify(victim, loss .. ". Похоже, вас обокрали.", "warning", 10) end
	end)
end

local function chance(thief, victim)
	local lvl = NYRP.Skills.Level(thief, "agility") or 0
	local p = 0.40 + lvl * 0.05
	if victim:GetVelocity():Length2D() > 60 then p = p - 0.15 end
	if victim:GetNW2String("nyrp.role", "") == "police" then p = p - 0.10 end
	return math.Clamp(p, 0.1, 0.92)
end

net.Receive("nyrp.crime.pick", function(_, thief)
	if (thief.nyrpPickNet or 0) > CurTime() then return end
	thief.nyrpPickNet = CurTime() + 1
	local victim = net.ReadEntity()
	if not NYRP.HasCharacter(thief) or not thief:Alive() or active[thief] then return end
	local ok, why = C.CanPickTarget(thief, victim)
	if not ok then NYRP.Notify(thief, why, "warning") return end
	if NYRP.Factions and NYRP.Factions.Cuffed and NYRP.Factions.Cuffed(thief) then return end
	if not C.IsBehind(victim, thief) then
		NYRP.Notify(thief, "Человек смотрит на вас — зайдите со спины", "warning", 4)
		return
	end
	local c = thief.nyrpChar
	c.flags = c.flags or {}
	local left = (c.flags.pickNext or 0) - os.time()
	if left > 0 then NYRP.Notify(thief, "Слишком рискованно — переждите ещё " .. left .. " с", "warning", 4) return end
	local vid = tostring(charId(victim) or 0)
	thief.nyrpPickVictims = thief.nyrpPickVictims or {}
	if (thief.nyrpPickVictims[vid] or 0) > CurTime() then
		NYRP.Notify(thief, "Этот человек уже настороже — найдите другую цель", "warning", 4)
		return
	end
	c.flags.pickNext = os.time() + C.Pick.Cooldown
	thief.nyrpPickVictims[vid] = CurTime() + C.Pick.VictimCooldown

	local started = NYRP.Action(thief, "Шарю по чужим карманам...", C.Pick.Time, function()
		local s = active[thief]
		if not s or not IsValid(victim) or not victim:Alive() then stop(thief) return end
		if math.random() < chance(thief, victim) then success(thief, victim) else fail(thief, victim) end
	end, "hand")
	if not started then return end
	active[thief] = { victim = victim, start = CurTime(), thiefPos = thief:GetPos() }
	setState(thief, victim, true)
end)

-- слежение за кражей: обернулся / отошёл / вор ушёл — провал
timer.Create("nyrp.crime.pick", 0.2, 0, function()
	for thief, s in pairs(active) do
		local victim = s.victim
		if not IsValid(thief) then
			active[thief] = nil
		elseif not thief:Alive() or not IsValid(victim) or not victim:Alive() then
			stop(thief)
		elseif thief:GetPos():Distance(victim:GetPos()) > C.Pick.BreakRange then
			fail(thief, victim, "Человек отошёл и заметил чужую руку")
		elseif CurTime() - s.start > 0.4 and C.ViewAngle(victim, thief) < C.Pick.NoticeAngle then
			fail(thief, victim, "Человек обернулся и заметил вас!")
		elseif thief:GetPos():Distance(s.thiefPos) > 60 then
			stop(thief)
			NYRP.Notify(thief, "Вы отошли — кража сорвалась", "warning", 4)
		end
	end
end)

hook.Add("PlayerDisconnected", "nyrp.crime.pick", function(ply) active[ply] = nil end)
hook.Add("PlayerDeath", "nyrp.crime.pick", function(ply) if active[ply] then stop(ply) end end)
