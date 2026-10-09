local B = NYRP.Business
NYRP.Doors = NYRP.Doors or {}
local D = NYRP.Doors

local function lic(ply) local c = ply.nyrpChar return c and c.flags and c.flags.license end

local function premises(ply)
	local list = {}
	for id, d in pairs(D.Data) do
		if d.business then
			local e = D.DoorById(id)
			list[#list + 1] = { id = id, name = d.name, price = d.price, taken = d.owner ~= nil, mine = d.owner == (ply.nyrpChar and ply.nyrpChar.id),
				bizName = d.bizName, open = d.bizOpen, dist = IsValid(e) and math.floor(e:GetPos():Distance(ply:GetPos()) * 0.019) or nil }
		end
	end
	table.sort(list, function(a, b) return (a.dist or 1e9) < (b.dist or 1e9) end)
	return list
end

local function send(ply)
	local card = NYRP.Bank.FindCard(ply)
	local c = ply.nyrpChar
	net.Start("nyrp.biz")
	net.WriteTable(lic(ply) or {})
	net.WriteTable(premises(ply))
	net.WriteString(card and card.data.bank or "")
	net.WriteDouble(card and NYRP.Bank.Balance(ply, card.data.bank) or 0)
	net.WriteString(c and c.name or "")
	net.WriteUInt(c and c.id or 0, 32)
	net.Send(ply)
end
B.Send = send

hook.Add("NYRP.NPCMenu", "nyrp.business", function(ply, ent, act) if act == "cityhall" then send(ply) end end)

net.Receive("nyrp.biz.act", function(_, ply)
	if (ply.nyrpBizNext or 0) > CurTime() or not NYRP.HasCharacter(ply) then return end
	ply.nyrpBizNext = CurTime() + 1
	local act, a1, a2 = net.ReadString(), net.ReadString(), net.ReadString()
	local c = ply.nyrpChar
	local Bk = NYRP.Bank
	if act == "license" then
		local t = B.TypeById[a1]
		local name = string.Trim(string.sub(a2 or "", 1, 32))
		if not t or utf8.len(name) == nil or utf8.len(name) < 2 then NYRP.Notify(ply, "Укажите вид деятельности и название (от 2 букв)", "error") return end
		if lic(ply) then NYRP.Notify(ply, "У вас уже есть лицензия", "warning") return end
		local card = Bk.FindCard(ply)
		if not card then NYRP.Notify(ply, "Пошлина оплачивается банковской картой", "error") return end
		if not Bk.Add(ply, card.data.bank, -t.fee, "Госпошлина: лицензия «" .. name .. "»") then
			NYRP.Notify(ply, "Недостаточно средств: пошлина " .. NYRP.Money.Format(t.fee), "error") return
		end
		local num = string.format("NYC-%02d-%06d", math.random(10, 99), (c.id * 7919 + os.time()) % 1000000)
		c.flags.license = { type = t.id, name = name, number = num, issued = os.date("%d.%m.%Y"), holder = c.name }
		NYRP.Inv.Add(ply, "business_license", 1, { number = num, name = name, type = t.id, holder = c.name })
		NYRP.Chars.Save(ply)
		ply:EmitSound("nyrp/fx/stamp.wav", 60)
		NYRP.Notify(ply, "Лицензия " .. num .. " выдана: " .. t.name .. " «" .. name .. "»", "success", 8)
		send(ply)
	elseif act == "rent" then
		local L = lic(ply)
		local d = D.Data[a1]
		if not L then NYRP.Notify(ply, "Сначала получите лицензию", "error") return end
		if not d or not d.business or d.owner then NYRP.Notify(ply, "Помещение уже занято", "warning") send(ply) return end
		for _, x in pairs(D.Data) do if x.business and x.owner == c.id then NYRP.Notify(ply, "У вас уже есть коммерческое помещение", "warning") return end end
		local card = Bk.FindCard(ply)
		if not card or not Bk.Add(ply, card.data.bank, -d.price, "Аренда помещения «" .. d.name .. "» (первый день)") then
			NYRP.Notify(ply, "Недостаточно средств на карте", "error") return
		end
		d.owner, d.ownerName, d.ownerKey, d.bank = c.id, c.name, NYRP.Chars.Key(ply), card.data.bank
		d.paidUntil = NYRP.Phone and NYRP.Phone.DayIndex() or 0
		d.locked, d.bizOpen = true, false
		d.bizName = L.name
		d.bizType = (B.TypeById[L.type] or {}).name
		d.name = d.name
		D.Save()
		D.Apply(a1)
		local e = D.DoorById(a1)
		if IsValid(e) then e:SetNW2String("nyrp.rentName", L.name) end
		ply:EmitSound("nyrp/fx/stamp.wav", 60)
		NYRP.Notify(ply, "Помещение ваше: «" .. L.name .. "». Метка поставлена, ключи — в почтовом ящике. F1 по двери — открыть бизнес.", "success", 10)
		D.Mark(ply, a1)
		send(ply)
	elseif act == "mark" then
		D.Mark(ply, a1)
	elseif act == "toggle" then
		local d = D.Data[a1]
		if not d or not d.business or d.owner ~= c.id then return end
		d.bizOpen = not d.bizOpen
		if d.bizOpen then d.locked = false end
		D.Save()
		D.Apply(a1)
		NYRP.Notify(ply, d.bizOpen and "«" .. (d.bizName or d.name) .. "» открыт. Выручка идёт, пока вы рядом." or "Бизнес закрыт", "success")
	end
end)

-- название бизнеса на табличке двери после перезапуска
hook.Add("InitPostEntity", "nyrp.business", function()
	timer.Simple(3, function()
		for id, d in pairs(D.Data) do
			if d.business and d.bizName then local e = D.DoorById(id) if IsValid(e) then e:SetNW2String("nyrp.rentName", d.bizName) end end
		end
	end)
end)

-- выручка: каждые 10 минут, если открыто и владелец в 25 м
timer.Create("nyrp.business.income", 600, 0, function()
	for id, d in pairs(D.Data) do
		if d.business and d.owner and d.bizOpen then
			local e = D.DoorById(id)
			for _, p in ipairs(player.GetAll()) do
				if p.nyrpChar and p.nyrpChar.id == d.owner and IsValid(e) and p:GetPos():Distance(e:GetPos()) < 1300 then
					local L = p.nyrpChar.flags.license
					local t = B.TypeById[L and L.type or ""] or B.Types[1]
					local sum = math.random(t.income[1], t.income[2])
					NYRP.Bank.Add(p, d.bank, sum, "Выручка «" .. (d.bizName or d.name) .. "»")
					p:EmitSound("nyrp/fx/cash.wav", 50)
					NYRP.Notify(p, "Выручка «" .. (d.bizName or d.name) .. "»: +" .. NYRP.Money.Format(sum) .. " на счёт", "success", 6)
					if NYRP.Skills then NYRP.Skills.AddXP(p, "intellect", 6) end
				end
			end
		end
	end
end)

-- кассы для грабителей — у открытых бизнесов
function B.RandomShopSpot(from)
	local list = {}
	for id, d in pairs(D.Data) do
		if d.business and d.owner then
			local e = D.DoorById(id)
			if IsValid(e) then list[#list + 1] = e end
		end
	end
	if #list == 0 then return end
	local e = list[math.random(#list)]
	local c = e:WorldSpaceCenter()
	for _, s in ipairs({ 1, -1 }) do
		local tr = util.TraceLine({ start = c + e:GetRight() * 50 * s, endpos = c + e:GetRight() * 50 * s - Vector(0, 0, 120) })
		if tr.Hit then return tr.HitPos end
	end
end
