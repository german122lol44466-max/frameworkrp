--[[
	Достижения на сервере: счётчики, проверка целей, награда, синхронизация с клиентом.
	Источники: хуки режима (ItemUsed, ZoneDiscovered, TrashThrown, ChatMessage, StockTrade, Lottery…),
	обёртки функций других модулей (пожар, арест, реанимация, помощь без сознания) — ставятся после загрузки,
	и раз в 5 секунд — опрос состояния (наличные, банк, задания работ, стул, навыки).
	API: NYRP.Ach.Add(ply, stat, n), NYRP.Ach.Max(ply, stat, value), NYRP.Ach.Unlock(ply, id).
	Админ: /achreset [часть имени] — сбросить достижения.
]]

NYRP.Ach = NYRP.Ach or {}
local A = NYRP.Ach

local function data(ply)
	local c = ply.nyrpChar
	if not c then return end
	c.flags = c.flags or {}
	c.flags.ach = c.flags.ach or {}
	local d = c.flags.ach
	d.done = d.done or {}
	d.p = d.p or {}
	return d
end
A.Data = data

local function count(d)
	local n = 0
	for _ in pairs(d.done) do n = n + 1 end
	return n
end

function A.Send(ply, open)
	local d = data(ply)
	if not d then return end
	net.Start("nyrp.ach.data")
	net.WriteTable(d.done)
	net.WriteTable(d.p)
	net.WriteBool(open and true or false)
	net.Send(ply)
end

function A.Unlock(ply, id)
	local d, a = data(ply), A.ById[id]
	if not d or not a or d.done[id] then return end
	d.done[id] = os.time()
	if a.reward and a.reward > 0 then NYRP.Money.Add(ply, a.reward) end
	net.Start("nyrp.ach.unlock")
	net.WriteString(id)
	net.Send(ply)
	NYRP.Print(string.format("[достижения] %s (%s): %s", ply:Nick(), NYRP.CharName(ply), a.name))
	hook.Run("NYRP.AchievementUnlocked", ply, id)
	-- «Коллекционер»
	d.p.achs = count(d)
	A.Check(ply, "achs")
	NYRP.Chars.Save(ply)
end

function A.Check(ply, stat)
	local d = data(ply)
	if not d then return end
	local v = d.p[stat] or 0
	for _, a in ipairs(A.List) do
		if a.stat == stat and not d.done[a.id] and v >= a.goal then A.Unlock(ply, a.id) end
	end
end

-- прибавить к счётчику
function A.Add(ply, stat, n)
	if not IsValid(ply) or not ply:IsPlayer() then return end
	local d = data(ply)
	if not d then return end
	d.p[stat] = (d.p[stat] or 0) + (n or 1)
	A.Check(ply, stat)
end

-- счётчик-«рекорд» (наибольшее значение)
function A.Max(ply, stat, v)
	if not IsValid(ply) then return end
	local d = data(ply)
	if not d or (d.p[stat] or 0) >= v then return end
	d.p[stat] = v
	A.Check(ply, stat)
end

net.Receive("nyrp.ach.req", function(_, ply)
	if (ply.nyrpAchReq or 0) > CurTime() then return end
	ply.nyrpAchReq = CurTime() + 1
	A.Send(ply, net.ReadBool())
end)

-- ------------------------------------------------------------------ хуки --
hook.Add("NYRP.CharacterLoaded", "nyrp.ach", function(ply)
	timer.Simple(2, function() if IsValid(ply) then A.Send(ply, false) end end)
end)
hook.Add("NYRP.ZoneDiscovered", "nyrp.ach", function(ply) A.Add(ply, "zones", 1) end)
hook.Add("NYRP.TrashThrown", "nyrp.ach", function(ply, e, n) A.Add(ply, "trash", tonumber(n) or 1) end)
hook.Add("NYRP.ChatMessage", "nyrp.ach", function(ply, kind)
	local T = NYRP.Chat and NYRP.Chat.Types
	if T and (kind == T.IC or kind == T.WHISPER or kind == T.YELL) then A.Add(ply, "talk", 1) end
end)
hook.Add("NYRP.AlcoholDrunk", "nyrp.ach", function(ply) A.Add(ply, "drinks", 1) end)
hook.Add("NYRP.StockTrade", "nyrp.ach", function(ply, op, id, n, amount, profit)
	if op == "buy" then A.Add(ply, "trades", 1) end
	local c = ply.nyrpChar
	if op == "sell" and c and c.flags then A.Max(ply, "stockProfit", math.floor(c.flags.stocksProfit or 0)) end
end)
hook.Add("NYRP.LotteryScratched", "nyrp.ach", function(ply, prize)
	A.Add(ply, "scratches", 1)
	if prize > 0 then A.Add(ply, "scratchWins", 1) end
end)
hook.Add("NYRP.LottoWon", "nyrp.ach", function(ply) A.Add(ply, "lotto", 1) end)

