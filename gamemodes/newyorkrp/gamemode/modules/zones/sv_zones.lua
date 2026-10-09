local Z = NYRP.Zones

local function path() return "nyrp/zones_" .. game.GetMap() .. ".json" end

local function pack(z)
	return { id = z.id, name = z.name, icon = z.icon, min = { z.min.x, z.min.y, z.min.z }, max = { z.max.x, z.max.y, z.max.z } }
end

local function unpackZone(t)
	return { id = t.id, name = t.name, icon = t.icon, min = Vector(t.min[1], t.min[2], t.min[3]), max = Vector(t.max[1], t.max[2], t.max[3]) }
end

function Z.Save()
	local out = {}
	for _, z in ipairs(Z.List) do out[#out + 1] = pack(z) end
	file.CreateDir("nyrp")
	file.Write(path(), util.TableToJSON(out, true))
end

function Z.Load()
	Z.List = {}
	for _, t in ipairs(util.JSONToTable(file.Read(path(), "DATA") or "") or {}) do Z.List[#Z.List + 1] = unpackZone(t) end
end

function Z.Send(ply)
	local out = {}
	for _, z in ipairs(Z.List) do out[#out + 1] = pack(z) end
	net.Start("nyrp.zones")
	net.WriteTable(out)
	if ply then net.Send(ply) else net.Broadcast() end
end

hook.Add("InitPostEntity", "nyrp.zones", Z.Load)
hook.Add("PlayerInitialSpawn", "nyrp.zones", function(ply) timer.Simple(3, function() if IsValid(ply) then Z.Send(ply) end end) end)

NYRP.Chat.AddCommand("/areaedit", function(ply)
	if not ply:IsAdmin() then NYRP.Notify(ply, "Только для администрации", "error") return end
	Z.Send(ply)
	net.Start("nyrp.zones.edit")
	net.Send(ply)
end)

net.Receive("nyrp.zones.save", function(_, ply)
	if not ply:IsAdmin() then return end
	local name, icon, a, b = net.ReadString(), net.ReadString(), net.ReadVector(), net.ReadVector()
	name = string.Trim(string.sub(name, 1, 60))
	if name == "" or not table.HasValue(Z.Icons, icon) then return end
	local z = { id = tostring(os.time()) .. math.random(100, 999), name = name, icon = icon,
		min = Vector(math.min(a.x, b.x), math.min(a.y, b.y), math.min(a.z, b.z)),
		max = Vector(math.max(a.x, b.x), math.max(a.y, b.y), math.max(a.z, b.z)) }
	-- зона хотя бы в рост человека
	if z.max.z - z.min.z < 80 then z.max.z = z.min.z + 80 end
	Z.List[#Z.List + 1] = z
	Z.Save()
	Z.Send()
	NYRP.Notify(ply, "Зона «" .. name .. "» сохранена", "success")
end)

net.Receive("nyrp.zones.del", function(_, ply)
	if not ply:IsAdmin() then return end
	local id = net.ReadString()
	for i, z in ipairs(Z.List) do
		if z.id == id then
			table.remove(Z.List, i)
			Z.Save()
			Z.Send()
			NYRP.Notify(ply, "Зона «" .. z.name .. "» удалена", "success")
			return
		end
	end
end)
