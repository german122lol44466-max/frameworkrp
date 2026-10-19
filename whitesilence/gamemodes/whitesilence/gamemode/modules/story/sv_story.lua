--[[
	Сюжет на сервере — одна общая операция для всех отрядов.

	Первый отряд, вышедший в игру, запускает текущую главу. Погибшие возвращаются в меню и могут снова
	выдвинуться — появятся рядом с живыми товарищами. Если погибли все — через StoryWipeDelay секунд глава
	откатывается к началу и ждёт, пока кто-нибудь выдвинется. После финала все возвращаются в меню, операция
	начинается заново.
]]

local S = WS.Story
local C = WS.Config
local L = WS.Lobby
local P = S.P

for _, n in ipairs({ "ws.story.state", "ws.story.line", "ws.story.chapter", "ws.story.finish", "ws.story.boom", "ws.story.checkpoint", "ws.story.cutscene", "ws.story.briefing" }) do
	util.AddNetworkString(n)
end

S.State = { ch = 1, step = 0, running = false }
S.Enemies = {}      -- [ent] = метка шага
S.Props = {}
S.Stats = { t0 = 0, kills = 0, deaths = 0 }

local cur           -- текущий шаг: { def, t0, ... }
local queue, queueEnd = {}, 0
local dirty, lastSend = true, 0

-- ---------------------------------------------------------------- игроки

