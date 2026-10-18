--[[
	Фонарика нет: вместо него ПНВ (клиент, cl_vision.lua). Сервер просто запрещает обычный фонарик.
]]

hook.Add("PlayerSwitchFlashlight", "ws.vision", function(ply, on)
	if on then return false end
end)
