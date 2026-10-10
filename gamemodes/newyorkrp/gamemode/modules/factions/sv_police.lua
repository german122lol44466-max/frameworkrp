--[[
	NYPD: руки задержанного за спиной (наручники на запястьях), меню задержанного (R с наручниками):
	обыск (изъять вещи), посадить в КПЗ на время, снять наручники.
	КПЗ: /jailpoint — точка камеры (несколько), /jailrelease — точка выхода, /jailclear — убрать все.
	Срок хранится на персонаже (перезаход не помогает). Судимости — во вкладке терминала NYPD.
]]
local F = NYRP.Factions
local Inv = NYRP.Inv

-- ------------------------------------------------------ руки за спиной --
local POSE = {
	["ValveBiped.Bip01_R_UpperArm"] = Angle(-28, 18, -21),
	["ValveBiped.Bip01_L_UpperArm"] = Angle(15, 26, 0),
	["ValveBiped.Bip01_R_Forearm"] = Angle(0, 50, 0),
	["ValveBiped.Bip01_L_Forearm"] = Angle(15, 20, 40),
	["ValveBiped.Bip01_R_Hand"] = Angle(45, 34, -15),
	["ValveBiped.Bip01_L_Hand"] = Angle(0, 0, 119),
}
function F.CuffPose(ply, on)
	for name, a in pairs(POSE) do
		local b = ply:LookupBone(name)
		if b then ply:ManipulateBoneAngles(b, on and a or angle_zero) end
	end
end
local oldCuff = F.Cuff
function F.Cuff(ply, target, on)
	oldCuff(ply, target, on)
	F.CuffPose(target, on)
end
hook.Add("PlayerSpawn", "nyrp.cuffs.pose", function(ply) F.CuffPose(ply, false) end)

-- ------------------------------------------------------------ КПЗ --
local function jailFile() return "nyrp/jail_" .. game.GetMap() .. ".json" end
F.Jail = util.JSONToTable(file.Read(jailFile(), "DATA") or "") or { cells = {}, release = nil }
local function saveJail()
	file.CreateDir("nyrp")
	file.Write(jailFile(), util.TableToJSON(F.Jail, true))
end
local function v(t) return Vector(t[1], t[2], t[3]) end

