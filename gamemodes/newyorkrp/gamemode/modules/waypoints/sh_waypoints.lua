--[[
	Метки на карте: значок, подпись и расстояние; за краем экрана — стрелка у края.
	Сервер: NYRP.Waypoint.Set(ply, id, pos, label, icon, color, { radius = 120, onReach = fn(ply) })
	        NYRP.Waypoint.Clear(ply, id)  (id = nil — все)
]]
NYRP.Waypoint = NYRP.Waypoint or {}
