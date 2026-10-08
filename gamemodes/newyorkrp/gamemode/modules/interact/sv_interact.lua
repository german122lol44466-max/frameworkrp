--[[
	E по подсвеченной цели, когда луч прошёл чуть мимо (клиент «примагничивает» прицел).
	Проверяем дистанцию и прямую видимость, затем нажимаем за игрока.
]]

local doors = { prop_door_rotating = true, func_door = true, func_door_rotating = true }

net.Receive("nyrp.interact.use", function(_, ply)
	if (ply.nyrpUseNext or 0) > CurTime() then return end
	ply.nyrpUseNext = CurTime() + 0.25
	local ent = net.ReadEntity()
	if not IsValid(ent) or not ply:Alive() or not NYRP.HasCharacter(ply) then return end
	if not doors[ent:GetClass()] and not ent.NYRPInteract then return end
	local eye = ply:EyePos()
	local near = ent:NearestPoint(eye)
	if near:Distance(eye) > NYRP.Config.Ranges.Interact + 30 then return end
	local tr = util.TraceLine({ start = eye, endpos = near, filter = { ply, ent }, mask = MASK_SOLID_BRUSHONLY })
	if tr.Hit and tr.Fraction < 0.95 then return end
	ent:Use(ply, ply, USE_TOGGLE, 1)
end)