NYRP.Chat.AddCommand("/jailpoint", function(ply)
	if not ply:IsAdmin() then return end
	local p = ply:GetPos()
	table.insert(F.Jail.cells, { p.x, p.y, p.z })
	saveJail()
	NYRP.Notify(ply, "Точка камеры КПЗ #" .. #F.Jail.cells .. " сохранена", "success")
end)
NYRP.Chat.AddCommand("/jailrelease", function(ply)
	if not ply:IsAdmin() then return end
	local p = ply:GetPos()
	F.Jail.release = { p.x, p.y, p.z }
	saveJail()
	NYRP.Notify(ply, "Точка выхода из КПЗ сохранена", "success")
end)
NYRP.Chat.AddCommand("/jailclear", function(ply)
	if not ply:IsAdmin() then return end
	F.Jail = { cells = {}, release = nil }
	saveJail()
	NYRP.Notify(ply, "Точки КПЗ удалены", "info")
end)

-- судимости: имя персонажа -> список
local RECORDS = "nyrp/police_records.json"
F.Records = util.JSONToTable(file.Read(RECORDS, "DATA") or "") or {}
local function addRecord(name, rec)
	F.Records[name] = F.Records[name] or {}
	table.insert(F.Records[name], 1, rec)
	while #F.Records[name] > 20 do table.remove(F.Records[name]) end
	file.CreateDir("nyrp")
	file.Write(RECORDS, util.TableToJSON(F.Records, true))
end

local function putInCell(ply)
	local cells = F.Jail.cells
	if #cells == 0 then return false end
	ply:SetPos(v(cells[math.random(#cells)]))
	return true
end

function F.Jailed(ply) return ply:GetNW2Float("nyrp.jailUntil", 0) > CurTime() end

function F.Arrest(cop, target, minutes, reason)
	if #F.Jail.cells == 0 then NYRP.Notify(cop, "КПЗ не настроено: администратор ставит /jailpoint", "error") return end
	minutes = math.Clamp(math.floor(minutes), 1, 30)
	if F.Cuffed(target) then F.Cuff(cop, target, false) end
	target.nyrpDraggedBy = nil
	if NYRP.Sit and NYRP.Sit.StandUp then NYRP.Sit.StandUp(target, true) end
	putInCell(target)
	target:SetNW2Float("nyrp.jailUntil", CurTime() + minutes * 60)
	target:SetNW2String("nyrp.jailReason", reason)
	local c = target.nyrpChar
	if c then
		c.flags = c.flags or {}
		c.flags.jailUntil = os.time() + minutes * 60
		c.flags.jailReason = reason
		NYRP.Chars.Save(target)
	end
	target:SetNW2Float("nyrp.wantedUntil", 0)
	addRecord(NYRP.CharName(target), { t = os.time(), date = os.date("%d.%m.%Y %H:%M"), reason = reason, minutes = minutes, officer = NYRP.CharName(cop) })
	NYRP.Notify(target, "Вы арестованы на " .. minutes .. " мин. Статья: " .. reason, "warning", 10)
	NYRP.Notify(cop, "Задержанный помещён в КПЗ на " .. minutes .. " мин", "success")
	if cop:GetNW2String("nyrp.role", "") == "police" then
		NYRP.Money.Add(cop, 30 + minutes * 5)
		cop:EmitSound("nyrp/fx/cash.wav", 50)
	end
	target:EmitSound("doors/door_metal_large_close2.wav", 70)
end

local function release(ply)
	ply:SetNW2Float("nyrp.jailUntil", 0)
	local c = ply.nyrpChar
	if c and c.flags then c.flags.jailUntil, c.flags.jailReason = nil, nil NYRP.Chars.Save(ply) end
	if F.Jail.release then ply:SetPos(v(F.Jail.release)) end
	NYRP.Notify(ply, "Срок окончен — вы свободны", "success", 6)
end

timer.Create("nyrp.jail", 1, 0, function()
	for _, p in ipairs(player.GetAll()) do
		local u = p:GetNW2Float("nyrp.jailUntil", 0)
		if u > 0 then
			if CurTime() >= u then
				release(p)
			elseif p:Alive() then
				-- сбежал из камеры — вернуть
				local near = false
				for _, c in ipairs(F.Jail.cells) do if p:GetPos():DistToSqr(v(c)) < 350 * 350 then near = true end end
				if not near then putInCell(p) end
			end
		end
	end
end)
-- срок сохраняется на персонаже
hook.Add("NYRP.PlayerSpawned", "nyrp.jail", function(ply)
	local c = ply.nyrpChar
	local left = c and c.flags and c.flags.jailUntil and (c.flags.jailUntil - os.time()) or 0
	if left > 0 and #F.Jail.cells > 0 then
		timer.Simple(0.5, function()
			if not IsValid(ply) then return end
			ply:SetNW2Float("nyrp.jailUntil", CurTime() + left)
			ply:SetNW2String("nyrp.jailReason", c.flags.jailReason or "")
			putInCell(ply)
		end)
	elseif ply:GetNW2Float("nyrp.jailUntil", 0) > CurTime() then
		timer.Simple(0.5, function() if IsValid(ply) then putInCell(ply) end end)
	end
end)

-- ------------------------------------------------ меню задержанного --
function F.OpenSuspectMenu(cop, target)
	net.Start("nyrp.police.menu")
	net.WriteEntity(target)
	net.WriteBool(#F.Jail.cells > 0)
	net.Send(cop)
end

local function itemList(target)
	local inv = Inv.Get(target)
	local out = {}
	for i, it in pairs(inv.slots) do
		local d = NYRP.Items.Get(it.id)
		if d then out[#out + 1] = { key = "s" .. i, name = d.name, n = it.n, cat = d.category } end
	end
	for k, it in pairs(inv.equip) do
		local d = NYRP.Items.Get(it.id)
		if d then out[#out + 1] = { key = "e" .. k, name = d.name, n = it.n, cat = d.category, worn = true } end
	end
	return out
end

local function sendSearch(cop, target)
	net.Start("nyrp.police.search")
	net.WriteEntity(target)
	net.WriteTable(itemList(target))
	net.WriteUInt(math.max(0, math.floor(NYRP.Money.Get and NYRP.Money.Get(target) or 0)), 32)
	net.Send(cop)
end

net.Receive("nyrp.police.act", function(_, cop)
	if (cop.nyrpPoliceNext or 0) > CurTime() then return end
	cop.nyrpPoliceNext = CurTime() + 0.4
	local target, act, a, b = net.ReadEntity(), net.ReadString(), net.ReadString(), net.ReadString()
	if not IsValid(target) or not target:IsPlayer() or not F.Cuffed(target) or target:GetPos():Distance(cop:GetPos()) > 130 then return end
	if act == "search" then
		NYRP.Action(cop, "Обыскиваю...", 3, function()
			if IsValid(target) and target:GetPos():Distance(cop:GetPos()) < 130 then
				sendSearch(cop, target)
				NYRP.Notify(target, "Вас обыскивают", "warning")
			end
		end, "hand")
	elseif act == "take" then
		local inv = Inv.Get(target)
		local kind, key = string.sub(a, 1, 1), string.sub(a, 2)
		local it = kind == "s" and inv.slots[tonumber(key) or -1] or (kind == "e" and inv.equip[key])
		if not it then return end
		local def = NYRP.Items.Get(it.id)
		if Inv.Add(cop, it.id, it.n, it.data) <= 0 then NYRP.Notify(cop, "В сумке нет места", "error") return end
		if kind == "s" then
			inv.slots[tonumber(key)] = nil
		else
			inv.equip[key] = nil
			if def and def.class and target:HasWeapon(def.class) then target:StripWeapon(def.class) end
			Inv.ApplyEquipment(target)
		end
		Inv.Sync(target)
		NYRP.Notify(cop, "Изъято: " .. (def and def.name or it.id), "success")
		NYRP.Notify(target, "У вас изъяли: " .. (def and def.name or it.id), "warning")
		sendSearch(cop, target)
	elseif act == "jail" then
		F.Arrest(cop, target, tonumber(a) or 5, string.sub(b ~= "" and b or "Задержание NYPD", 1, 80))
	elseif act == "uncuff" then
		NYRP.Action(cop, "Снимаю наручники...", 2, function()
			if IsValid(target) and target:GetPos():Distance(cop:GetPos()) < 130 then F.Cuff(cop, target, false) end
		end, "unlock")
	elseif act == "lead" then
		target.nyrpDraggedBy = target.nyrpDraggedBy ~= cop and cop or nil
	end
end)

-- последние аресты для терминала NYPD
function F.RecentRecords(limit)
	local all = {}
	for name, list in pairs(F.Records) do
		for _, r in ipairs(list) do all[#all + 1] = { name = name, date = r.date, reason = r.reason, minutes = r.minutes, officer = r.officer, t = r.t or 0, total = #list } end
	end
	table.sort(all, function(a, b) return a.t > b.t end)
	local out = {}
	for i = 1, math.min(limit or 40, #all) do out[i] = all[i] end
	return out
end
