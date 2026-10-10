--[[
	Защита пропов.
	  • У каждого заспавненного пропа/рэгдолла/эффекта/энтити/машины (и всего, что ставит тулган) есть владелец.
	  • Physgun, тулган, свойства (C-меню), разморозка, грави-ган и подъём на E — только владелец и админы.
	  • Чужие и «мировые» вещи (двери, NPC, постоянные пропы) обычные игроки не трогают.
	  • Лимиты: nyrp_proplimit (пропы, рэгдоллы, эффекты) и nyrp_entlimit (энтити, транспорт) на игрока; админам — без лимита.
	  • Права на спавн — по флагам персонажа (sh_world.lua): e — пропы, n — энтити, v — транспорт; NPC и оружие — только админы.
	  • Вышел с сервера — его постройки удаляются через 5 минут (вернулся раньше — остаются).
]]

NYRP.World = NYRP.World or {}
local W = NYRP.World

local cvProps = CreateConVar("nyrp_proplimit", tostring(W.Config.PropLimit), FCVAR_ARCHIVE, "NYRP: лимит пропов на игрока")
local cvEnts = CreateConVar("nyrp_entlimit", tostring(W.Config.EntLimit), FCVAR_ARCHIVE, "NYRP: лимит энтити и транспорта на игрока")

-- SteamID64 -> { [ent] = "prop"|"ent" }
W.Owned = W.Owned or {}

-- Инструменты, которые обычным игрокам недоступны даже с флагом t.
W.AdminTools = {
	creator = true, dynamite = true, duplicator = true, advdupe2 = true, adv_duplicator = true,
	eyeposer = false, faceposer = false, -- позинг разрешён
}

local function say(ply, text, kind)
	if not IsValid(ply) then return end
	if (ply.nyrpPPNext or 0) > CurTime() then return end
	ply.nyrpPPNext = CurTime() + 1
	NYRP.Notify(ply, text, kind or "warning", 4)
end

-- ------------------------------------------------------------- владельцы --
function W.SetOwner(ent, ply, kind)
	if not IsValid(ent) then return end
	if not IsValid(ply) or not ply:IsPlayer() then return W.ClearOwner(ent) end
	W.ClearOwner(ent)
	local sid = W.SID(ply)
	ent:SetNW2Entity("nyrp.owner", ply)
	ent:SetNW2String("nyrp.ownerSID", sid)
	ent:SetNW2String("nyrp.ownerName", NYRP.CharName(ply))
	ent:SetNW2String("nyrp.ownerNick", ply:Nick())
	W.Owned[sid] = W.Owned[sid] or {}
	W.Owned[sid][ent] = kind or ent.nyrpOwnKind or "ent"
	ent.nyrpOwnKind = W.Owned[sid][ent]
end

function W.ClearOwner(ent)
	if not IsValid(ent) then return end
	local sid = ent:GetNW2String("nyrp.ownerSID", "")
	if sid ~= "" and W.Owned[sid] then W.Owned[sid][ent] = nil end
	ent:SetNW2Entity("nyrp.owner", NULL)
	ent:SetNW2String("nyrp.ownerSID", "")
	ent:SetNW2String("nyrp.ownerName", "")
	ent:SetNW2String("nyrp.ownerNick", "")
end

-- Сколько у игрока вещей вида kind (заодно чистим удалённые).
function W.Count(ply, kind)
	local list = W.Owned[W.SID(ply)]
	if not list then return 0 end
	local n = 0
	for ent, k in pairs(list) do
		if not IsValid(ent) then list[ent] = nil
		elseif k == kind then n = n + 1 end
	end
	return n
end

