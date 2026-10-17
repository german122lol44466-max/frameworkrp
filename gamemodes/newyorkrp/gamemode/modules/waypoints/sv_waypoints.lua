local W = NYRP.Waypoint

-- opts: radius (по умолчанию 120) — дошёл в этот радиус: метка исчезает и вызывается onReach(ply);
--       keep = true — метка остаётся после прибытия (onReach вызывается один раз);
--       clearOnDeath = true — снять при смерти.
function W.Set(ply, id, pos, label, icon, color, opts)
	if not IsValid(ply) or not isvector(pos) then return end
	ply.nyrpWP = ply.nyrpWP or {}
	ply.nyrpWP[id] = { pos = pos, opts = opts or {}, char = ply.nyrpChar and ply.nyrpChar.id }
	net.Start("nyrp.wp")
	net.WriteString(id)
	net.WriteBool(true)
	net.WriteVector(pos)
	net.WriteString(label or "")
	net.WriteString(icon or "map_pin")
	net.WriteColor(color or Color(247, 198, 0))
	net.Send(ply)
end

function W.Clear(ply, id)
	if not IsValid(ply) or not ply.nyrpWP then return end
	local ids = {}
	if id then
		if ply.nyrpWP[id] then ids[1] = id end
	else
		for k in pairs(ply.nyrpWP) do ids[#ids + 1] = k end
	end
	for _, k in ipairs(ids) do
		ply.nyrpWP[k] = nil
		net.Start("nyrp.wp")
		net.WriteString(k)
		net.WriteBool(false)
		net.Send(ply)
	end
end

function W.Has(ply, id) return ply.nyrpWP and ply.nyrpWP[id] ~= nil end

-- прибыл на место: метка снимается (кроме keep), onReach — один раз
timer.Create("nyrp.wp", 0.5, 0, function()
	for _, ply in ipairs(player.GetAll()) do
		if ply.nyrpWP and ply:Alive() then
			local reached = {}
			for id, w in pairs(ply.nyrpWP) do
				if not w.done and ply:GetPos():DistToSqr(w.pos) < (w.opts.radius or 120) ^ 2 then reached[#reached + 1] = id end
			end
			for _, id in ipairs(reached) do
				local w = ply.nyrpWP[id]
				if w then
					local fn = w.opts.onReach
					if w.opts.keep then w.done = true else W.Clear(ply, id) end
					if fn then ProtectedCall(function() fn(ply) end) end
				end
			end
		end
	end
end)

hook.Add("PlayerDeath", "nyrp.wp", function(ply)
	local ids = {}
	for id, w in pairs(ply.nyrpWP or {}) do if w.opts.clearOnDeath then ids[#ids + 1] = id end end
	for _, id in ipairs(ids) do W.Clear(ply, id) end
end)

-- смена персонажа: метки прошлого персонажа снимаются
hook.Add("NYRP.CharacterLoaded", "nyrp.wp", function(ply, c)
	local ids = {}
	for id, w in pairs(ply.nyrpWP or {}) do if w.char ~= (c and c.id) then ids[#ids + 1] = id end end
	for _, id in ipairs(ids) do W.Clear(ply, id) end
end)
