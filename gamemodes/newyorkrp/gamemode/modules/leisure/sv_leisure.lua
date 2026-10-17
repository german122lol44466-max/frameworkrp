--[[
	Развлечения на сервере: расстановка столов для блэкджека и аркадных автоматов, сохранение для карты.
	  data/nyrp/leisure_<карта>.json = { blackjack = {{pos, ang}}, arcade = {{pos, ang}} }
	Админ: /blackjack — поставить стол, /blackjackremove — убрать тот, на который смотрите;
	       /arcade — поставить автомат, /arcaderemove — убрать. Спавн-меню (New-York Roleplay) тоже сохраняет.
]]

NYRP.Leisure = NYRP.Leisure or {}
local LS = NYRP.Leisure

local CLASSES = { blackjack = "nyrp_blackjack", arcade = "nyrp_arcade" }
local function mapFile() return "nyrp/leisure_" .. game.GetMap() .. ".json" end

function LS.SavePlaced()
	local out = {}
	for key, class in pairs(CLASSES) do
		out[key] = {}
		for _, e in ipairs(ents.FindByClass(class)) do
			if IsValid(e) and not e.nyrpRemoving then
				local p, a = e:GetPos(), e:GetAngles()
				out[key][#out[key] + 1] = { pos = { p.x, p.y, p.z }, ang = { a.p, a.y, a.r } }
			end
		end
	end
	file.CreateDir("nyrp")
	file.Write(mapFile(), util.TableToJSON(out, true))
end

function LS.SpawnPlaced(class, pos, ang)
	local e = ents.Create(class)
	if not IsValid(e) then return end
	e:SetPos(pos)
	e:SetAngles(ang)
	e:Spawn()
	return e
end

local function loadPlaced()
	local raw = file.Exists(mapFile(), "DATA") and util.JSONToTable(file.Read(mapFile(), "DATA") or "") or nil
	if not istable(raw) then return end
	for key, class in pairs(CLASSES) do
		-- не дублировать, если уже стоят (повторный вызов)
		for _, e in ipairs(ents.FindByClass(class)) do e:Remove() end
		if istable(raw[key]) then
			for _, m in ipairs(raw[key]) do
				if istable(m.pos) and istable(m.ang) and tonumber(m.pos[1]) and tonumber(m.ang[2]) then
					LS.SpawnPlaced(class, Vector(tonumber(m.pos[1]) or 0, tonumber(m.pos[2]) or 0, tonumber(m.pos[3]) or 0),
						Angle(tonumber(m.ang[1]) or 0, tonumber(m.ang[2]) or 0, tonumber(m.ang[3]) or 0))
				end
			end
		end
	end
end
hook.Add("InitPostEntity", "nyrp.leisure", function() timer.Simple(1, function() loadPlaced() end) end)
hook.Add("PostCleanupMap", "nyrp.leisure", function() timer.Simple(0, function() loadPlaced() end) end)

-- админ передвинул стол/автомат физганом — запомнить новое место
hook.Add("PhysgunDrop", "nyrp.leisure", function(ply, ent)
	if not IsValid(ent) or not IsValid(ply) or not ply:IsAdmin() then return end
	local class = ent:GetClass()
	if class == "nyrp_blackjack" or class == "nyrp_arcade" then
		local phys = ent:GetPhysicsObject()
		if IsValid(phys) then phys:EnableMotion(false) end
		timer.Simple(0, function() LS.SavePlaced() end)
	end
end)

local function cmd(name, fn)
	if NYRP.Chat and NYRP.Chat.AddCommand then NYRP.Chat.AddCommand(name, fn) return end
	timer.Simple(0, function() if NYRP.Chat and NYRP.Chat.AddCommand then NYRP.Chat.AddCommand(name, fn) end end)
end

local function place(ply, class, what)
	if not IsValid(ply) or not ply:IsAdmin() then return end
	local tr = ply:GetEyeTrace()
	if not tr.Hit then NYRP.Notify(ply, "Смотрите на пол", "warning") return end
	local e = LS.SpawnPlaced(class, tr.HitPos + tr.HitNormal * 2, Angle(0, ply:EyeAngles().y + 180, 0))
	if IsValid(e) then
		e:SetPos(tr.HitPos - Vector(0, 0, e:OBBMins().z))   -- низом модели на пол
		LS.SavePlaced()
		NYRP.Notify(ply, what .. " поставлен и сохранён для карты", "success")
	end
end

local function remove(ply, class, what)
	if not IsValid(ply) or not ply:IsAdmin() then return end
	local e = ply:GetEyeTrace().Entity
	if not IsValid(e) or e:GetClass() ~= class then NYRP.Notify(ply, "Смотрите на " .. what, "warning") return end
	e.nyrpRemoving = true
	e:Remove()
	timer.Simple(0, function() LS.SavePlaced() end)
	NYRP.Notify(ply, "Убрано", "success")
end

cmd("/blackjack", function(ply) place(ply, "nyrp_blackjack", "Стол для блэкджека") end)
cmd("/blackjackremove", function(ply) remove(ply, "nyrp_blackjack", "стол для блэкджека") end)
cmd("/arcade", function(ply) place(ply, "nyrp_arcade", "Аркадный автомат") end)
cmd("/arcaderemove", function(ply) remove(ply, "nyrp_arcade", "аркадный автомат") end)
