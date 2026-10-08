--[[
	Сервер: ход времени, свет карты (light style 0), небо (env_skypaint), сохранение времени.
]]

local T = NYRP.Time
local FILE = "nyrp/time.txt"

function T.Set(hour)
	SetGlobal2Float("nyrp.timeBase", CurTime())
	SetGlobal2Float("nyrp.timeHour", hour % 24)
end

hook.Add("Initialize", "nyrp.time", function()
	local saved = tonumber(file.Read(FILE, "DATA") or "")
	T.Set(saved or NYRP.Config.StartHour)
end)

timer.Create("nyrp.time.save", 30, 0, function()
	file.CreateDir("nyrp")
	file.Write(FILE, tostring(T.Hour()))
end)

-- Свет: буквы light style от «b» (ночь) до «m» (обычный день).
local NIGHT, DAY = string.byte("b"), string.byte("m")
local lastLetter

local function skyColors(d)
	-- ночь -> день
	local top = LerpVector(d, Vector(0.01, 0.015, 0.05), Vector(0.22, 0.45, 0.85))
	local bottom = LerpVector(d, Vector(0.02, 0.03, 0.07), Vector(0.75, 0.82, 0.9))
	return top, bottom
end

local function apply(force)
	local h = T.Hour()
	local d = T.Daylight(h)
	local letter = string.char(math.Round(Lerp(d, NIGHT, DAY)))
	if letter ~= lastLetter or force then
		lastLetter = letter
		engine.LightStyle(0, letter)
		net.Start("nyrp.time.light")
		net.Broadcast()
	end
	for _, sky in ipairs(ents.FindByClass("env_skypaint")) do
		local top, bottom = skyColors(d)
		local dusk = (h >= 5 and h < 8) or (h >= 18 and h < 21)
		sky:SetTopColor(top)
		sky:SetBottomColor(bottom)
		sky:SetDuskIntensity(dusk and 1.2 or 0)
		sky:SetDuskColor(Vector(1, 0.35, 0.1))
		sky:SetStarFade(Lerp(d, 1.5, 0))
		sky:SetDrawStars(d < 0.5)
		sky:SetSunSize(d * 2)
	end
end

timer.Create("nyrp.time.apply", 5, 0, function() apply(false) end)
hook.Add("InitPostEntity", "nyrp.time", function() timer.Simple(2, function() apply(true) end) end)
hook.Add("PlayerInitialSpawn", "nyrp.time", function(ply)
	timer.Simple(5, function()
		if IsValid(ply) then net.Start("nyrp.time.light") net.Send(ply) end
	end)
end)

concommand.Add("nyrp_settime", function(ply, _, args)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	local h = tonumber(args[1])
	if not h then return end
	T.Set(h)
	apply(true)
	if IsValid(ply) then NYRP.Notify(ply, "Время: " .. T.Format(), "success") end
end)
