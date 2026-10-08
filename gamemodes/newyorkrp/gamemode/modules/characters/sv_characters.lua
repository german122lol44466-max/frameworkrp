--[[
	Персонажи: хранение в SQLite, создание, загрузка, удаление, выход в меню.
	Если камеры меню на карте не расставлены — игрок сразу попадает за персонажа:
	последнего / первого из своих, а если их нет — за нового случайного.
]]

local Chars = NYRP.Chars
local DB = NYRP.DB
local Q, E = DB.Query, DB.Escape

local function decode(s, def)
	local ok, t = pcall(util.JSONToTable, s or "")
	return (ok and t) or def
end

local function rowToChar(r)
	return {
		id = tonumber(r.id), steamid = r.steamid, name = r.name, description = r.description, gender = r.gender,
		model = r.model, height = tonumber(r.height) or 175, skills = decode(r.skills, {}), bag = r.bag,
		inventory = decode(r.inventory, {}), equipment = decode(r.equipment, {}),
		hunger = tonumber(r.hunger) or 100, thirst = tonumber(r.thirst) or 100, health = tonumber(r.health) or 100,
		recognized = decode(r.recognized, {}), flags = decode(r.flags, {}),
	}
end

-- Ключ владельца: SteamID64, у ботов — отдельный ключ по нику (их персонажи не смешиваются с игроками).
function Chars.Key(ply)
	if ply:IsBot() then return "BOT:" .. ply:Nick() end
	return ply:SteamID64() or ply:SteamID()
end