-- Все вещи игрока (по SteamID64).
function W.OwnedBy(sid)
	local out = {}
	for ent in pairs(W.Owned[sid] or {}) do
		if IsValid(ent) then out[#out + 1] = ent end
	end
	return out
end

local function limitOK(ply, kind)
	if ply:IsAdmin() then return true end
	local cv = kind == "prop" and cvProps or cvEnts
	local max = cv:GetInt()
	if max <= 0 then return true end
	if W.Count(ply, kind) >= max then
		say(ply, (kind == "prop" and "Лимит пропов" or "Лимит энтити") .. ": " .. max .. ". Удалите что-нибудь из своих построек.", "error")
		return false
	end
	return true
end

local function needFlag(ply, f)
	if W.HasFlag(ply, f) then return true end
	local def = W.Flags[f]
	say(ply, "Нет права «" .. (def and def.desc or f) .. "» (флаг " .. f .. "). Обратитесь к администрации.", "error")
	return false
end

-- --------------------------------------------------------- права на спавн --
hook.Add("PlayerSpawnObject", "nyrp.pp", function(ply)
	if not NYRP.HasCharacter(ply) or not ply:Alive() then return false end
end)

hook.Add("PlayerSpawnProp", "nyrp.pp", function(ply)
	if not needFlag(ply, "e") or not limitOK(ply, "prop") then return false end
end)
hook.Add("PlayerSpawnRagdoll", "nyrp.pp", function(ply)
	if not needFlag(ply, "e") or not limitOK(ply, "prop") then return false end
end)
hook.Add("PlayerSpawnEffect", "nyrp.pp", function(ply)
	if not needFlag(ply, "e") or not limitOK(ply, "prop") then return false end
end)
hook.Add("PlayerSpawnSENT", "nyrp.pp", function(ply)
	if not needFlag(ply, "n") or not limitOK(ply, "ent") then return false end
end)
hook.Add("PlayerSpawnVehicle", "nyrp.pp", function(ply)
	if not needFlag(ply, "v") or not limitOK(ply, "ent") then return false end
end)

local function adminOnly(ply)
	if not ply:IsAdmin() then
		say(ply, "Это доступно только администрации", "error")
		return false
	end
end
hook.Add("PlayerSpawnNPC", "nyrp.pp", adminOnly)
hook.Add("PlayerSpawnSWEP", "nyrp.pp", adminOnly)
hook.Add("PlayerGiveSWEP", "nyrp.pp", adminOnly)

-- ------------------------------------------------------------ владельцы --
hook.Add("PlayerSpawnedProp", "nyrp.pp", function(ply, _, ent) W.SetOwner(ent, ply, "prop") end)
hook.Add("PlayerSpawnedRagdoll", "nyrp.pp", function(ply, _, ent) W.SetOwner(ent, ply, "prop") end)
hook.Add("PlayerSpawnedEffect", "nyrp.pp", function(ply, _, ent) W.SetOwner(ent, ply, "prop") end)
hook.Add("PlayerSpawnedSENT", "nyrp.pp", function(ply, ent) W.SetOwner(ent, ply, "ent") end)
hook.Add("PlayerSpawnedVehicle", "nyrp.pp", function(ply, ent) W.SetOwner(ent, ply, "ent") end)
hook.Add("PlayerSpawnedNPC", "nyrp.pp", function(ply, ent) W.SetOwner(ent, ply, "ent") end)
hook.Add("PlayerSpawnedSWEP", "nyrp.pp", function(ply, ent) W.SetOwner(ent, ply, "ent") end)

-- Всё, что создаёт тулган (кнопки, колёса, лампы, тросы...), регистрируется через cleanup.Add — там и ставим владельца.
local function wrapCleanup()
	if W.CleanupWrapped or not cleanup or not isfunction(cleanup.Add) then return end
	W.CleanupWrapped = true
	local orig = cleanup.Add
	cleanup.Add = function(ply, kind, ent, ...)
		if IsValid(ent) and IsValid(ply) and ply:IsPlayer() and ent:GetNW2String("nyrp.ownerSID", "") == "" then
			W.SetOwner(ent, ply, "tool")
		end
		return orig(ply, kind, ent, ...)
	end
end
hook.Add("Initialize", "nyrp.pp.cleanup", function(...) wrapCleanup(...) end)
wrapCleanup()

-- --------------------------------------------------------------- защита --
local function deny(ply, ent)
	if ent:GetNW2Bool("nyrp.persist") then
		say(ply, "Это постоянный объект карты")
		return
	end
	local _, sid = W.Owner(ent)
	if sid then
		say(ply, "Это чужое: владелец — " .. ent:GetNW2String("nyrp.ownerName", "?"))
	else
		say(ply, "Это часть карты — трогать нельзя")
	end
end

hook.Add("PhysgunPickup", "nyrp.pp", function(ply, ent)
	if not IsValid(ent) then return end
	if ent:IsPlayer() then
		if not ply:IsAdmin() then return false end
		return
	end
	if not W.HasFlag(ply, "p") then return false end
	if not W.CanTouch(ply, ent) then return false end
end)

hook.Add("OnPhysgunReload", "nyrp.pp", function(_, ply)
	if not W.HasFlag(ply, "p") then return false end
end)

hook.Add("CanPlayerUnfreeze", "nyrp.pp", function(ply, ent)
	if not W.CanTouch(ply, ent) then return false end
end)

hook.Add("CanTool", "nyrp.pp", function(ply, tr, mode)
	if not W.HasFlag(ply, "t") then return false end
	if W.AdminTools[mode] and not ply:IsAdmin() then
		say(ply, "Инструмент «" .. tostring(mode) .. "» доступен только администрации", "error")
		return false
	end
	local ent = tr and tr.Entity
	if not IsValid(ent) or ent:IsWorld() then return end
	if ent:IsPlayer() and not ply:IsAdmin() then return false end
	if ent:GetNW2Bool("nyrp.persist") and mode == "remover" then
		say(ply, "Это постоянный проп. Сначала /unpersist")
		return false
	end
	if not W.CanTouch(ply, ent) then
		deny(ply, ent)
		return false
	end
end)

hook.Add("CanProperty", "nyrp.pp", function(ply, prop, ent)
	if prop == "persist" then
		-- у режима свои постоянные пропы (/persist), стандартное «Persist» — только суперадмину
		if not ply:IsSuperAdmin() then return false end
		return
	end
	if prop == "drive" and not ply:IsAdmin() then return false end
	if IsValid(ent) and ent:GetNW2Bool("nyrp.persist") and prop == "remover" then
		say(ply, "Это постоянный проп. Сначала /unpersist")
		return false
	end
	if IsValid(ent) and not W.CanTouch(ply, ent) then
		deny(ply, ent)
		return false
	end
end)

hook.Add("CanDrive", "nyrp.pp", function(ply)
	if not ply:IsAdmin() then return false end
end)

hook.Add("CanEditVariable", "nyrp.pp", function(ent, ply)
	if not W.CanTouch(ply, ent) then return false end
end)

-- Чужие постройки нельзя поднять руками / грави-ганом.
local function foreign(ply, ent)
	if not IsValid(ent) or ply:IsAdmin() then return false end
	local _, sid = W.Owner(ent)
	return (sid ~= nil and sid ~= W.SID(ply)) or ent:GetNW2Bool("nyrp.persist")
end
hook.Add("AllowPlayerPickup", "nyrp.pp", function(ply, ent) if foreign(ply, ent) then return false end end)
hook.Add("GravGunPickupAllowed", "nyrp.pp", function(ply, ent) if foreign(ply, ent) then return false end end)
hook.Add("GravGunPunt", "nyrp.pp", function(ply, ent) if foreign(ply, ent) then return false end end)

-- ------------------------------------------------- уход и возвращение --
hook.Add("PlayerDisconnected", "nyrp.pp", function(ply)
	local sid = W.SID(ply)
	if #W.OwnedBy(sid) == 0 then return end
	local name = ply:Nick()
	local delay = ply:IsBot() and 1 or W.Config.CleanupDelay
	timer.Create("nyrp.pp.cleanup." .. sid, delay, 1, function()
		local list = W.OwnedBy(sid)
		for _, ent in ipairs(list) do
			if IsValid(ent) and not ent:GetNW2Bool("nyrp.persist") then ent:Remove() end
		end
		W.Owned[sid] = nil
		if #list > 0 then NYRP.Print("Удалены постройки вышедшего игрока " .. name .. " (" .. #list .. ")") end
	end)
end)

hook.Add("PlayerInitialSpawn", "nyrp.pp", function(ply)
	local sid = W.SID(ply)
	if timer.Exists("nyrp.pp.cleanup." .. sid) then timer.Remove("nyrp.pp.cleanup." .. sid) end
	for _, ent in ipairs(W.OwnedBy(sid)) do ent:SetNW2Entity("nyrp.owner", ply) end
end)

-- Имя владельца — имя текущего персонажа.
hook.Add("NYRP.CharacterLoaded", "nyrp.pp", function(ply)
	local name = NYRP.CharName(ply)
	for _, ent in ipairs(W.OwnedBy(W.SID(ply))) do ent:SetNW2String("nyrp.ownerName", name) end
end)

-- Админ: удалить все постройки игрока.
concommand.Add("nyrp_pp_clear", function(ply, _, args)
	if IsValid(ply) and not ply:IsAdmin() then return end
	local target = W.FindPlayer and W.FindPlayer(table.concat(args, " "))
	if not IsValid(target) then
		if IsValid(ply) then NYRP.Notify(ply, "nyrp_pp_clear <имя>: игрок не найден", "error") else print("игрок не найден") end
		return
	end
	local n = 0
	for _, ent in ipairs(W.OwnedBy(W.SID(target))) do
		if not ent:GetNW2Bool("nyrp.persist") then ent:Remove() n = n + 1 end
	end
	if IsValid(ply) then NYRP.Notify(ply, "Удалено построек: " .. n, "success") end
end)
