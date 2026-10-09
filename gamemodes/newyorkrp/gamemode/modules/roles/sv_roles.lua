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
	hook.Run("NYRP.RoleChanged", ply, id)
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

-- ------------------------------------------------------------ наигранное время --
timer.Create("nyrp.roles.played", 60, 0, function()
	for _, ply in ipairs(player.GetAll()) do
		local c = ply.nyrpChar
		if c and ply:Alive() then
			c.flags = c.flags or {}
			c.flags.played = (c.flags.played or 0) + 60
		end
	end
end)

local function members(id)
	local n = 0
	for _, p in ipairs(player.GetAll()) do if p:GetNW2String("nyrp.role") == id then n = n + 1 end end
	return n
end
Roles.Members = members

-- что мешает вступить: список строк (пусто — можно)
function Roles.Check(ply, id)
	local r = Roles.List[id]
	local c = ply.nyrpChar
	local out = {}
	if not r or not c then return { "Нет такой службы" } end
	local hours = (c.flags and c.flags.played or 0) / 3600
	if (r.MinHours or 0) > 0 and hours < r.MinHours then
		out[#out + 1] = string.format("Отыграть %d ч (сейчас %.1f ч)", r.MinHours, hours)
	end
	for sk, lvl in pairs(r.MinSkills or {}) do
		local have = c.skills and c.skills[sk] or 0
		if have < lvl then
			local name = sk
			for _, s in ipairs(NYRP.Config.Skills) do if s.id == sk then name = s.name end end
			out[#out + 1] = "Навык «" .. name .. "» " .. lvl .. " (у вас " .. have .. ")"
		end
	end
	if (r.MaxMembers or 0) > 0 and members(id) >= r.MaxMembers then out[#out + 1] = "Нет свободных мест (" .. r.MaxMembers .. ")" end
	return out
end

local function sendFactions(ply)
	local list = {}
	for _, id in ipairs(Roles.Order) do
		local r = Roles.List[id]
		local c = ply.nyrpChar
		list[#list + 1] = { id = id, members = members(id), problems = Roles.Check(ply, id),
			applied = c and c.flags and c.flags.roleApply == id or false }
	end
	net.Start("nyrp.fac")
	net.WriteTable(list)
	net.WriteFloat(ply.nyrpChar and ply.nyrpChar.flags and ply.nyrpChar.flags.played or 0)
	net.Send(ply)
end

hook.Add("NYRP.NPCMenu", "nyrp.roles", function(ply, ent, act)
	if act == "factions" then sendFactions(ply) end
end)

-- заявки (вайтлист): data/nyrp/role_applications.json
local APP = "nyrp/role_applications.json"
local function apps() return util.JSONToTable(file.Read(APP, "DATA") or "") or {} end
local function saveApps(t) file.CreateDir("nyrp") file.Write(APP, util.TableToJSON(t, true)) end

net.Receive("nyrp.fac.act", function(_, ply)
	if (ply.nyrpFacNext or 0) > CurTime() or not NYRP.HasCharacter(ply) then return end
	ply.nyrpFacNext = CurTime() + 1
	local act, id = net.ReadString(), net.ReadString()
	local r = Roles.List[id]
	local c = ply.nyrpChar
	if act == "leave" then
		if ply:GetNW2String("nyrp.role") == Roles.Default then return end
		Roles.Set(ply, Roles.Default)
		NYRP.Notify(ply, "Вы ушли со службы", "info")
		sendFactions(ply)
		return
	end
	if act ~= "join" or not r or r.Default then return end
	if ply:GetNW2String("nyrp.role") == id then return end
	local problems = Roles.Check(ply, id)
	if #problems > 0 then NYRP.Notify(ply, "Пока нельзя: " .. problems[1], "error", 6) return end
	if r.Whitelist then
		local t = apps()
		t[tostring(c.id)] = { role = id, name = c.name, steam = ply:SteamID(), time = os.time() }
		saveApps(t)
		c.flags.roleApply = id
		NYRP.Notify(ply, "Заявка в «" .. r.Name .. "» отправлена. Её рассмотрит администрация.", "success", 7)
		for _, a in ipairs(player.GetAll()) do
			if a:IsAdmin() then NYRP.Notify(a, "Заявка: " .. c.name .. " → " .. r.Name .. ". Принять: /facaccept " .. c.name, "info", 10) end
		end
	else
		Roles.Set(ply, id)
		ply:EmitSound("nyrp/fx/stamp.wav", 60)
	end
	sendFactions(ply)
end)

NYRP.Chat.AddCommand("/facaccept", function(ply, raw)
	if not ply:IsAdmin() then return end
	local name = string.lower(string.Trim(string.match(raw, "^%S+%s+(.+)$") or ""))
	if name == "" then
		local t = apps()
		local list = {}
		for _, a in pairs(t) do list[#list + 1] = a.name .. " → " .. (Roles.List[a.role] and Roles.List[a.role].Name or a.role) end
		NYRP.Notify(ply, #list > 0 and ("Заявки: " .. table.concat(list, "; ")) or "Заявок нет", "info", 10)
		return
	end
	for _, p in ipairs(player.GetAll()) do
		local c = p.nyrpChar
		if c and string.find(string.lower(c.name), name, 1, true) and c.flags and c.flags.roleApply then
			local id = c.flags.roleApply
			c.flags.roleApply = nil
			local t = apps() t[tostring(c.id)] = nil saveApps(t)
			Roles.Set(p, id)
			NYRP.Notify(ply, "Принят: " .. c.name, "success")
			return
		end
	end
	NYRP.Notify(ply, "Онлайн нет такого персонажа с заявкой", "error")
end)
