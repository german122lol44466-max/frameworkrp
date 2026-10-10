--[[
	Лотерея на сервере: продажа в автомате, результат скретч-карты (решается при покупке),
	выплата после стирания, розыгрыш NY Lotto раз в 2 часа, сохранение автоматов на карте.
]]

NYRP.Lottery = NYRP.Lottery or {}
local L = NYRP.Lottery

local FILE = "nyrp/lottery.json"
local MFILE = function() return "nyrp/lottery_" .. game.GetMap() .. ".json" end

-- ------------------------------------------------------------- состояние --
-- { jackpot, nextDraw = os.time, draw = номер розыгрыша, tickets = {{char, name, num}}, pending = {[charId] = сумма}, last = {name, amount, num} }
L.Data = L.Data or nil

function L.Save()
	file.CreateDir("nyrp")
	file.Write(FILE, util.TableToJSON(L.Data))
end

local function load()
	local raw = file.Exists(FILE, "DATA") and util.JSONToTable(file.Read(FILE, "DATA") or "") or nil
	if not istable(raw) then raw = {} end
	L.Data = {
		jackpot = tonumber(raw.jackpot) or L.BaseJackpot,
		nextDraw = tonumber(raw.nextDraw) or (os.time() + L.DrawEvery),
		draw = tonumber(raw.draw) or 1,
		tickets = istable(raw.tickets) and raw.tickets or {},
		pending = istable(raw.pending) and raw.pending or {},
		last = istable(raw.last) and raw.last or nil,
	}
end
load()

