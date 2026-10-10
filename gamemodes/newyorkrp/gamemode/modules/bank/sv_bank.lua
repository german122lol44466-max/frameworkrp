--[[
	Банк на сервере: счета персонажа, выдача карты, штрафы, сеансы банкомата, сохранение банкоматов карты.
	Админ: nyrp_spawnatm [liberty|hudson|empire] — поставить банкомат (сохраняется для карты),
	       nyrp_fine <часть имени> <сумма> <причина> — выписать штраф.
]]

local B = NYRP.Bank
local Inv = NYRP.Inv

-- ------------------------------------------------------------------ счета --
local function flags(ply)
	local c = ply.nyrpChar
	if not c then return end
	c.flags = c.flags or {}
	c.flags.bank = c.flags.bank or {}
	c.flags.bankLog = c.flags.bankLog or {}
	c.flags.fines = c.flags.fines or {}
	return c.flags
end
B.Flags = flags

function B.Balance(ply, bank)
	local f = flags(ply)
	return f and f.bank[bank] or 0
end

local function today() return NYRP.Phone and NYRP.Phone.DayIndex() or 0 end

function B.Log(ply, bank, text, amount)
	local f = flags(ply)
	if not f then return end
	f.bankLog[bank] = f.bankLog[bank] or {}
	table.insert(f.bankLog[bank], 1, { text = text, amount = amount, day = today(), time = NYRP.Time.Format() })
	while #f.bankLog[bank] > 15 do table.remove(f.bankLog[bank]) end
end

-- Изменить счёт (amount может быть отрицательным). false — если не хватает средств.
function B.Add(ply, bank, amount, text)
	local f = flags(ply)
	if not f or not B.Banks[bank] then return false end
	local bal = f.bank[bank] or 0
	if bal + amount < 0 then return false end
	f.bank[bank] = bal + amount
	if text then B.Log(ply, bank, text, amount) end
	return true
end

-- Первая карта в сумке (или nil)
function B.FindCard(ply)
	local inv = Inv.Get(ply)
	for i = 1, Inv.Size(ply) do
		local it = inv.slots[i]
		if it and it.id == "bankcard" and it.data and it.data.number then return it, i end
	end
end

-- -------------------------------------------------------------- выдача карты --
local function luhn(digits)
	local sum, alt = 0, true
	for i = #digits, 1, -1 do
		local d = tonumber(digits:sub(i, i))
		if alt then d = d * 2 if d > 9 then d = d - 9 end end
		sum = sum + d
		alt = not alt
	end
	return (10 - sum % 10) % 10
end

function B.NewCard(ply, bank)
	local c = ply.nyrpChar
	local body = "4" .. string.format("%03d", math.random(0, 999)) .. string.format("%04d%04d", math.random(0, 9999), math.random(0, 9999)) .. string.format("%03d", math.random(0, 999))
	local d = os.date("*t")
	return {
		bank = bank, number = body .. luhn(body), holder = string.upper(c and c.name or "CARDHOLDER"),
		exp = string.format("%02d/%02d", math.random(1, 12), (d.year + 4) % 100),
		cvv = string.format("%03d", math.random(0, 999)), pin = string.format("%04d", math.random(0, 9999)),
	}
end