local function fighters()
	local out = {}
	for _, p in ipairs(player.GetAll()) do
		if L.InGame(p) and p:Alive() then out[#out + 1] = p end
	end
	return out
end

local function inGame()
	local out = {}
	for _, p in ipairs(player.GetAll()) do
		if L.InGame(p) then out[#out + 1] = p end
	end
	return out
end
S.Fighters = fighters

local function nearest(pos)
	local best, bd = nil, math.huge
	for _, p in ipairs(fighters()) do
		local d = p:GetPos():DistToSqr(pos)
		if d < bd then best, bd = p, d end
	end
	return best, math.sqrt(bd)
end

-- ---------------------------------------------------------------- реплики

-- Реплики идут строго друг за другом: следующая — после окончания предыдущей
function S.Say(lines)
	if not lines then return end
	local t = math.max(CurTime(), queueEnd)
	for _, id in ipairs(lines) do
		if S.Lines[id] then
			queue[#queue + 1] = { id = id, at = t }
			t = t + S.LineTime(id) + 0.6
		end
	end
	queueEnd = t
end

local function sayThink()
	local now = CurTime()
	while queue[1] and queue[1].at <= now do
		local q = table.remove(queue, 1)
		net.Start("ws.story.line")
		net.WriteString(q.id)
		net.Send(inGame())
	end
end

function S.Talking() return queueEnd > CurTime() end
function S.Current() return cur end

-- ---------------------------------------------------------------- враги и предметы

function S.CountEnemies(tag)
	local n = 0
	for e, t in pairs(S.Enemies) do
		if not IsValid(e) or e:Health() <= 0 then S.Enemies[e] = nil
		elseif tag == nil or t == tag then n = n + 1 end
	end
	return n
end

local function playerNear(pos, dist)
	for _, p in ipairs(fighters()) do
		if p:GetPos():DistToSqr(pos) < dist * dist then return true end
	end
	return false
end

-- Место появления: точки группы из редактора, иначе — вокруг цели, подальше от игроков
local function spawnSpot(gid, center, i)
	local spots = P.GroupSpots(gid)
	if #spots > 0 then
		local s = spots[(i - 1) % #spots + 1]
		local pos = s.pos
		if i > #spots then
			pos = P.AutoNear(s.pos, 40, 140)
		end
		return pos, s.yaw
	end
	for _ = 1, 8 do
		local pos = P.AutoNear(center, 900, 1600)
		if not playerNear(pos, 800) then return pos, math.random(0, 359) end
	end
	return P.AutoNear(center, 600, 1200), math.random(0, 359)
end

function S.Spawn(gid, count, mode, goal, tag)
	local g = S.GroupById[gid]
	local center = goal or (g and P.Get(g.near)) or P.MapOrigin()
	count = count + math.floor(math.max(#fighters() - 1, 0) * 0.6)   -- больше игроков — больше врагов
	local made = {}
	for i = 1, count do
		if S.CountEnemies() >= C.EnemyMaxAlive then break end
		local pos, yaw = spawnSpot(gid, center, i)
		local e = ents.Create("ws_enemy")
		if not IsValid(e) then break end
		e:SetPos(pos + Vector(0, 0, 4))
		e:SetAngles(Angle(0, yaw or 0, 0))
		e.wsMode = mode or "guard"
		e.wsGoal = goal or center
		e.wsSpots = P.GroupSpots(gid)
		e:Spawn()
		S.Enemies[e] = tag or true
		made[#made + 1] = e
	end
	return made
end

function S.ClearEnemies()
	for e in pairs(S.Enemies) do if IsValid(e) then e:Remove() end end
	S.Enemies = {}
end

local function clearProps()
	for _, e in ipairs(S.Props) do if IsValid(e) then e:Remove() end end
	S.Props = {}
end

local function placeProp(pid, model)
	local pos, yaw = P.Get(pid)
	local e
	if model == "body" then
		e = ents.Create("prop_ragdoll")
		e:SetModel(util.IsValidModel(C.SquadModel) and C.SquadModel or C.SquadModelFallback)
		e:SetPos(pos + Vector(0, 0, 12))
		e:SetAngles(Angle(0, yaw, 0))
		e:Spawn()
		e:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
		util.Decal("Blood", pos + Vector(0, 0, 8), pos - Vector(0, 0, 40))
		-- тело лежит, раскинув руки — не «манекеном»
		for b = 0, e:GetPhysicsObjectCount() - 1 do
			local ph = e:GetPhysicsObjectNum(b)
			if IsValid(ph) then ph:SetVelocity(VectorRand() * 40) end
		end
	elseif WS.Props.Defs[model] then
		e = ents.Create("ws_prop")
		e:SetMeshId(model)
		e.wsStatic = true
		e:SetPos(pos)
		e:SetAngles(Angle(0, yaw, 0))
		e:Spawn()
	else
		if not util.IsValidModel(model) then return end
		e = ents.Create("prop_dynamic")
		e:SetModel(model)
		e:SetPos(pos)
		e:SetAngles(Angle(0, yaw, 0))
		e:SetKeyValue("solid", "6")
		e:Spawn()
	end
	e.wsPoint = pid
	S.Props[#S.Props + 1] = e
	return e
end

-- ---------------------------------------------------------------- состояние для клиентов

local function chapter() return S.Chapters[S.State.ch] end

local function markersOf(step)
	local m = {}
	if not step then return m end
	local d = step.def
	if d.type == "goto" or d.type == "hold" then
		local pos, _, r = P.Get(d.point)
		m[1] = { pos = pos, kind = d.marker or "goto", label = d.type == "hold" and "Удерживать" or "", r = d.type == "hold" and (d.radius or r) or 0 }
	elseif d.type == "interact" then
		for _, pid in ipairs(d.points) do
			if not step.used[pid] then
				m[#m + 1] = { pos = P.Get(pid) + Vector(0, 0, 24), kind = d.marker or "interact", label = d.label or "", r = 0 }
			end
		end
	elseif d.type == "kill" and step.reveal then
		for e in pairs(S.Enemies) do
			if IsValid(e) and e:Health() > 0 then m[#m + 1] = { pos = e:GetPos() + Vector(0, 0, 80), kind = "enemy", label = "", r = 0, ent = e } end
		end
	end
	return m
end

local function progressOf(step)
	if not step then return "", -1 end
	local d = step.def
	if d.type == "interact" and #d.points > 1 then
		return string.format("%d / %d", table.Count(step.used), #d.points), table.Count(step.used) / #d.points
	elseif d.type == "kill" then
		return "Осталось: " .. S.CountEnemies(step.tag), -1
	elseif d.type == "hold" then
		local left = math.max(0, step.need - step.held)
		local txt = string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60))
		if not step.inside then txt = txt .. "  ·  вернитесь в зону" end
		return txt, step.held / step.need
	end
	return "", -1
end

local function sendState(to)
	local text = cur and cur.def.text or ""
	local prog, frac = progressOf(cur)
	local marks = S.State.running and markersOf(cur) or {}
	net.Start("ws.story.state")
	net.WriteBool(S.State.running)
	net.WriteUInt(S.State.ch, 6)
	net.WriteString(S.State.running and text or "")
	net.WriteString(prog)
	net.WriteFloat(frac)
	net.WriteUInt(#marks, 6)
	for _, mk in ipairs(marks) do
		net.WriteVector(mk.pos)
		net.WriteString(mk.kind)
		net.WriteString(mk.label)
		net.WriteUInt(math.Clamp(math.floor(mk.r), 0, 4095), 12)
		net.WriteEntity(mk.ent or NULL)
	end
	if to then net.Send(to) else net.Broadcast() end
	lastSend = CurTime()
	dirty = false
end
S.SendState = sendState
function S.Dirty() dirty = true end

-- ---------------------------------------------------------------- шаги

local beginStep

local function nextStep()
	if cur and cur.def.done then S.Say(cur.def.done) end
	local ch = chapter()
	local i = S.State.step + 1
	if not ch.steps[i] then
		-- следующая глава
		if S.State.ch < #S.Chapters then
			S.StartChapter(S.State.ch + 1, true)
		end
		return
	end
	beginStep(i)
end

beginStep = function(i)
	local d = chapter().steps[i]
	S.State.step = i
	cur = { def = d, t0 = CurTime(), used = {}, held = 0, need = (d.time or 0) * C.StoryHoldScale,
		tag = S.State.ch .. ":" .. i, nextWave = CurTime() + (d.waves and d.waves.first or 0), midDone = {} }
	S.Say(d.lines)
	for _, sp in ipairs(d.spawn or {}) do
		local goal = d.point and P.Get(d.point) or P.Get(S.GroupById[sp.group].near)
		if sp.mode == "assault" then
			local n = nearest(goal)
			if n then goal = n:GetPos() end
		end
		S.Spawn(sp.group, sp.count, sp.mode, goal, cur.tag)
	end
	if d.type == "kill" and not d.spawn then
		-- враги, появившиеся раньше в этой главе, становятся целью шага
		for e in pairs(S.Enemies) do S.Enemies[e] = cur.tag end
	end
	if d.type == "explode" then cur.boomAt = CurTime() + 1.5 end
	-- чекпоинт: павшие возвращаются к живым
	if d.checkpoint then
		S.State.cp = i
		hook.Run("WSCheckpoint", S.State.ch, i)
		WS.Death.ReviveAll()
		net.Start("ws.story.checkpoint")
		net.Send(inGame())
	end
	dirty = true
	hook.Run("WSStoryStep", S.State.ch, i, d)
end

-- fromStep — начать главу не с начала, а с шага-чекпоинта (после гибели всего отряда)
function S.StartChapter(ch, continuing, fromStep)
	S.State.ch = math.Clamp(ch, 1, #S.Chapters)
	S.State.step = 0
	S.State.cp = fromStep
	S.State.running = true
	cur = nil
	clearProps()
	local c = chapter()
	-- предметы главы ставятся сразу — их видно издалека
	for _, st in ipairs(c.steps) do
		if st.type == "interact" and not st.plant then
			for _, pid in ipairs(st.points) do
				local def = S.PointById[pid]
				if def and def.prop then placeProp(pid, def.prop) end
			end
		elseif st.type == "goto" or st.type == "hold" or st.type == "explode" then
			local def = S.PointById[st.point]
			if def and def.prop then
				local exists = false
				for _, e in ipairs(S.Props) do if e.wsPoint == st.point then exists = true end end
				if not exists then placeProp(st.point, def.prop) end
			end
		end
	end
	-- ящик снабжения у начала главы (кроме первой — набор только что выдан)
	if S.State.ch > 1 then
		local base, yaw = P.Get(c.spawn or "spawn")
		local spot = P.AutoNear(base, 90, 180)
		local crate = ents.Create("ws_crate")
		if IsValid(crate) then
			crate:SetPos(spot)
			crate:SetAngles(Angle(0, yaw + 90, 0))
			crate:Spawn()
			S.Props[#S.Props + 1] = crate
		end
	end
	hook.Run("WSCheckpoint", S.State.ch, 0)
	WS.Death.ReviveAll()
	if not continuing then
		S.ClearEnemies()
	else
		-- оставшиеся враги идут на отряд
		for e in pairs(S.Enemies) do if IsValid(e) then e.wsMode = "hunt" end end
	end
	net.Start("ws.story.chapter")
	net.WriteUInt(S.State.ch, 6)
	net.Send(inGame())
	timer.Simple(3.5, function()
		if S.State.running and S.State.step == 0 and chapter() == c then beginStep(fromStep or 1) end
	end)
	dirty = true
	WS.Print("Сюжет: глава %d «%s»", S.State.ch, c.title)
end

function S.Stop(rollback)
	S.State.running = false
	S.State.step = 0
	cur = nil
	queue, queueEnd = {}, 0
	S.ClearEnemies()
	clearProps()
	if not rollback then S.State.ch = 1 end
	dirty = true
end

local function finish()
	local t = CurTime() - S.Stats.t0
	net.Start("ws.story.finish")
	net.WriteFloat(t)
	net.WriteUInt(S.Stats.kills, 16)
	net.WriteUInt(S.Stats.deaths, 16)
	net.Send(inGame())
	S.State.running = false
	cur = nil
	dirty = true
	hook.Run("WSStoryFinished", { time = t, kills = S.Stats.kills, deaths = S.Stats.deaths })
	timer.Simple(C.StoryEndTime, function()
		for _, p in ipairs(inGame()) do
			p:SetNW2Bool("ws_ingame", false)
			p:Spawn()
		end
		S.Stop(false)
	end)
end

local function explode(pos)
	local ed = EffectData()
	ed:SetOrigin(pos)
	ed:SetMagnitude(4)
	ed:SetScale(3)
	util.Effect("Explosion", ed, true, true)
	util.Effect("HelicopterMegaBomb", ed, true, true)
	util.ScreenShake(pos, 16, 120, 3, 6000)
	sound.Play("ambient/explosions/explode_4.wav", pos, 140, 90, 1)
	sound.Play("ambient/explosions/explode_8.wav", pos, 140, 70, 1)
	for _, e in ipairs(S.Props) do
		if IsValid(e) and e:GetPos():Distance(pos) < 400 then e:Remove() end
	end
	for e in pairs(S.Enemies) do
		if IsValid(e) and e:GetPos():Distance(pos) < 900 then
			local dmg = DamageInfo()
			dmg:SetDamage(1000)
			dmg:SetDamageType(DMG_BLAST)
			dmg:SetAttacker(game.GetWorld())
			dmg:SetInflictor(game.GetWorld())
			e:TakeDamageInfo(dmg)
		end
	end
	net.Start("ws.story.boom")
	net.WriteVector(pos)
	net.Broadcast()
end

-- Свободное место рядом с точкой (кольцом вокруг)
local function freeAround(pos, idx)
	if P.Free(pos) and idx == 0 then return pos end
	for k = 0, 23 do
		local a = (idx * 0.9 + k * 0.785)
		local r = 60 + math.floor(k / 8) * 50
		local p = P.Ground(pos + Vector(math.cos(a) * r, math.sin(a) * r, 0))
		if p and P.Free(p) then return p end
	end
	return pos
end

-- ---------------------------------------------------------------- взаимодействие (удерживать E)

local function aimingAt(ply, pos)
	local eye = ply:EyePos()
	local to = pos - eye
	local d = to:Length()
	if d > C.StoryUseDist + 40 then return false end
	if d < 40 then return true end
	return ply:GetAimVector():Dot(to:GetNormalized()) > 0.8
end

local function useThink(step, dt)
	local d = step.def
	local need = d.use or C.StoryUseTime
	for _, ply in ipairs(fighters()) do
		local target
		if ply:KeyDown(IN_USE) then
			for _, pid in ipairs(d.points) do
				if not step.used[pid] then
					local pos = P.Get(pid) + Vector(0, 0, 16)
					if ply:GetPos():Distance(pos) < C.StoryUseDist + 60 and aimingAt(ply, pos) then target = pid break end
				end
			end
		end
		if target ~= ply.wsUseId then
			ply.wsUseId, ply.wsUseT = target, 0
			ply:SetNW2String("ws_use_label", target and (d.label or "") or "")
		end
		if target then
			ply.wsUseT = ply.wsUseT + dt
			ply:SetNW2Float("ws_use", math.min(ply.wsUseT / need, 1))
			if ply.wsUseT >= need then
				step.used[target] = ply
				ply.wsUseId = nil
				ply:SetNW2Float("ws_use", 0)
				ply:SetNW2String("ws_use_label", "")
				ply:EmitSound("buttons/button9.wav", 60, 110)
				if d.plant then
					local pos, yaw = P.Get(target)
					local e = placeProp(target, d.plant)
					if IsValid(e) then e:SetPos(pos + Vector(0, 0, 1)) e:SetAngles(Angle(0, yaw, 0)) end
				end
				if d.after and d.after[target] then S.Say(d.after[target]) end
				dirty = true
			end
		elseif ply:GetNW2Float("ws_use", 0) ~= 0 then
			ply:SetNW2Float("ws_use", 0)
		end
	end
	return table.Count(step.used) >= #d.points
end

-- ---------------------------------------------------------------- главный цикл

local function anyInside(pos, r)
	for _, p in ipairs(fighters()) do
		local pp = p:GetPos()
		if math.abs(pp.z - pos.z) < 250 and pp:Distance2DSqr(pos) < r * r then return true end
	end
	return false
end

local function stepThink(dt)
	if not cur then return end
	local d = cur.def
	local done = false
	if d.type == "say" then
		done = not S.Talking() and CurTime() - cur.t0 > 0.5
	elseif d.type == "goto" then
		local pos, _, r = P.Get(d.point)
		r = d.radius or r
		if d.near and not cur.nearSaid then
			local _, dist = nearest(pos)
			if dist < d.near.dist then cur.nearSaid = true S.Say(d.near.lines) end
		end
		done = anyInside(pos, r)
	elseif d.type == "interact" then
		done = useThink(cur, dt)
	elseif d.type == "kill" then
		local left = S.CountEnemies(cur.tag)
		if left ~= cur.left then cur.left = left dirty = true end
		-- если враги долго не попадаются на глаза — показать их метками
		local seen = false
		for e in pairs(S.Enemies) do if IsValid(e) and e.wsSeenT and CurTime() - e.wsSeenT < 30 then seen = true end end
		local reveal = not seen and CurTime() - cur.t0 > 30
		if reveal ~= cur.reveal then cur.reveal = reveal dirty = true end
		if cur.reveal and CurTime() - lastSend > 1 then dirty = true end
		done = left == 0 and CurTime() - cur.t0 > 2
	elseif d.type == "hold" then
		local pos, _, r = P.Get(d.point)
		r = d.radius or r
		local inside = anyInside(pos, r)
		if inside ~= cur.inside then cur.inside = inside dirty = true end
		if inside then cur.held = cur.held + dt end
		if CurTime() - lastSend > 0.5 then dirty = true end
		local w = d.waves
		if w and CurTime() >= cur.nextWave and cur.held < cur.need then
			cur.nextWave = CurTime() + w.every
			S.Spawn(w.group, w.count, "assault", pos, cur.tag)
		end
		for k, lines in pairs(d.mid or {}) do
			if not cur.midDone[k] and cur.held >= cur.need * k then cur.midDone[k] = true S.Say(lines) end
		end
		done = cur.held >= cur.need
	elseif d.type == "explode" then
		if cur.boomAt and CurTime() >= cur.boomAt then
			cur.boomAt = nil
			explode(P.Get(d.point))
			cur.after = CurTime() + 2
		end
		done = cur.after and CurTime() >= cur.after
	elseif d.type == "cutscene" then
		-- крушение: реплики → затемнение и удар (клиент) → все очнутся в точке d.point
		if not cur.sent and not S.Talking() then
			cur.sent = true
			net.Start("ws.story.cutscene")
			net.WriteString(d.scene or "crash")
			net.Send(inGame())
			cur.tpAt = CurTime() + 6.5
		end
		if cur.tpAt and not cur.tp and CurTime() >= cur.tpAt then
			cur.tp = true
			S.ClearEnemies()
			clearProps()
			WS.Death.ReviveAll()
			local base, yaw = P.Get(d.point)
			for i, p in ipairs(fighters()) do
				p:SetPos(freeAround(base, i))
				p:SetEyeAngles(Angle(0, yaw, 0))
				p:SetHealth(math.random(48, 70))
				p:SetVelocity(-p:GetVelocity())
			end
			-- обломки: дым и огонь у места падения
			local ed = EffectData()
			ed:SetOrigin(base + Vector(0, 0, 10))
			util.Effect("HelicopterMegaBomb", ed, true, true)
			cur.after = CurTime() + 1
		end
		done = cur.after and CurTime() >= cur.after
	elseif d.type == "finish" then
		if not S.Talking() then
			cur = nil
			finish()
		end
		return
	end
	if done then nextStep() end
end

local wipeT
local accum = 0
hook.Add("Think", "ws.story", function()
	local dt = FrameTime()
	sayThink()
	accum = accum + dt
	if accum < 0.1 then return end
	dt, accum = accum, 0
	if S.State.running then
		-- гибель всего отряда
		if #fighters() == 0 then
			wipeT = wipeT or CurTime()
			if CurTime() - wipeT > C.StoryWipeDelay then
				wipeT = nil
				local ch, cp = S.State.ch, S.State.cp
				S.Stop(true)
				S.State.ch = ch
				WS.Chat.System("Связь с отрядом потеряна. " .. (cp and "Отряд вернётся к последнему чекпоинту главы «" or "Глава «")
					.. S.Chapters[ch].title .. (cp and "»." or "» начнётся заново."))
				hook.Run("WSSquadWiped", ch)
				-- все сразу возвращаются: к последнему чекпоинту главы или к её началу
				timer.Simple(3, function()
					if S.State.running or #inGame() == 0 then return end
					WS.Death.ReviveAll()
					S.StartChapter(ch, false, cp)
				end)
			end
		else
			wipeT = nil
			stepThink(dt)
		end
	end
	if dirty and CurTime() - lastSend > 0.25 then sendState() end
end)

-- ---------------------------------------------------------------- выход в игру и появление

hook.Add("WSSquadDeployed", "ws.story", function(members)
	if not S.State.running and not S.Starting then
		local delay = 2.5
		if S.State.ch == 1 then
			S.Stats = { t0 = CurTime(), kills = 0, deaths = 0 }
			-- брифинг миссии: карта, задача, голос штаба — потом пробуждение и первая глава
			net.Start("ws.story.briefing")
			net.Send(members)
			delay = C.BriefingTime
		end
		S.Starting = true
		timer.Simple(delay, function()
			S.Starting = nil
			if not S.State.running and #inGame() > 0 then S.StartChapter(S.State.ch) end
		end)
	end
	timer.Simple(0.5, function() for _, p in ipairs(members) do if IsValid(p) then sendState(p) end end end)
end)

local function spawnPoint()
	local ch = chapter()
	return P.Get(ch and ch.spawn or "spawn")
end

hook.Add("PlayerSpawn", "ws.story", function(ply)
	timer.Simple(0, function()
		if not IsValid(ply) or not L.InGame(ply) then return end
		-- подкрепление — к живым товарищам по отряду, иначе к чекпоинту главы
		local mate
		for _, p in ipairs(fighters()) do
			if p ~= ply and (not mate or L.Id(p) == L.Id(ply)) then mate = p end
		end
		local pos, yaw
		if S.State.running and IsValid(mate) then
			pos = freeAround(mate:GetPos() - mate:GetForward() * 90, ply:EntIndex())
			yaw = mate:EyeAngles().y
		else
			local base, y = spawnPoint()
			pos, yaw = freeAround(base, ply:EntIndex() % 8), y
		end
		ply:SetPos(pos)
		ply:SetEyeAngles(Angle(0, yaw or 0, 0))
	end)
end)

hook.Add("PlayerDeath", "ws.story", function(ply)
	if L.InGame(ply) then S.Stats.deaths = S.Stats.deaths + 1 end
	ply:SetNW2Float("ws_use", 0)
end)

hook.Add("WSEnemyKilled", "ws.story", function()
	S.Stats.kills = S.Stats.kills + 1
	dirty = true
end)

hook.Add("PlayerInitialSpawn", "ws.story", function(ply)
	timer.Simple(2, function() if IsValid(ply) then sendState(ply) end end)
end)

-- Консоль сервера / суперадмин: ws_story <глава> | stop
concommand.Add("ws_story", function(ply, _, args)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	if args[1] == "stop" then S.Stop(false) return end
	local ch = tonumber(args[1] or "1") or 1
	S.Stop(true)
	if ch == 1 then S.Stats = { t0 = CurTime(), kills = 0, deaths = 0 } end
	S.StartChapter(ch)
end)