-- --------------------------------------------------------------- опрос --
timer.Create("nyrp.ach.poll", 5, 0, function()
	for _, ply in ipairs(player.GetAll()) do
		local c = ply.nyrpChar
		if c and c.flags then
			A.Max(ply, "cash", NYRP.Money.Get(ply))
			local bank = 0
			for _, v in pairs(c.flags.bank or {}) do bank = bank + (tonumber(v) or 0) end
			A.Max(ply, "bank", math.floor(bank))
			A.Max(ply, "jobs", c.flags.jobTasks or 0)
			if ply:GetNW2Bool("nyrp.sit") and not ply:GetNW2Bool("nyrp.sitGround") then A.Max(ply, "sit", 1) end
			local best = 0
			for _, v in pairs(c.skills or {}) do best = math.max(best, tonumber(v) or 0) end
			A.Max(ply, "skill", best)
		end
	end
end)

-- ---------------------------------------------- обёртки функций других модулей --
A.Wrapped = A.Wrapped or {}
local function wrap(tbl, name, key, after)
	if not tbl or type(tbl[name]) ~= "function" or A.Wrapped[key] == tbl[name] then return end
	local orig = tbl[name]
	local w = function(...)
		local r = { orig(...) }
		local ok, err = pcall(after, r, ...)
		if not ok then ErrorNoHalt("[NYRP ach] " .. tostring(err) .. "\n") end
		return unpack(r)
	end
	tbl[name] = w
	A.Wrapped[key] = w
end

local function install()
	local F = NYRP.Factions
	wrap(F, "Extinguished", "ext", function(_, ply) if IsValid(ply) then A.Add(ply, "fires", 1) end end)
	wrap(F, "Arrest", "arrest", function(_, cop, target)
		if IsValid(target) and target:GetNW2Float("nyrp.jailUntil", 0) > CurTime() then
			if IsValid(cop) and cop ~= target then A.Add(cop, "arrests", 1) end
			A.Add(target, "jailed", 1)
		end
	end)
	wrap(F, "Revive", "revive", function(r, medic) if r[1] and IsValid(medic) then A.Add(medic, "heals", 1) end end)
	-- первая помощь без сознания: WakeUp(owner, hp) с hp — помог кто-то рядом
	wrap(NYRP.Cond, "WakeUp", "wake", function(_, owner, hp)
		if not hp or not IsValid(owner) then return end
		local best, bd
		for _, p in ipairs(player.GetAll()) do
			if p ~= owner and p:Alive() then
				local dist = p:GetPos():DistToSqr(owner:GetPos())
				if dist < 200 * 200 and (not bd or dist < bd) then best, bd = p, dist end
			end
		end
		if best then A.Add(best, "heals", 1) end
	end)
end
hook.Add("InitPostEntity", "nyrp.ach.wrap", function(...) install(...) end)
timer.Simple(0, install)

-- ---------------------------------------------------------------- команды --
local function cmd(name, fn)
	if NYRP.Chat and NYRP.Chat.AddCommand then NYRP.Chat.AddCommand(name, fn) return end
	timer.Simple(0, function() NYRP.Chat.AddCommand(name, fn) end)
end

local function open(ply) if NYRP.HasCharacter(ply) then A.Send(ply, true) end end
cmd("/achievements", open)
cmd("/достижения", open)
cmd("/ach", open)

cmd("/achreset", function(ply, raw)
	if not ply:IsSuperAdmin() then return end
	local part = string.lower(string.Trim(string.match(raw, "^%S+%s*(.*)$") or ""))
	local target = ply
	if part ~= "" then
		target = nil
		for _, p in ipairs(player.GetAll()) do
			if string.find(string.lower(p:Nick()), part, 1, true) or string.find(string.lower(NYRP.CharName(p) or ""), part, 1, true) then target = p break end
		end
	end
	if not IsValid(target) or not target.nyrpChar then NYRP.Notify(ply, "Игрок не найден", "error") return end
	target.nyrpChar.flags.ach = nil
	NYRP.Chars.Save(target)
	A.Send(target, false)
	NYRP.Notify(ply, "Достижения сброшены: " .. NYRP.CharName(target), "success")
end)
