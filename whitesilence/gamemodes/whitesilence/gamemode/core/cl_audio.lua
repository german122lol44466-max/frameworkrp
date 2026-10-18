--[[
	Звук через BASS (sound.PlayFile) с плавной громкостью.

	local h = WS.Audio.Play("whitesilence/intro/blizzard.ogg", { volume = 0.8, fade = 2, loop = true })
	h:Fade(0.3, 1.5)   -- к громкости 0.3 за 1.5 с
	h:Stop(2)          -- затухание за 2 с и остановка
	Громкость умножается на ws_volume (0..1).
]]

local A = WS.Audio
A.Active = A.Active or {}

local master = CreateClientConVar("ws_volume", "0.8", true, false, "Громкость звуков режима (0..1)", 0, 1)

local Handle = {}
Handle.__index = Handle

function Handle:Fade(target, time)
	self.from = self.cur
	self.to = target
	self.t0 = RealTime()
	self.dur = math.max(time or 0, 0.001)
	return self
end

function Handle:Stop(time)
	self.stopping = true
	if (time or 0) <= 0 then
		if IsValid(self.ch) then self.ch:Stop() end
		self.dead = true
		return
	end
	self:Fade(0, time)
end

function Handle:IsPlaying()
	return not self.dead
end

function A.Play(path, opts)
	opts = opts or {}
	local h = setmetatable({ cur = 0, from = 0, to = opts.volume or 1, t0 = RealTime(), dur = math.max(opts.fade or 0, 0.001) }, Handle)
	if (opts.fade or 0) <= 0 then h.cur = h.to h.from = h.to end
	A.Active[h] = true
	sound.PlayFile("sound/" .. path, "noplay", function(ch, errId, err)
		if not IsValid(ch) then
			WS.Print("Звук не загрузился: %s (%s)", path, tostring(err or errId))
			h.dead = true
			return
		end
		if h.dead then ch:Stop() return end
		h.ch = ch
		if opts.loop then ch:EnableLooping(true) end
		ch:SetVolume(h.cur * master:GetFloat())
		ch:Play()
	end)
	return h
end

function A.StopAll(time)
	for h in pairs(A.Active) do h:Stop(time) end
end

hook.Add("Think", "ws.audio", function()
	local m = master:GetFloat()
	local now = RealTime()
	for h in pairs(A.Active) do
		local k = math.Clamp((now - h.t0) / h.dur, 0, 1)
		h.cur = Lerp(k * k * (3 - 2 * k), h.from, h.to)
		local ch = h.ch
		if IsValid(ch) then
			ch:SetVolume(h.cur * m)
			-- после Stop() канал становится NULL — больше его не трогаем
			if h.stopping and k >= 1 then
				ch:Stop()
				h.dead = true
			elseif not h.stopping and ch:GetState() == GMOD_CHANNEL_STOPPED then
				h.dead = true
			end
		elseif h.ch ~= nil then
			h.dead = true   -- канал освободил сам BASS
		end
		if h.dead then A.Active[h] = nil end
	end
end)
