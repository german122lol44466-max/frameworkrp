--[[
	Аркадный автомат на сервере: оплата игры ($1), проверка результата, таблицы рекордов.
	  «Змейка» — счёт = съеденные яблоки (больше — лучше). Проверка: не больше яблока за 0,25 с игры.
	  «Реакция» — 5 попыток, задержки до сигнала выбирает сервер; счёт = средняя реакция в мс (меньше — лучше).
	    Проверка: каждая попытка 100–1500 мс (фальстарт = 1000 мс), игра не короче суммы задержек.
	Рекорды: топ-10 каждой игры, лучший результат одного персонажа, data/nyrp/arcade.json.
	Денег не выигрывают; достижения «Удав» и «Молниеносный» — если есть модуль достижений.
]]

NYRP.Leisure = NYRP.Leisure or {}
local LS = NYRP.Leisure
LS.Arcade = LS.Arcade or {}
local AR = LS.Arcade

local FILE = "nyrp/arcade.json"
AR.Records = AR.Records or nil

local function load()
	local raw = file.Exists(FILE, "DATA") and util.JSONToTable(file.Read(FILE, "DATA") or "") or nil
	if not istable(raw) then raw = {} end
	AR.Records = {}
	for _, g in ipairs(AR.Order) do
		local list = {}
		if istable(raw[g]) then
			for _, r in ipairs(raw[g]) do
				if istable(r) and tonumber(r.score) then
					list[#list + 1] = { name = tostring(r.name or "?"), char = tonumber(r.char) or 0, score = math.floor(tonumber(r.score)), date = tonumber(r.date) or 0 }
				end
			end
		end
		AR.Records[g] = list
	end
end
load()

function AR.Save()
	file.CreateDir("nyrp")
	file.Write(FILE, util.TableToJSON(AR.Records, true))
end

local function better(game, a, b)
	if AR.Games[game].higher then return a > b end
	return a < b
end

-- текст лучшего результата для экрана автомата
function AR.BestText(game)
	local r = AR.Records and AR.Records[game] and AR.Records[game][1]
	if not r then return "" end
	return r.name .. " — " .. AR.Format(game, r.score)
end

function AR.UpdateScreens()
	for _, e in ipairs(ents.FindByClass("nyrp_arcade")) do
		if IsValid(e) then
			e:SetNW2String("nyrp.arc.snake", AR.BestText("snake"))
			e:SetNW2String("nyrp.arc.reaction", AR.BestText("reaction"))
		end
	end
end

-- добавить результат; вернуть место (0 — не попал в таблицу) и был ли это личный рекорд
local function submit(ply, game, score)
	local c = ply.nyrpChar
	local list = AR.Records[game]
	local name = c and c.name or ply:Nick()
	local cid = c and c.id or 0
	for i, r in ipairs(list) do
		if r.char == cid then
			if not better(game, score, r.score) then return 0, false end
			table.remove(list, i)
			break
		end
	end
	list[#list + 1] = { name = name, char = cid, score = score, date = os.time() }
	table.sort(list, function(a, b)
		if a.score == b.score then return a.date < b.date end
		return better(game, a.score, b.score)
	end)
	while #list > AR.Top do table.remove(list) end
	AR.Save()
	AR.UpdateScreens()
	for i, r in ipairs(list) do
		if r.char == cid and r.score == score then return i, true end
	end
	return 0, true
end

local function writeRecords()
	for _, g in ipairs(AR.Order) do
		local list = AR.Records[g]
		net.WriteUInt(#list, 5)
		for _, r in ipairs(list) do
			net.WriteString(r.name)
			net.WriteUInt(math.Clamp(r.score, 0, 65535), 16)
		end
	end
end

local function near(ply, ent)
	return IsValid(ent) and ent:GetClass() == "nyrp_arcade" and ent:GetPos():Distance(ply:GetPos()) <= 180
end

function AR.Use(ent, ply)
	if (ply.nyrpArcUse or 0) > CurTime() then return end
	ply.nyrpArcUse = CurTime() + 1
	ply.nyrpArcEnt = ent
	ent:EmitSound("buttons/button17.wav", 55)
	net.Start("nyrp.arc.open")
	net.WriteEntity(ent)
	writeRecords()
	net.Send(ply)
end

net.Receive("nyrp.arc.start", function(_, ply)
	if (ply.nyrpArcNext or 0) > CurTime() then return end
	ply.nyrpArcNext = CurTime() + 1.5
	local game = net.ReadString()
	if not AR.Games[game] then return end
	local ent = ply.nyrpArcEnt
	if not NYRP.HasCharacter(ply) or not ply:Alive() then return end
	if not near(ply, ent) then NYRP.Notify(ply, "Подойдите к автомату", "warning") return end
	if NYRP.Money.Get(ply) < AR.Price then NYRP.Notify(ply, "Игра стоит " .. NYRP.Money.Format(AR.Price) .. " — не хватает наличных", "error") return end
	NYRP.Money.Add(ply, -AR.Price)
	ent:EmitSound("ambient/levels/labs/coinslot1.wav", 60)
	local sess = { game = game, started = CurTime(), ent = ent }
	if game == "reaction" then
		sess.delays = {}
		for i = 1, AR.ReactRounds do sess.delays[i] = math.random(15, 45) / 10 end
	end
	ply.nyrpArcGame = sess
	net.Start("nyrp.arc.go")
	net.WriteString(game)
	local n = sess.delays and #sess.delays or 0
	net.WriteUInt(n, 4)
	for i = 1, n do net.WriteFloat(sess.delays[i]) end
	net.Send(ply)
end)

net.Receive("nyrp.arc.finish", function(_, ply)
	local game = net.ReadString()
	local score = net.ReadUInt(16)
	local n = net.ReadUInt(4)
	local times = {}
	for i = 1, n do times[i] = net.ReadUInt(16) end
	local sess = ply.nyrpArcGame
	if not sess or sess.game ~= game then return end
	ply.nyrpArcGame = nil
	if not NYRP.HasCharacter(ply) then return end
	local elapsed = CurTime() - sess.started
	if elapsed > 900 then NYRP.Notify(ply, "Игра слишком затянулась — результат не засчитан", "warning") return end
	local ok = true
	if game == "snake" then
		local maxScore = AR.SnakeW * AR.SnakeH
		if score > maxScore or score > elapsed / 0.25 + 1 then ok = false end
	elseif game == "reaction" then
		if n ~= AR.ReactRounds then ok = false end
		local sum, minTotal = 0, 0
		for i = 1, AR.ReactRounds do
			local t = times[i] or 0
			if t < 100 or t > 1500 then ok = false end
			sum = sum + t
			minTotal = minTotal + (sess.delays[i] or 0)
		end
		if ok then
			score = math.floor(sum / AR.ReactRounds + 0.5)
			if elapsed + 1 < minTotal + sum / 1000 * 0.5 then ok = false end
		end
	end
	if not ok then
		NYRP.Notify(ply, "Автомат не принял результат (сбой)", "warning", 3)
		return
	end
	local place, personal = 0, false
	if game ~= "snake" or score > 0 then place, personal = submit(ply, game, score) end
	-- достижения
	local A = NYRP.Ach
	if A then
		if game == "snake" and A.Max then A.Max(ply, "arcadeSnake", score) end
		if game == "reaction" and score <= 250 and A.Max then A.Max(ply, "arcadeReflex", 1) end
	end
	if place == 1 and IsValid(sess.ent) then sess.ent:EmitSound("nyrp/phone/game_record.wav", 65) end
	hook.Run("NYRP.ArcadePlayed", ply, game, score, place)
	net.Start("nyrp.arc.result")
	net.WriteString(game)
	net.WriteUInt(math.Clamp(score, 0, 65535), 16)
	net.WriteUInt(place, 5)
	net.WriteBool(personal)
	writeRecords()
	net.Send(ply)
end)

hook.Add("InitPostEntity", "nyrp.arcade", function() timer.Simple(3, function() AR.UpdateScreens() end) end)
