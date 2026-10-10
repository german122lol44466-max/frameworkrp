--[[
	Мир и строительство — общая часть.
	  • Флаги персонажа (как в Helix): p — physgun, t — toolgun, e — пропы, n — энтити, v — транспорт.
	    Хранятся в c.flags.cflags (строка), на клиент — NW2String "nyrp.cflags". Админам доступно всё.
	  • Владелец энтити: NW2Entity "nyrp.owner", NW2String "nyrp.ownerName" / "nyrp.ownerSID".
	  • CPPI-совместимые функции (ENT:CPPIGetOwner, ENT:CPPICanTool, ...), если их не объявил другой аддон.
	  • Сетевые сообщения модуля (3D-текст, 3D-панели).
	Сервер: sv_protect (защита пропов), sv_flags (флаги и команды), sv_persist (постоянные пропы),
	sv_text (3D-текст), sv_panels (3D-панели), sv_saveitems (предметы на земле).
]]

NYRP.World = NYRP.World or {}
local W = NYRP.World

if SERVER then
	util.AddNetworkString("nyrp.world.text")
	util.AddNetworkString("nyrp.world.panel")
end

-- Настройки (лимиты дополнительно крутятся консольными переменными nyrp_proplimit / nyrp_entlimit).
W.Config = W.Config or {
	PropLimit = 25,         -- пропов на игрока (админы — без лимита)
	EntLimit = 4,           -- энтити/транспорта на игрока
	CleanupDelay = 300,     -- через сколько секунд после выхода удалять пропы игрока
	TextDrawDist = 1100,    -- дальность прорисовки 3D-текста
	PanelDrawDist = 1600,   -- дальность прорисовки 3D-панелей
	ItemsSaveEvery = 300,   -- автосохранение предметов на земле (сек)
	ItemsMaxAge = 86400,    -- предметы старше суток (реального времени) не восстанавливаются
}

-- Флаги персонажа: буква -> описание.
W.Flags = {
	p = { name = "Physgun", desc = "физган", icon = "move" },
	t = { name = "Toolgun", desc = "тулган", icon = "tools" },
	e = { name = "Пропы", desc = "спавн пропов", icon = "box" },
	n = { name = "Энтити", desc = "спавн энтити", icon = "bolt" },
	v = { name = "Транспорт", desc = "спавн машин", icon = "key" },
}
W.FlagOrder = { "p", "t", "e", "n", "v" }

-- Строка флагов персонажа.
function W.GetFlags(ply)
	if not IsValid(ply) then return "" end
	if SERVER then
		local c = ply.nyrpChar
		return c and c.flags and tostring(c.flags.cflags or "") or ""
	end
	return ply:GetNW2String("nyrp.cflags", "")
end

-- Есть ли у игрока флаг (админам — всё).
function W.HasFlag(ply, f)
	if not IsValid(ply) or not ply:IsPlayer() then return false end
	if ply:IsAdmin() then return true end
	if not NYRP.HasCharacter(ply) then return false end
	return string.find(W.GetFlags(ply), f, 1, true) ~= nil
end

-- Может ли строить (открывать спавн-меню).
function W.CanBuild(ply)
	return W.HasFlag(ply, "e") or W.HasFlag(ply, "n") or W.HasFlag(ply, "v")
end

-- Владелец энтити (игрок или nil) и его SteamID64.
function W.Owner(ent)
	if not IsValid(ent) then return nil, nil end
	local sid = ent:GetNW2String("nyrp.ownerSID", "")
	if sid == "" then return nil, nil end
	local ply = ent:GetNW2Entity("nyrp.owner")
	if not IsValid(ply) then ply = player.GetBySteamID64 and player.GetBySteamID64(sid) or nil end
	return (IsValid(ply) and ply) or nil, sid
end

local function sidOf(ply)
	if not IsValid(ply) then return "" end
	if ply:IsBot() then return "BOT:" .. ply:Nick() end
	return ply:SteamID64() or ""
end
W.SID = sidOf

-- Может ли игрок трогать энтити (physgun, тулган, удаление, разморозка).
function W.CanTouch(ply, ent)
	if not IsValid(ply) then return false end
	if not IsValid(ent) then return false end
	if ent:IsWorld() then return true end
	if ply:IsAdmin() then return true end
	if ent:GetNW2Bool("nyrp.persist") then return false end
	local _, sid = W.Owner(ent)
	return sid ~= nil and sid == sidOf(ply)
end

-- ------------------------------------------------------------------ CPPI --
-- Общий интерфейс защиты пропов: им пользуются Wiremod, Advanced Duplicator и др.
if not CPPI then
	CPPI = {}
	CPPI.CPPI_DEFER = 8080
	CPPI.CPPI_NOTIMPLEMENTED = 8081
	function CPPI:GetName() return "New-York Roleplay Prop Protection" end
	function CPPI:GetVersion() return "1.0" end
	function CPPI:GetInterfaceVersion() return 1.3 end
	function CPPI:GetNameFromUID(uid)
		for _, p in ipairs(player.GetAll()) do
			if p:UniqueID() == uid or sidOf(p) == tostring(uid) then return p:Nick() end
		end
	end

	local PLAYER = FindMetaTable("Player")
	local ENTITY = FindMetaTable("Entity")

	if PLAYER then
		function PLAYER:CPPIGetFriends() return {} end
	end

	if ENTITY then
		function ENTITY:CPPIGetOwner()
			local ply, sid = W.Owner(self)
			if ply then return ply, ply:UniqueID() end
			return nil, sid
		end
		function ENTITY:CPPICanTool(ply, mode) return W.CanTouch(ply, self) end
		function ENTITY:CPPICanPhysgun(ply) return W.CanTouch(ply, self) end
		function ENTITY:CPPICanPickup(ply) return W.CanTouch(ply, self) end
		function ENTITY:CPPICanPunt(ply) return W.CanTouch(ply, self) end
		function ENTITY:CPPICanUse(ply) return true end
		function ENTITY:CPPICanDamage(ply) return true end
		function ENTITY:CPPIDrive(ply) return IsValid(ply) and ply:IsAdmin() end
		function ENTITY:CPPICanProperty(ply, prop) return W.CanTouch(ply, self) end
		function ENTITY:CPPICanEditVariable(ply, key, val, edit) return W.CanTouch(ply, self) end
		if SERVER then
			function ENTITY:CPPISetOwner(ply)
				if W.SetOwner then W.SetOwner(self, ply) end
				return true
			end
			function ENTITY:CPPISetOwnerUID(uid)
				for _, p in ipairs(player.GetAll()) do
					if p:UniqueID() == uid then return self:CPPISetOwner(p) end
				end
				return false
			end
		end
	end
end
