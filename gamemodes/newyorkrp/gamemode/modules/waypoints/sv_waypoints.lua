local W = NYRP.Waypoint

function W.Set(ply, id, pos, label, icon, color, opts)
	ply.nyrpWP = ply.nyrpWP or {}
	ply.nyrpWP[id] = { pos = pos, opts = opts or {} }
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
	if not ply.nyrpWP then return end
	local ids = {}
	if id then ids[1] = id else for k in pairs(ply.nyrpWP) do ids[#ids + 1] = k end end
	for _, k in ipairs(ids) do
		ply.nyrpWP[k] = nil
		net.Start("nyrp.wp")
		net.WriteString(k)
		net.WriteBool(false)
		net.Send(ply)
	end
end

-- прибыл на место
timer.Create("nyrp.wp", 0.5, 0, function()
	for _, ply in ipairs(player.GetAll()) do
		for id, w in pairs(ply.nyrpWP or {}) do
			if w.opts.onReach and ply:Alive() and ply:GetPos():Distance(w.pos) < (w.opts.radius or 120) then
				local fn = w.opts.onReach
				if w.opts.keep then w.opts.onReach = nil else W.Clear(ply, id) end
				fn(ply)
			end
		end
	end
end)

hook.Add("PlayerDeath", "nyrp.wp", function(ply)
	for id, w in pairs(ply.nyrpWP or {}) do if w.opts.clearOnDeath then W.Clear(ply, id) end end
end)
