--[[
	Фоновая музыка (sound/nyrp/music/night_city.ogg) по кругу.
	Громкость — nyrp_music_volume; в меню немного громче.
]]

local channel
local current = 0

local function start()
	if IsValid(channel) then return end
	sound.PlayFile("sound/nyrp/music/night_city.ogg", "noplay noblock", function(ch, errId, err)
		if not IsValid(ch) then
			NYRP.Print("Музыка не загрузилась: " .. tostring(err or errId))
			return
		end
		channel = ch
		ch:EnableLooping(true)
		ch:SetVolume(0)
		ch:Play()
	end)
end

hook.Add("InitPostEntity", "nyrp.music", start)

hook.Add("Think", "nyrp.music", function()
	if not IsValid(channel) then return end
	local base = GetConVar("nyrp_music_volume"):GetFloat()
	local target = base * (NYRP.HUDHidden() and 1.6 or 1)
	if system.HasFocus and not system.HasFocus() then target = 0 end
	current = NYRP.UI.Approach(current, math.Clamp(target, 0, 1), 1.5)
	channel:SetVolume(current)
end)

concommand.Add("nyrp_music_restart", function()
	if IsValid(channel) then channel:Stop() end
	channel = nil
	start()
end)
