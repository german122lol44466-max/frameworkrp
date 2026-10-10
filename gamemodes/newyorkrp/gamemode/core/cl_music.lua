--[[
	Фоновая музыка: ночной джаз и lo-fi (Open Lo-Fi, CC0) — плейлист в случайном порядке,
	треки сменяются с плавным затуханием. Громкость — nyrp_music_volume; в меню немного громче.
]]

local TRACKS = {
	"last_train_home", "headlights_on_the_divider", "platform_after_rain", "glow_on_the_overpass", "3_am_echoes",
	"rain_on_the_boulevard", "midnight_amber_room", "streetlights_in_the_rearview", "ashes_in_the_coffee_cup", "midnight_on_my_mind",
}

local channel
local current = 0
local order, pos = {}, 0
local fadeOut = false

local function nextTrack()
	if pos >= #order then
		order = table.Copy(TRACKS)
		for i = #order, 2, -1 do local j = math.random(i) order[i], order[j] = order[j], order[i] end
		pos = 0
	end
	pos = pos + 1
	return order[pos]
end

local function start()
	if IsValid(channel) then return end
	local name = nextTrack()
	sound.PlayFile("sound/nyrp/music/" .. name .. ".ogg", "noplay noblock", function(ch, errId, err)
		if not IsValid(ch) then
			NYRP.Print("Музыка не загрузилась: " .. tostring(err or errId))
			return
		end
		channel = ch
		fadeOut = false
		current = 0
		ch:SetVolume(0)
		ch:Play()
	end)
end

hook.Add("InitPostEntity", "nyrp.music", function(...) start(...) end)

hook.Add("Think", "nyrp.music", function()
	if not IsValid(channel) then return end
	local base = GetConVar("nyrp_music_volume"):GetFloat()
	local target = base * (NYRP.HUDHidden() and 1.6 or 1)
	if system.HasFocus and not system.HasFocus() then target = 0 end
	-- за 4 секунды до конца трека — затухание и следующий
	local left = channel:GetLength() - channel:GetTime()
	if left < 4 or channel:GetState() == GMOD_CHANNEL_STOPPED then fadeOut = true end
	if fadeOut then target = 0 end
	current = NYRP.UI.Approach(current, math.Clamp(target, 0, 1), fadeOut and 0.9 or 1.5)
	channel:SetVolume(current)
	if fadeOut and current < 0.01 then
		channel:Stop()
		channel = nil
		start()
	end
end)

concommand.Add("nyrp_music_next", function()
	if IsValid(channel) then fadeOut = true end
end)

concommand.Add("nyrp_music_restart", function()
	if IsValid(channel) then channel:Stop() end
	channel = nil
	start()
end)
