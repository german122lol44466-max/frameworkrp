local Roles = NYRP.Roles

local function roleModel(r, c)
	local m = r.Model
	if istable(m) then m = (c and c.gender == "female" and m[2]) or m[1] end
	return m
end

function Roles.Apply(ply)
	local c = ply.nyrpChar
	if not c then return end
	c.flags = c.flags or {}
	if not Roles.List[c.flags.role or ""] then c.flags.role = Roles.Default end
	ply:SetNW2String("nyrp.role", c.flags.role or "")
end

hook.Add("NYRP.CharacterLoaded", "nyrp.roles", Roles.Apply)

-- модель роли (если задана) вместо модели персонажа
hook.Add("PlayerSetModel", "nyrp.roles", function(ply)
	local c = ply.nyrpChar
	local r = c and Roles.List[c.flags and c.flags.role or ""]
	local m = r and roleModel(r, c)
	if m and util.IsValidModel(m) then
		ply:SetModel(m)
		ply:SetupHands()
		return true
	end
end)

function Roles.Set(ply, id)
	local r = Roles.List[id]
	local c = ply.nyrpChar
	if not r or not c then return false end
	c.flags = c.flags or {}
	c.flags.role = id
	ply:SetNW2String("nyrp.role", id)
	for _, item in ipairs(r.Items or {}) do
		if NYRP.Items.Get(item) and NYRP.Inv.Add(ply, item, 1) <= 0 then NYRP.Inv.DropNew(ply, item, 1) end
	end
	if NYRP.Chars.Save then NYRP.Chars.Save(ply) end
	hook.Run("PlayerSetModel", ply)
	NYRP.Notify(ply, "Ваша роль: " .. r.Name, "success", 6)
	return true
end

-- зарплата в полночь
hook.Add("NYRP.NewDay", "nyrp.roles", function()
	local B = NYRP.Bank
	for _, ply in ipairs(player.GetAll()) do
		local r = NYRP.HasCharacter(ply) and Roles.Of(ply)
		if r and (r.Salary or 0) > 0 and B and B.FindCard then
			local card = B.FindCard(ply)
			if card then
				B.Add(ply, card.data.bank, r.Salary, "Зарплата: " .. r.Name)
				NYRP.Notify(ply, "Зарплата " .. NYRP.Money.Format(r.Salary) .. " пришла на карту", "success", 6)
			end
		end
	end
end)

NYRP.Chat.AddCommand("/setrole", function(ply, raw)
	if not ply:IsAdmin() then NYRP.Notify(ply, "Только для администрации", "error") return end
	local name, id = string.match(raw, "^%S+%s+(.-)%s+(%S+)$")
	if not name then
		local ids = table.concat(Roles.Order, ", ")
		NYRP.Notify(ply, "/setrole <имя персонажа> <роль>. Роли: " .. ids, "info", 8)
		return
	end
	if not Roles.List[id] then NYRP.Notify(ply, "Нет роли «" .. id .. "»", "error") return end
	name = string.lower(name)
	for _, p in ipairs(player.GetAll()) do
		if NYRP.HasCharacter(p) and string.find(string.lower(NYRP.CharName(p)), name, 1, true) then
			Roles.Set(p, id)
			NYRP.Notify(ply, NYRP.CharName(p) .. " — " .. Roles.List[id].Name, "success")
			return
		end
	end
	NYRP.Notify(ply, "Персонаж не найден", "error")
end)

-- Меню C → «Информация»: данные персонажа
net.Receive("nyrp.info", function(_, ply)
	if (ply.nyrpInfoNext or 0) > CurTime() or not NYRP.HasCharacter(ply) then return end
	ply.nyrpInfoNext = CurTime() + 1
	local c = ply.nyrpChar
	local d = { skills = c.skills or {}, height = c.height, gender = c.gender, created = c.created, playtime = 0, banks = {} }
	local B = NYRP.Bank
	if B and B.Banks then
		for id, bank in pairs(B.Banks) do
			local bal = B.Balance(ply, id)
			if bal and bal > 0 then d.banks[#d.banks + 1] = { name = bank.name, balance = bal } end
		end
	end
	local homes = {}
	if NYRP.Doors and NYRP.Doors.AccessList then
		for _, id in ipairs(NYRP.Doors.AccessList(ply)) do homes[#homes + 1] = NYRP.Doors.Data[id].name end
	end
	d.homes = homes
	net.Start("nyrp.info")
	net.WriteTable(d)
	net.Send(ply)
end)