-- ---------------------------------------------------------- скретч-карта --
-- Результат: 6 символов и выигрыш. Выигрыш — ровно три одинаковых призовых, остальные — не больше двух.
function L.Roll()
	local r, acc = math.random(), 0
	local win
	for _, s in ipairs(L.Symbols) do
		if s.prize > 0 then
			acc = acc + s.chance
			if r < acc then win = s break end
		end
	end
	local syms, count = {}, {}
	if win then
		for _ = 1, 3 do syms[#syms + 1] = win.id end
		count[win.id] = 3
	end
	local guard = 0
	while #syms < 6 and guard < 500 do
		guard = guard + 1
		local s = L.Symbols[math.random(#L.Symbols)]
		if s ~= win and (count[s.id] or 0) < 2 then
			syms[#syms + 1] = s.id
			count[s.id] = (count[s.id] or 0) + 1
		end
	end
	-- перемешать
	for i = #syms, 2, -1 do
		local j = math.random(i)
		syms[i], syms[j] = syms[j], syms[i]
	end
	return syms, win and win.prize or 0
end

local function serial() return string.format("%06d%04d", os.time() % 1000000, math.random(0, 9999)) end

-- ПКМ «Стереть»: показать окно стирания
function L.OpenScratch(ply, it)
	if (ply.nyrpScratchNext or 0) > CurTime() then return end
	ply.nyrpScratchNext = CurTime() + 1
	it.data = it.data or {}
	if not it.data.serial or not istable(it.data.syms) then
		-- карта без результата (выдана админом) — решаем сейчас
		it.data.serial = serial()
		it.data.syms, it.data.prize = L.Roll()
	end
	net.Start("nyrp.lottery.scratch")
	net.WriteString(it.data.serial)
	net.WriteTable(it.data.syms)
	net.WriteUInt(it.data.prize or 0, 16)
	net.Send(ply)
end

net.Receive("nyrp.lottery.claim", function(_, ply)
	if (ply.nyrpClaimNext or 0) > CurTime() then return end
	ply.nyrpClaimNext = CurTime() + 1
	local ser = net.ReadString()
	if not NYRP.HasCharacter(ply) then return end
	local Inv = NYRP.Inv
	local inv = Inv.Get(ply)
	for slot = 1, Inv.Size(ply) do
		local it = inv.slots[slot]
		if it and it.id == "scratch_ticket" and it.data and it.data.serial == ser then
			local prize = tonumber(it.data.prize) or 0
			Inv.Take(ply, slot, 1)
			if prize > 0 then
				NYRP.Money.Add(ply, prize)
				ply:EmitSound("nyrp/fx/cash.wav", 60)
				NYRP.Notify(ply, "Выигрыш по скретч-карте: +" .. NYRP.Money.Format(prize) .. " наличными!", "success", 7)
				if prize >= 100 and NYRP.Street and NYRP.Street.AddNews then
					NYRP.Street.AddNews("Лотерея Liberty Luck: житель города выиграл " .. NYRP.Money.Format(prize))
				end
			else
				NYRP.Notify(ply, "Без выигрыша. Повезёт в следующий раз!", "info", 4)
			end
			hook.Run("NYRP.LotteryScratched", ply, prize)
			return
		end
	end
end)

-- ---------------------------------------------------------- автомат: меню --
local function myTickets(ply)
	local c = ply.nyrpChar
	local out = {}
	if not c then return out end
	for _, t in ipairs(L.Data.tickets) do
		if t.char == c.id then out[#out + 1] = t.num end
	end
	return out
end

function L.SendMenu(ply, ent)
	ply.nyrpLotteryEnt = ent
	net.Start("nyrp.lottery.menu")
	net.WriteEntity(ent)
	net.WriteUInt(L.Data.jackpot, 32)
	net.WriteUInt(math.max(0, L.Data.nextDraw - os.time()), 32)
	net.WriteUInt(#L.Data.tickets, 16)
	net.WriteTable(myTickets(ply))
	net.WriteTable(L.Data.last or {})
	net.Send(ply)
end

net.Receive("nyrp.lottery.buy", function(_, ply)
	if (ply.nyrpLotteryBuy or 0) > CurTime() then return end
	ply.nyrpLotteryBuy = CurTime() + 0.6
	local kind = net.ReadString()
	local ent = ply.nyrpLotteryEnt
	if not NYRP.HasCharacter(ply) or not ply:Alive() then return end
	if not IsValid(ent) or ent:GetClass() ~= "nyrp_lottery" or ent:GetPos():Distance(ply:GetPos()) > 160 then
		NYRP.Notify(ply, "Подойдите к лотерейному автомату", "warning")
		return
	end
	local c = ply.nyrpChar
	if kind == "scratch" then
		if NYRP.Money.Get(ply) < L.ScratchPrice then NYRP.Notify(ply, "Не хватает наличных: нужно " .. NYRP.Money.Format(L.ScratchPrice), "error") return end
		local syms, prize = L.Roll()
		if NYRP.Inv.Add(ply, "scratch_ticket", 1, { serial = serial(), syms = syms, prize = prize }) <= 0 then
			NYRP.Notify(ply, "В сумке нет места", "error")
			return
		end
		NYRP.Money.Add(ply, -L.ScratchPrice)
		ent:EmitSound("buttons/button14.wav", 60)
		NYRP.Notify(ply, "Скретч-карта в сумке: ПКМ → «Стереть»", "success", 5)
	elseif kind == "lotto" then
		if #myTickets(ply) >= L.MaxLotto then NYRP.Notify(ply, "Не больше " .. L.MaxLotto .. " билетов на розыгрыш", "warning") return end
		if NYRP.Money.Get(ply) < L.LottoPrice then NYRP.Notify(ply, "Не хватает наличных: нужно " .. NYRP.Money.Format(L.LottoPrice), "error") return end
		NYRP.Money.Add(ply, -L.LottoPrice)
		local num = string.format("%06d", math.random(0, 999999))
		table.insert(L.Data.tickets, { char = c.id, name = c.name, num = num })
		L.Data.jackpot = L.Data.jackpot + math.floor(L.LottoPrice * L.JackpotShare)
		L.Save()
		ent:EmitSound("buttons/button9.wav", 60)
		NYRP.Notify(ply, "Билет NY Lotto №" .. num .. " зарегистрирован. Розыгрыш — в объявлении в чате.", "success", 6)
	else
		return
	end
	L.SendMenu(ply, ent)
end)

-- ------------------------------------------------------------ NY Lotto --
local function payWinner(charId, amount, name)
	for _, p in ipairs(player.GetAll()) do
		if p.nyrpChar and p.nyrpChar.id == charId then
			local B = NYRP.Bank
			local card = B and B.FindCard(p)
			if card and B.Add(p, card.data.bank, amount, "Выигрыш NY Lotto") then
				NYRP.Notify(p, "Вы выиграли джекпот NY Lotto: " .. NYRP.Money.Format(amount) .. " — зачислено на карту!", "success", 12)
			else
				NYRP.Money.Add(p, amount)
				NYRP.Notify(p, "Вы выиграли джекпот NY Lotto: " .. NYRP.Money.Format(amount) .. " наличными!", "success", 12)
			end
			NYRP.Chars.Save(p)
			p:EmitSound("nyrp/phone/game_record.wav", 70)
			hook.Run("NYRP.LottoWon", p, amount)
			return
		end
	end
	-- не в игре — выплатим при входе
	local k = tostring(charId)
	L.Data.pending[k] = (L.Data.pending[k] or 0) + amount
end

function L.Draw()
	local d = L.Data
	d.nextDraw = os.time() + L.DrawEvery
	local Chat = NYRP.Chat
	if #d.tickets == 0 then
		if Chat then Chat.System(nil, "NY Lotto: билетов в розыгрыше №" .. d.draw .. " не было. Джекпот " .. NYRP.Money.Format(d.jackpot) .. " переходит в следующий тираж!") end
		d.draw = d.draw + 1
		L.Save()
		return
	end
	local t = d.tickets[math.random(#d.tickets)]
	local amount = d.jackpot
	if Chat then
		Chat.System(nil, "NY Lotto, тираж №" .. d.draw .. ": выигрышный билет №" .. t.num .. "! Джекпот " .. NYRP.Money.Format(amount) .. " получает " .. (t.name or "житель города") .. ".")
	end
	if NYRP.Street and NYRP.Street.AddNews then
		NYRP.Street.AddNews("NY Lotto: джекпот " .. NYRP.Money.Format(amount) .. " сорвал(а) " .. (t.name or "житель города"))
	end
	d.last = { name = t.name, amount = amount, num = t.num, draw = d.draw }
	payWinner(t.char, amount, t.name)
	d.tickets = {}
	d.jackpot = L.BaseJackpot
	d.draw = d.draw + 1
	L.Save()
end

timer.Create("nyrp.lottery.draw", 30, 0, function()
	if not L.Data then return end
	local left = L.Data.nextDraw - os.time()
	if left <= 0 then
		L.Draw()
	elseif left <= 600 and not L.Warned then
		L.Warned = true
		if NYRP.Chat then NYRP.Chat.System(nil, "NY Lotto: розыгрыш джекпота " .. NYRP.Money.Format(L.Data.jackpot) .. " через 10 минут! Билеты — в лотерейных автоматах ($" .. L.LottoPrice .. ").") end
	end
	if left > 600 then L.Warned = false end
end)

-- выигрыш, пока персонажа не было в игре
hook.Add("NYRP.CharacterLoaded", "nyrp.lottery", function(ply, c)
	local k = tostring(c.id)
	local sum = L.Data and L.Data.pending[k]
	if not sum then return end
	L.Data.pending[k] = nil
	L.Save()
	timer.Simple(5, function()
		if not IsValid(ply) or not ply.nyrpChar or ply.nyrpChar.id ~= c.id then
			L.Data.pending[k] = (L.Data.pending[k] or 0) + sum
			L.Save()
			return
		end
		NYRP.Money.Add(ply, sum)
		NYRP.Notify(ply, "Пока вас не было, ваш билет NY Lotto выиграл: +" .. NYRP.Money.Format(sum) .. " наличными!", "success", 12)
		hook.Run("NYRP.LottoWon", ply, sum)
	end)
end)

-- ------------------------------------------------------------- автоматы --
function L.SaveMachines()
	local out = {}
	for _, e in ipairs(ents.FindByClass("nyrp_lottery")) do
		local p, a = e:GetPos(), e:GetAngles()
		out[#out + 1] = { pos = { p.x, p.y, p.z }, ang = { a.p, a.y, a.r } }
	end
	file.CreateDir("nyrp")
	file.Write(MFILE(), util.TableToJSON(out, true))
end

function L.SpawnMachine(pos, ang)
	local e = ents.Create("nyrp_lottery")
	if not IsValid(e) then return end
	e:SetPos(pos)
	e:SetAngles(ang)
	e:Spawn()
	return e
end

local function loadMachines()
	local list = util.JSONToTable(file.Read(MFILE(), "DATA") or "") or {}
	for _, m in ipairs(list) do
		if m.pos and m.ang then
			L.SpawnMachine(Vector(m.pos[1], m.pos[2], m.pos[3]), Angle(m.ang[1], m.ang[2], m.ang[3]))
		end
	end
end
hook.Add("InitPostEntity", "nyrp.lottery", function() timer.Simple(1, loadMachines) end)
hook.Add("PostCleanupMap", "nyrp.lottery", loadMachines)

local function cmd(name, fn)
	if NYRP.Chat and NYRP.Chat.AddCommand then NYRP.Chat.AddCommand(name, fn) return end
	timer.Simple(0, function() NYRP.Chat.AddCommand(name, fn) end)
end

cmd("/lotterymachine", function(ply)
	if not ply:IsAdmin() then return end
	local tr = ply:GetEyeTrace()
	if not tr.Hit then return end
	local e = L.SpawnMachine(tr.HitPos + tr.HitNormal * 2, Angle(0, ply:EyeAngles().y + 180, 0))
	if IsValid(e) then
		L.SaveMachines()
		NYRP.Notify(ply, "Лотерейный автомат поставлен и сохранён", "success")
	end
end)

cmd("/lotteryremove", function(ply)
	if not ply:IsAdmin() then return end
	local e = ply:GetEyeTrace().Entity
	if not IsValid(e) or e:GetClass() ~= "nyrp_lottery" then NYRP.Notify(ply, "Смотрите на лотерейный автомат", "warning") return end
	e:Remove()
	timer.Simple(0, L.SaveMachines)
	NYRP.Notify(ply, "Автомат убран", "success")
end)

cmd("/lottodraw", function(ply)
	if not ply:IsSuperAdmin() then return end
	L.Draw()
end)
