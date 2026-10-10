--[[
	Режим наблюдателя (сервер): /observer или V (noclip) у админа.
	Невидимость, без коллизий, noclip, бессмертие; ESP рисуется на клиенте (cl_observer.lua).
	При выходе — возврат на место входа (настройка «Наблюдатель: возврат»).
	Слежка за игроком (/spectate <имя>, кнопка «Наблюдать» в меню): камера вокруг игрока,
	админ невидимо следует за ним (слышит его чат и голос). Пробел или /spectate — выход.
]]

NYRP.Admin = NYRP.Admin or {}
local A = NYRP.Admin

local function log(text, ply)
	if NYRP.Log and NYRP.Log.Add then NYRP.Log.Add("admin", text, ply) end
end

local function hideWeapons(ply, hide)
	for _, w in ipairs(ply:GetWeapons()) do
		if IsValid(w) then w:SetNoDraw(hide) end
	end
end

-- on = true/false; silent — без уведомлений; noReturn — не возвращать на место входа
function A.SetObserver(ply, on, silent, noReturn)
	if not IsValid(ply) then return end
	if on then
		if A.IsObserver(ply) then return end
		if not ply:Alive() or not NYRP.HasCharacter(ply) then
			if not silent then NYRP.Notify(ply, "Наблюдатель доступен только живому персонажу", "error") end
			return
		end
		if ply:InVehicle() then ply:ExitVehicle() end
		ply.nyrpObs = { pos = ply:GetPos(), ang = ply:EyeAngles(), group = ply:GetCollisionGroup() }
		ply:SetNW2Bool("nyrp.observer", true)
		ply:SetNoDraw(true)
		ply:DrawShadow(false)
		ply:SetNotSolid(true)
		ply:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
		ply:GodEnable()
		ply:SetNoTarget(true)
		ply:SetMoveType(MOVETYPE_NOCLIP)
		hideWeapons(ply, true)
		if not silent then NYRP.Notify(ply, "Режим наблюдателя включён. V или /observer — выйти", "info", 5) end
		log("включил режим наблюдателя", ply)
	else
		if not A.IsObserver(ply) then return end
		if A.Spectating(ply) then A.StopSpectate(ply, true) end
		local d = ply.nyrpObs or {}
		ply.nyrpObs = nil
		ply:SetNW2Bool("nyrp.observer", false)
		ply:SetNoDraw(false)
		ply:DrawShadow(true)
		ply:SetNotSolid(false)
		ply:SetCollisionGroup(d.group or COLLISION_GROUP_PLAYER)
		ply:GodDisable()
		ply:SetNoTarget(false)
		hideWeapons(ply, false)
		if ply:Alive() then
			ply:SetMoveType(MOVETYPE_WALK)
			local back = NYRP.Config.Admin and NYRP.Config.Admin.ObserverReturn
			if back == nil then back = true end
			if back and not noReturn and d.pos then
				ply:SetPos(d.pos)
				ply:SetEyeAngles(d.ang or ply:EyeAngles())
				ply:SetLocalVelocity(vector_origin)
			end
		end
		if not silent then NYRP.Notify(ply, "Режим наблюдателя выключен", "info", 3) end
		log("выключил режим наблюдателя", ply)
	end
end

function A.ToggleObserver(ply)
	if not IsValid(ply) or not ply:IsAdmin() then return end
	if A.Spectating(ply) then A.StopSpectate(ply) return end
	A.SetObserver(ply, not A.IsObserver(ply))
end

-- ------------------------------------------------------------ слежка --
function A.Spectate(admin, target)
	if not IsValid(target) or target == admin then NYRP.Notify(admin, "Нельзя наблюдать за этим игроком", "error") return end
	if not A.IsObserver(admin) then
		A.SetObserver(admin, true, true)
		if not A.IsObserver(admin) then NYRP.Notify(admin, "Сначала нужен живой персонаж", "error") return end
		admin.nyrpSpecAutoObs = true
	end
	admin:SetNW2Entity("nyrp.spectate", target)
	admin:SetPos(target:GetPos() + Vector(0, 0, 16))
	NYRP.Notify(admin, "Наблюдение: " .. NYRP.CharName(target) .. ". Пробел — выход", "info", 5)
	log("наблюдает за " .. NYRP.Log.Who(target), admin)
end

function A.StopSpectate(admin, keepObserver)
	if not A.Spectating(admin) then return end
	admin:SetNW2Entity("nyrp.spectate", NULL)
	local auto = admin.nyrpSpecAutoObs
	admin.nyrpSpecAutoObs = nil
	if auto and not keepObserver then
		-- место входа в наблюдатель — там, откуда начали слежку: возвращаем туда всегда
		local d = admin.nyrpObs
		A.SetObserver(admin, false, true, true)
		if d and d.pos and admin:Alive() then
			admin:SetPos(d.pos)
			admin:SetEyeAngles(d.ang or admin:EyeAngles())
		end
	end
	NYRP.Notify(admin, "Наблюдение завершено", "info", 3)
end

hook.Add("KeyPress", "nyrp.admin.spectate", function(ply, key)
	if key == IN_JUMP and A.Spectating(ply) then A.StopSpectate(ply) end
end)

-- админ невидимо держится рядом с целью (чат и голос по дистанции)
timer.Create("nyrp.admin.spectate", 0.25, 0, function()
	for _, p in ipairs(player.GetAll()) do
		if p:GetNW2Bool("nyrp.observer", false) then
			local t = A.Spectating(p)
			if t then
				if not p:IsAdmin() then
					A.StopSpectate(p)
				else
					p:SetPos(t:GetPos() + Vector(0, 0, 16))
				end
			end
			-- новое оружие тоже прячем
			local w = p:GetActiveWeapon()
			if IsValid(w) and not w:GetNoDraw() then w:SetNoDraw(true) end
		end
	end
end)

-- цель всегда в зоне видимости наблюдателя
hook.Add("SetupPlayerVisibility", "nyrp.admin.spectate", function(ply)
	local t = A.Spectating(ply)
	if t then AddOriginToPVS(t:EyePos()) end
end)

hook.Add("PlayerShouldTakeDamage", "nyrp.admin.observer", function(ply)
	if A.IsObserver(ply) then return false end
end)

hook.Add("PlayerCanPickupWeapon", "nyrp.admin.observer", function(ply)
	if A.IsObserver(ply) then return false end
end)

hook.Add("PlayerCanPickupItem", "nyrp.admin.observer", function(ply)
	if A.IsObserver(ply) then return false end
end)

-- смерть / возрождение / смена персонажа — режим сбрасывается
local function reset(ply)
	if not A.IsObserver(ply) and not A.Spectating(ply) then return end
	ply:SetNW2Entity("nyrp.spectate", NULL)
	ply.nyrpSpecAutoObs = nil
	ply.nyrpObs = nil
	ply:SetNW2Bool("nyrp.observer", false)
	ply:SetNoDraw(false)
	ply:DrawShadow(true)
	ply:SetNotSolid(false)
	ply:SetCollisionGroup(COLLISION_GROUP_PLAYER)
	ply:GodDisable()
	ply:SetNoTarget(false)
	hideWeapons(ply, false)
end
hook.Add("PlayerDeath", "nyrp.admin.observer", reset)
hook.Add("NYRP.PlayerSpawned", "nyrp.admin.observer", reset)

-- цель ушла — у всех, кто за ней следил, слежка заканчивается
hook.Add("PlayerDisconnected", "nyrp.admin.spectate", function(ply)
	for _, p in ipairs(player.GetAll()) do
		if p ~= ply and A.Spectating(p) == ply then A.StopSpectate(p) end
	end
end)
