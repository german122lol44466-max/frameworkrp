--[[
	Настройки сервера в игре (вкладка «Настройки» админ-меню).
	Список значений — A.Settings в sh_admin.lua. Изменения: проверка типа и границ на сервере,
	применение к NYRP.Config, сохранение в data/nyrp/config.json, рассылка всем клиентам.
	Файл читается при запуске сервера.
]]

NYRP.Admin = NYRP.Admin or {}
local A = NYRP.Admin

local FILE = "nyrp/config.json"

local function readOverrides()
	local s = file.Read(FILE, "DATA")
	if not s or s == "" then return {} end
	local ok, t = pcall(util.JSONToTable, s)
	return (ok and type(t) == "table") and t or {}
end

A.ConfigOverrides = readOverrides()

function A.LoadConfig()
	for key, v in pairs(A.ConfigOverrides) do
		local s = A.SettingByKey[key]
		local val = s and A.ValidateSetting(s, v)
		if val ~= nil then A.ApplySetting(s, val) end
	end
end
-- сразу (то, что уже есть в Config) и ещё раз, когда загружены все модули (StartMoney задаёт модуль money)
A.LoadConfig()
hook.Add("Initialize", "nyrp.admin.config", A.LoadConfig)

function A.SaveConfig()
	file.CreateDir("nyrp")
	file.Write(FILE, util.TableToJSON(A.ConfigOverrides, true))
end

-- Отправить значения клиенту (или всем)
function A.SendConfig(ply)
	net.Start("nyrp.admin.cfg")
	net.WriteUInt(#A.Settings, 8)
	for _, s in ipairs(A.Settings) do
		net.WriteString(s.key)
		local v = A.GetSetting(s)
		if s.type == "bool" then net.WriteBool(v == true) else net.WriteDouble(tonumber(v) or s.def) end
	end
	if IsValid(ply) then net.Send(ply) else net.Broadcast() end
end

-- изменения скоростей — сразу на всех живых персонажах
local function reapplyMovement()
	if not NYRP.ApplyMovement then return end
	for _, p in ipairs(player.GetAll()) do
		if NYRP.HasCharacter(p) and p:Alive() then NYRP.ApplyMovement(p) end
	end
end

net.Receive("nyrp.admin.cfgset", function(_, ply)
	if not IsValid(ply) or not ply:IsAdmin() then return end
	if (ply.nyrpCfgNext or 0) > CurTime() then NYRP.Notify(ply, "Подождите секунду", "warning", 2) return end
	ply.nyrpCfgNext = CurTime() + 1.5
	local n = net.ReadUInt(8)
	local changed, bad = {}, {}
	for _ = 1, math.min(n, #A.Settings) do
		local key = net.ReadString()
		local isBool = net.ReadBool()
		local raw
		if isBool then raw = net.ReadBool() else raw = net.ReadDouble() end
		local s = A.SettingByKey[key]
		if s and ((s.type == "bool") == isBool) then
			local v = A.ValidateSetting(s, raw)
			if v == nil then
				bad[#bad + 1] = s.name
			elseif v ~= A.GetSetting(s) then
				A.ApplySetting(s, v)
				A.ConfigOverrides[key] = v
				changed[#changed + 1] = s.name .. " = " .. tostring(v)
			end
		end
	end
	if #bad > 0 then
		NYRP.Notify(ply, "Неверные значения: " .. table.concat(bad, ", "), "error", 8)
	end
	if #changed == 0 then
		if #bad == 0 then NYRP.Notify(ply, "Изменений нет", "info", 3) end
		A.SendConfig(ply)
		return
	end
	A.SaveConfig()
	reapplyMovement()
	A.SendConfig()
	NYRP.Notify(ply, "Настройки сохранены (" .. #changed .. ")", "success", 4)
	if NYRP.Log and NYRP.Log.Add then NYRP.Log.Add("admin", "изменил настройки: " .. table.concat(changed, "; "), ply) end
end)

-- Сбросить настройку к значению по умолчанию: req "cfgreset" + ключ
function A.ResetSetting(ply, key)
	local s = A.SettingByKey[key]
	if not s then return end
	A.ApplySetting(s, s.def)
	A.ConfigOverrides[key] = nil
	A.SaveConfig()
	reapplyMovement()
	A.SendConfig()
	NYRP.Notify(ply, "«" .. s.name .. "» сброшено: " .. tostring(s.def), "success", 4)
	if NYRP.Log and NYRP.Log.Add then NYRP.Log.Add("admin", "сбросил настройку " .. s.name .. " → " .. tostring(s.def), ply) end
end