hook.Add("NYRP.CharInventoryReady", "nyrp.bank", function(ply, c)
	c.flags = c.flags or {}
	if c.flags.cardIssued then return end
	c.flags.cardIssued = true
	local bank = B.Order[math.random(#B.Order)]
	local card = B.NewCard(ply, bank)
	Inv.Add(ply, "bankcard", 1, card)
	B.Add(ply, bank, B.StartBalance, "Приветственный бонус")
	NYRP.Notify(ply, "Вам выдана карта " .. B.Banks[bank].name .. ". PIN-код: " .. card.pin .. " (виден в инвентаре: ПКМ → Посмотреть).", "item", 10)
end)

-- --------------------------------------------------------------- штрафы --
function B.AddFine(ply, amount, reason)
	local f = flags(ply)
	if not f then return end
	f.fineSeq = (f.fineSeq or 0) + 1
	table.insert(f.fines, { id = f.fineSeq, amount = math.floor(amount), reason = string.sub(reason or "", 1, 80), day = today() })
	NYRP.Notify(ply, "Вам выписан штраф " .. NYRP.Money.Format(amount) .. ": " .. (reason or "") .. ". Оплатить можно в любом банкомате.", "warning", 8)
end

concommand.Add("nyrp_fine", function(ply, _, args)
	if IsValid(ply) and not ply:IsAdmin() then return end
	local part, amount = string.lower(args[1] or ""), tonumber(args[2] or "")
	local reason = table.concat(args, " ", 3)
	if part == "" or not amount or amount <= 0 then print("nyrp_fine <часть имени> <сумма> <причина>") return end
	for _, p in ipairs(player.GetAll()) do
		if NYRP.HasCharacter(p) and string.find(string.lower(p:GetNW2String("nyrp.name", p:Nick())), part, 1, true) then
			B.AddFine(p, amount, reason ~= "" and reason or "Нарушение")
			if IsValid(ply) then NYRP.Notify(ply, "Штраф выписан: " .. p:GetNW2String("nyrp.name", p:Nick()), "success") end
			return
		end
	end
end)

-- ---------------------------------------------------------- банкомат: сеанс --
-- ply.nyrpATM = { ent, card (предмет), authed, tries }
local function send(ply, msg)
	local s = ply.nyrpATM
	if not s then return end
	local it = s.card
	local bank = it.data.bank
	net.Start("nyrp.atm.info")
	net.WriteBool(s.authed)
	net.WriteString(msg or "")
	if s.authed then
		local f = flags(ply)
		net.WriteDouble(B.Balance(ply, bank))
		net.WriteDouble(NYRP.Money.Get(ply))
		net.WriteTable(f and f.fines or {})
		net.WriteTable(f and f.bankLog[bank] or {})
	end
	net.Send(ply)
end

function B.EndATM(ply, silent)
	local s = ply.nyrpATM
	if not s then return end
	ply.nyrpATM = nil
	if IsValid(s.ent) and s.ent:GetUser() == ply then s.ent:SetUser(NULL) end
	if not silent then
		net.Start("nyrp.atm.close")
		net.Send(ply)
	end
end

function B.StartATM(ply, ent)
	if not NYRP.HasCharacter(ply) or not ply:Alive() then return end
	-- «зависший» прошлый сеанс (клиент его закрыл, а сервер не узнал) больше не блокирует банкомат
	if ply.nyrpATM then
		if ply.nyrpATM.ent == ent and (ply.nyrpATM.started or 0) > CurTime() - 2 then return end
		B.EndATM(ply, true)
	end
	local user = ent:GetUser()
	if IsValid(user) and user ~= ply then NYRP.Notify(ply, "Банкоматом сейчас пользуются", "warning") return end
	local card = B.FindCard(ply)
	if not card then NYRP.Notify(ply, "Нужна банковская карта", "warning") return end
	ent:SetUser(ply)
	ply.nyrpATM = { ent = ent, card = card, authed = false, tries = 0, started = CurTime() }
	local own = B.Banks[card.data.bank] and card.data.bank or "liberty"
	net.Start("nyrp.atm.open")
	net.WriteEntity(ent)
	net.WriteString(own)
	net.WriteString(card.data.number)
	net.WriteString(card.data.holder or "")
	net.Send(ply)
	ply:EmitSound("nyrp/fx/cloth_off.wav", 50, 120, 0.5)
end

local function valid(ply)
	local s = ply.nyrpATM
	if not s then return end
	if not IsValid(s.ent) or not ply:Alive() or ply:GetPos():Distance(s.ent:GetPos()) > 150 then B.EndATM(ply) return end
	-- карту нельзя «вынуть» из сумки во время сеанса
	local card = B.FindCard(ply)
	if card ~= s.card then B.EndATM(ply) return end
	return s
end

net.Receive("nyrp.atm.pin", function(_, ply)
	local s = valid(ply)
	if not s or s.authed then return end
	local pin = net.ReadString()
	if pin == s.card.data.pin then
		s.authed = true
		s.ent:EmitSound("buttons/button14.wav", 50, 120)
		send(ply)
	else
		s.tries = s.tries + 1
		s.ent:EmitSound("buttons/button10.wav", 50, 100)
		if s.tries >= 3 then
			send(ply, "Неверный PIN три раза — сеанс завершён")
			timer.Simple(1.5, function() if IsValid(ply) then B.EndATM(ply) end end)
		else
			send(ply, "Неверный PIN. Осталось попыток: " .. (3 - s.tries))
		end
	end
end)

net.Receive("nyrp.atm.op", function(_, ply)
	if (ply.nyrpATMNext or 0) > CurTime() then return end
	ply.nyrpATMNext = CurTime() + 0.3
	local op = net.ReadString()
	local arg = math.floor(math.max(0, net.ReadDouble()))
	local s = valid(ply)
	if not s then return end
	if op == "close" then B.EndATM(ply, true) return end
	if not s.authed then return end
	local bank = s.card.data.bank
	local atmBank = s.ent:GetBank()
	local fee = atmBank ~= bank and B.ForeignFee or 0
	if op == "withdraw" then
		if arg <= 0 then return end
		if not B.Add(ply, bank, -(arg + fee), "Снятие наличных" .. (fee > 0 and (" (комиссия " .. NYRP.Money.Format(fee) .. ")") or "")) then
			send(ply, "Недостаточно средств на счёте")
			return
		end
		NYRP.Money.Add(ply, arg)
		s.ent:EmitSound("ambient/levels/labs/coinslot1.wav", 55, 110)
		send(ply, "Заберите наличные: " .. NYRP.Money.Format(arg))
	elseif op == "deposit" then
		if arg <= 0 then return end
		if NYRP.Money.Get(ply) < arg then send(ply, "У вас нет столько наличных") return end
		NYRP.Money.Add(ply, -arg)
		B.Add(ply, bank, arg, "Внесение наличных")
		s.ent:EmitSound("ambient/levels/labs/coinslot1.wav", 55, 90)
		send(ply, "Счёт пополнен на " .. NYRP.Money.Format(arg))
	elseif op == "fine" then
		local f = flags(ply)
		for i, fn in ipairs(f.fines) do
			if fn.id == arg then
				if not B.Add(ply, bank, -fn.amount, "Оплата штрафа: " .. fn.reason) then send(ply, "Недостаточно средств для оплаты штрафа") return end
				table.remove(f.fines, i)
				send(ply, "Штраф оплачен")
				return
			end
		end
	else
		send(ply)
	end
end)

hook.Add("PlayerDeath", "nyrp.atm", function(ply) B.EndATM(ply) end)
-- отошёл от банкомата / банкомат удалили — сеанс закрывается и на сервере
timer.Create("nyrp.atm.watch", 1, 0, function()
	for _, p in ipairs(player.GetAll()) do
		local s = p.nyrpATM
		if s and (not IsValid(s.ent) or not p:Alive() or p:GetPos():DistToSqr(s.ent:GetPos()) > 200 * 200) then B.EndATM(p) end
	end
end)
hook.Add("PlayerDisconnected", "nyrp.atm", function(ply) B.EndATM(ply, true) end)

-- --------------------------------------------- банкоматы карты: сохранение --
local function file_() return "nyrp/atms_" .. game.GetMap() .. ".json" end

function B.SaveATMs()
	if B.Loading then return end
	local out = {}
	for _, e in ipairs(ents.FindByClass("nyrp_atm")) do
		local p, a = e:GetPos(), e:GetAngles()
		out[#out + 1] = { pos = { p.x, p.y, p.z }, ang = { a.p, a.y, a.r }, bank = e:GetBank() }
	end
	file.CreateDir("nyrp")
	file.Write(file_(), util.TableToJSON(out, true))
end

function B.SpawnATM(pos, ang, bank)
	local e = ents.Create("nyrp_atm")
	e:SetPos(pos)
	e:SetAngles(ang)
	e:Spawn()
	e:SetBank(B.Banks[bank] and bank or "liberty")
	return e
end

local function loadATMs()
	B.Loading = true
	for _, e in ipairs(ents.FindByClass("nyrp_atm")) do e:Remove() end
	for _, d in ipairs(util.JSONToTable(file.Read(file_(), "DATA") or "") or {}) do
		B.SpawnATM(Vector(d.pos[1], d.pos[2], d.pos[3]), Angle(d.ang[1], d.ang[2], d.ang[3]), d.bank)
	end
	B.Loading = false
end
hook.Add("InitPostEntity", "nyrp.atm", function(...) loadATMs(...) end)
hook.Add("PostCleanupMap", "nyrp.atm", function(...) loadATMs(...) end)

concommand.Add("nyrp_spawnatm", function(ply, _, args)
	if not IsValid(ply) or not ply:IsSuperAdmin() then return end
	local tr = ply:GetEyeTrace()
	local ang = Angle(0, ply:EyeAngles().y + 180, 0)
	local e = B.SpawnATM(tr.HitPos, ang, args[1] or "liberty")
	if NYRP.SnapToFloor then NYRP.SnapToFloor(e) end
	B.SaveATMs()
	undo.Create("Банкомат")
	undo.AddEntity(e)
	undo.SetPlayer(ply)
	undo.Finish()
	NYRP.Notify(ply, "Банкомат " .. B.Banks[e:GetBank()].name .. " поставлен и сохранён", "success")
end)

-- C-меню: сменить банк / удалить (только админы)
net.Receive("nyrp.atm.close", function(_, ply)
	-- клиент просит закрыть сеанс (Esc / ПКМ)
	if ply.nyrpATM then B.EndATM(ply, true) end
end)
