--[[
	Голос на клиенте: минималистичная панель говорящих (слева, у середины экрана) и иконка микрофона
	над головой говорящего в мире (пульсирует с громкостью). Стандартные панели голоса отключены.
]]

local L = WS.Lobby
local UI = WS.UI
local E = WS.Ease
local speakers = {}   -- [ply] = { t = начало, a = прозрачность, on = говорит }

hook.Add("PlayerStartVoice", "ws.voice", function(ply)
	if not IsValid(ply) then return true end
	local s = speakers[ply] or { a = 0 }
	s.on, s.t = true, RealTime()
	speakers[ply] = s
	return true   -- без стандартной панели
end)

hook.Add("PlayerEndVoice", "ws.voice", function(ply)
	if speakers[ply] then speakers[ply].on = false end
	return true
end)

local function icon(n) return UI.Mat("whitesilence/icons/" .. n .. ".png", "smooth") end

hook.Add("HUDPaint", "ws.voice.panel", function()
	local w, h = ScrW(), ScrH()
	local s = h / 1080
	local me = LocalPlayer()
	local y = h * 0.42
	local font = WS.Font("menusemi", 18)
	local dt = FrameTime()
	for ply, st in pairs(speakers) do
		if not IsValid(ply) then speakers[ply] = nil goto next end
		st.a = WS.Approach(st.a, st.on and 1 or 0, st.on and 6 or 2.5)
		if st.a <= 0 and not st.on then speakers[ply] = nil goto next end
		do
			local vol = st.on and math.Clamp(ply:VoiceVolume() * 3, 0, 1) or 0
			local mate = ply ~= me and L.Id(ply) ~= 0 and L.Id(ply) == L.Id(me)
			local col = mate and Color(226, 190, 120) or Color(232, 236, 242)
			local x = 20 * s - (1 - E.OutCubic(st.a)) * 30 * s
			local name = L.Name(ply)
			surface.SetFont(font)
			local tw, th = surface.GetTextSize(name)
			local rh = 30 * s
			draw.RoundedBox(4, x, y, tw + 64 * s, rh, Color(6, 8, 12, 150 * st.a))
			-- микрофон пульсирует с громкостью
			surface.SetMaterial(icon("mic"))
			surface.SetDrawColor(col.r, col.g, col.b, (140 + 115 * vol) * st.a)
			local is = (18 + 4 * vol) * s
			surface.DrawTexturedRect(x + 16 * s - is / 2, y + rh / 2 - is / 2, is, is)
			draw.SimpleText(name, font, x + 32 * s, y + rh / 2, Color(col.r, col.g, col.b, 255 * st.a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			-- полоска уровня под ником
			surface.SetDrawColor(col.r, col.g, col.b, 160 * st.a)
			surface.DrawRect(x + 32 * s, y + rh - 4 * s, tw * vol, 2 * s)
			y = y + rh + 6 * s
		end
		::next::
	end
end)

-- иконка над головой говорящего
hook.Add("PostDrawTranslucentRenderables", "ws.voice.overhead", function(depth, skybox)
	if skybox then return end
	local me = LocalPlayer()
	local eye = EyePos()
	render.SetMaterial(icon("mic"))
	for _, ply in ipairs(player.GetAll()) do
		if ply ~= me and ply:IsSpeaking() and ply:Alive() and not ply:GetNoDraw() then
			local pos = ply:GetPos() + Vector(0, 0, ply:Crouching() and 52 or 82)
			local d = eye:Distance(pos)
			if d < 1600 then
				local vol = math.Clamp(ply:VoiceVolume() * 3, 0, 1)
				local a = 255 * (1 - math.Clamp((d - 1100) / 500, 0, 1))
				local mate = L.Id(ply) ~= 0 and L.Id(ply) == L.Id(me)
				local c = mate and Color(226, 190, 120, a) or Color(235, 238, 244, a)
				local size = 9 + 3 * vol
				render.DrawSprite(pos, size, size, c)
			end
		end
	end
end)