function Chars.List(ply)
	local rows = Q("SELECT * FROM nyrp_characters WHERE steamid = " .. E(Chars.Key(ply)) .. " ORDER BY id ASC") or {}
	local out = {}
	for _, r in ipairs(rows) do out[#out + 1] = rowToChar(r) end
	return out
end

function Chars.MaxFor()
	local spots = NYRP.Points.Data and #NYRP.Points.Data.spots or 0
	return spots > 0 and spots or NYRP.Config.MaxCharacters
end

function Chars.SendList(ply)
	local list = Chars.List(ply)
	net.Start("nyrp.char.list")
	net.WriteUInt(#list, 8)
	for _, c in ipairs(list) do
		net.WriteUInt(c.id, 32)
		net.WriteString(c.name)
		net.WriteString(c.description)
		net.WriteString(c.gender)
		net.WriteString(c.model)
		net.WriteUInt(c.height, 8)
		net.WriteString(c.bag or "waistbag")
	end
	net.WriteUInt(Chars.MaxFor(), 8)
	net.Send(ply)
end

function Chars.Insert(ply, d)
	Q(string.format([[INSERT INTO nyrp_characters (steamid, name, description, gender, model, height, skills, bag, inventory, equipment, created, flags)
		VALUES (%s, %s, %s, %s, %s, %d, %s, %s, '[]', '{}', %d, '{}')]],
		E(Chars.Key(ply)), E(d.name), E(d.description), E(d.gender), E(d.model), d.height, E(util.TableToJSON(d.skills)), E(d.bag), os.time()))
	return tonumber(sql.QueryValue("SELECT last_insert_rowid()"))
end

function Chars.Save(ply)
	local c = ply.nyrpChar
	if not c then return end
	local inv, eq = {}, {}
	if NYRP.Inv then inv, eq = NYRP.Inv.Export(ply) end
	Q(string.format("UPDATE nyrp_characters SET inventory = %s, equipment = %s, hunger = %f, thirst = %f, health = %d, recognized = %s, flags = %s WHERE id = %d",
		E(util.TableToJSON(inv)), E(util.TableToJSON(eq)),
		ply:GetNW2Float("nyrp.hunger", 100), ply:GetNW2Float("nyrp.thirst", 100),
		ply:Alive() and ply:Health() or 100,
		E(util.TableToJSON(NYRP.Recog.Export and NYRP.Recog.Export(ply) or {})), E(util.TableToJSON(c.flags or {})), c.id))
end

local function savePlaytime(ply)
	if not ply.nyrpJoined then return end
	local total = (ply.nyrpPlaytime or 0) + math.floor(CurTime() - ply.nyrpJoined)
	Q(string.format("REPLACE INTO nyrp_players (steamid, playtime, last_char) VALUES (%s, %d, %d)",
		E(Chars.Key(ply)), total, ply.nyrpChar and ply.nyrpChar.id or (ply.nyrpLastChar or 0)))
end

-- Удостоверение личности выдаётся один раз — при первом входе персонажа.
local function issueID(ply, c)
	c.flags = c.flags or {}
	if c.flags.idIssued then return end
	c.flags.idIssued = true
	if NYRP.Inv then
		NYRP.Inv.Add(ply, "idcard", 1, {
			char = c.id, name = c.name, gender = c.gender, height = c.height, desc = c.description, model = c.model,
			number = string.format("NY-%03d-%04d", c.id % 1000, math.random(1000, 9999)),
			issued = os.date("%d.%m.%Y"),
		})
		NYRP.Notify(ply, "Вам выдано удостоверение личности штата Нью-Йорк. Посмотреть: инвентарь → ПКМ.", "item", 8)
	end
end

function Chars.Load(ply, id)
	local r = Q("SELECT * FROM nyrp_characters WHERE id = " .. tonumber(id) .. " AND steamid = " .. E(Chars.Key(ply)))
	if not r or not r[1] then return false end
	if ply.nyrpChar then Chars.Save(ply) end

	local c = rowToChar(r[1])
	-- у каждого персонажа свои вещи: оружие, патроны, броня прошлого персонажа не переносятся
	ply:StripWeapons()
	ply:RemoveAllAmmo()
	ply:SetArmor(0)
	ply.nyrpContainer = nil
	ply.nyrpChar = c
	ply.nyrpLastChar = c.id
	ply:SetNW2Int("nyrp.charID", c.id)
	ply:SetNW2String("nyrp.name", c.name)
	ply:SetNW2String("nyrp.desc", c.description)
	ply:SetNW2String("nyrp.gender", c.gender)
	ply:SetNW2String("nyrp.bag", c.bag or "waistbag")
	ply:SetNW2Int("nyrp.height", c.height)
	ply:SetNW2Float("nyrp.hunger", c.hunger)
	ply:SetNW2Float("nyrp.thirst", c.thirst)
	-- знакомые: { [id персонажа] = когда виделись (os.time) }; старый формат — просто список id
	ply.nyrpRecog = {}
	local rec = c.recognized or {}
	if rec[1] ~= nil then
		for _, cid in ipairs(rec) do ply.nyrpRecog[tonumber(cid)] = os.time() end
	else
		for cid, ts in pairs(rec) do if tonumber(cid) then ply.nyrpRecog[tonumber(cid)] = tonumber(ts) or os.time() end end
	end
	if NYRP.Recog then NYRP.Recog.Sync(ply) end
	if NYRP.Inv then NYRP.Inv.Import(ply, c.inventory, c.equipment) end
	issueID(ply, c)

	ply.nyrpSpawnHealth = math.max(c.health, 25)
	ply:Spawn()
	savePlaytime(ply)

	net.Start("nyrp.char.loaded")
	net.WriteString(c.gender)
	net.Send(ply)
	hook.Run("NYRP.CharacterLoaded", ply, c)
	return true
end

function Chars.ToMenu(ply)
	if ply.nyrpChar then Chars.Save(ply) end
	ply.nyrpChar = nil
	ply:SetNW2Int("nyrp.charID", 0)
	ply:SetNW2String("nyrp.name", "")
	ply:SetNW2String("nyrp.bag", "")
	if NYRP.Inv then NYRP.Inv.Clear(ply) end
	ply:StripWeapons()
	ply:RemoveAllAmmo()
	ply:SetArmor(0)
	ply.nyrpContainer = nil
	ply:Spawn()
	Chars.SendList(ply)
end

-- Автоматический персонаж (на карте не расставлены камеры).
function Chars.AutoLoad(ply)
	local list = Chars.List(ply)
	local pick
	for _, c in ipairs(list) do
		if c.id == ply.nyrpLastChar then pick = c.id end
	end
	pick = pick or (list[1] and list[1].id)
	if not pick then
		pick = Chars.Insert(ply, Chars.RandomData())
	end
	Chars.Load(ply, pick)
end

-- ----------------------------------------------------------------- сеть --
net.Receive("nyrp.ready", function(_, ply)
	if ply.nyrpReady then return end
	ply.nyrpReady = true
	NYRP.Points.Send(ply)
	Chars.SendList(ply)
	if not NYRP.Points.Configured() then
		Chars.AutoLoad(ply)
	end
end)

net.Receive("nyrp.char.create", function(_, ply)
	if (ply.nyrpNextCreate or 0) > CurTime() then return end
	ply.nyrpNextCreate = CurTime() + 2
	local ok, data = Chars.Validate(net.ReadTable())
	if not ok then
		NYRP.Notify(ply, data, "error")
		net.Start("nyrp.char.state") net.WriteString("create_failed") net.Send(ply)
		return
	end
	if #Chars.List(ply) >= Chars.MaxFor() then
		NYRP.Notify(ply, "Достигнут лимит персонажей", "error")
		return
	end
	local id = Chars.Insert(ply, data)
	Chars.SendList(ply)
	Chars.Load(ply, id)
end)

net.Receive("nyrp.char.load", function(_, ply)
	if (ply.nyrpNextLoad or 0) > CurTime() then return end
	ply.nyrpNextLoad = CurTime() + 2
	local id = net.ReadUInt(32)
	if ply.nyrpChar and ply.nyrpChar.id == id then return end
	if not Chars.Load(ply, id) then NYRP.Notify(ply, "Персонаж не найден", "error") end
end)

net.Receive("nyrp.char.delete", function(_, ply)
	local id = net.ReadUInt(32)
	if ply.nyrpChar and ply.nyrpChar.id == id then
		NYRP.Notify(ply, "Нельзя удалить персонажа, за которого вы играете", "error")
		return
	end
	Q("DELETE FROM nyrp_characters WHERE id = " .. id .. " AND steamid = " .. E(Chars.Key(ply)))
	Chars.SendList(ply)
	NYRP.Notify(ply, "Персонаж удалён", "success")
end)

net.Receive("nyrp.char.menu", function(_, ply)
	if not NYRP.Points.Configured() then
		NYRP.Notify(ply, "Меню персонажей недоступно: на карте не расставлены камеры", "warning")
		return
	end
	if (ply.nyrpNextMenu or 0) > CurTime() then return end
	ply.nyrpNextMenu = CurTime() + 3
	Chars.ToMenu(ply)
end)

-- ---------------------------------------------------------------- хуки --
hook.Add("PlayerInitialSpawn", "nyrp.chars", function(ply)
	local row = Q("SELECT * FROM nyrp_players WHERE steamid = " .. E(Chars.Key(ply)))
	ply.nyrpPlaytime = row and row[1] and tonumber(row[1].playtime) or 0
	ply.nyrpLastChar = row and row[1] and tonumber(row[1].last_char) or 0
	ply.nyrpJoined = CurTime()
	ply:SetNW2Int("nyrp.playtime", ply.nyrpPlaytime)
	ply:SetNW2Float("nyrp.joined", CurTime())

	-- Бот заходит «впервые»: сразу новый случайный персонаж.
	if ply:IsBot() then
		timer.Simple(0.5, function()
			if not IsValid(ply) then return end
			Q("DELETE FROM nyrp_characters WHERE steamid = " .. E(Chars.Key(ply)))
			Chars.Load(ply, Chars.Insert(ply, Chars.RandomData()))
		end)
	end
end)

function GM:PlayerSpawn(ply, transition)
	if not NYRP.HasCharacter(ply) then
		-- в меню: игрок «за кадром»
		player_manager.SetPlayerClass(ply, "player_sandbox")
		ply:SetModel("models/player/group01/male_01.mdl")
		ply:SetNoDraw(true)
		ply:SetNotSolid(true)
		ply:DrawShadow(false)
		ply:GodEnable()
		ply:StripWeapons()
		ply:SetMoveType(MOVETYPE_NONE)
		ply:Freeze(true)
		return
	end
	ply:SetNoDraw(false)
	ply:SetNotSolid(false)
	ply:DrawShadow(true)
	ply:GodDisable()
	ply:Freeze(false)
	ply:SetMoveType(MOVETYPE_WALK)
	self.BaseClass.PlayerSpawn(self, ply, transition)

	local c = ply.nyrpChar
	local scale = Chars.HeightScale(c.height)
	ply:SetModelScale(scale, 0)
	ply:SetViewOffset(Vector(0, 0, 64 * scale))
	ply:SetViewOffsetDucked(Vector(0, 0, 28 * scale))
	ply:SetHull(Vector(-16, -16, 0), Vector(16, 16, 72 * scale))
	ply:SetHullDuck(Vector(-16, -16, 0), Vector(16, 16, 36 * scale))
	if ply.nyrpSpawnHealth then
		ply:SetHealth(ply.nyrpSpawnHealth)
		ply.nyrpSpawnHealth = nil
	end
	NYRP.ApplyMovement(ply)
	hook.Run("NYRP.PlayerSpawned", ply)
end

function GM:PlayerSetModel(ply)
	local c = ply.nyrpChar
	ply:SetModel(c and c.model or "models/player/group01/male_01.mdl")
	ply:SetupHands()
end

function GM:PlayerLoadout(ply)
	if not NYRP.HasCharacter(ply) then return true end
	ply:Give("nyrp_hands")
	if ply:IsAdmin() then
		ply:Give("weapon_physgun")
		ply:Give("gmod_tool")
	end
	hook.Run("NYRP.Loadout", ply)
	ply:SelectWeapon("nyrp_hands")
	return true
end

hook.Add("PlayerDisconnected", "nyrp.chars", function(ply)
	if ply:IsBot() then
		Q("DELETE FROM nyrp_characters WHERE steamid = " .. E(Chars.Key(ply)))
		return
	end
	Chars.Save(ply)
	savePlaytime(ply)
end)

hook.Add("ShutDown", "nyrp.chars", function()
	for _, ply in ipairs(player.GetAll()) do
		Chars.Save(ply)
		savePlaytime(ply)
	end
end)

timer.Create("nyrp.chars.autosave", 120, 0, function()
	for _, ply in ipairs(player.GetAll()) do
		Chars.Save(ply)
		savePlaytime(ply)
	end
end)

-- В меню нельзя получить урон и умереть.
hook.Add("PlayerShouldTakeDamage", "nyrp.chars", function(ply)
	if not NYRP.HasCharacter(ply) then return false end
end)
