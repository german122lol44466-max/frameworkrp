local S = NYRP.Street
local FILE = function() return "nyrp/street_" .. game.GetMap() .. ".json" end
S.News = S.News or {}

-- события в газету: S.AddNews("текст")
function S.AddNews(text)
	table.insert(S.News, 1, { text = text, t = os.date("%H:%M") })
	while #S.News > 8 do table.remove(S.News) end
end

function S.Save()
	if S.Loading then return end
	local out = {}
	for _, e in ipairs(ents.GetAll()) do
		if e.NYRPStreet and e.Kind then
			local p, a = e:GetPos(), e:GetAngles()
			out[#out + 1] = { kind = e.Kind, pos = { p.x, p.y, p.z }, ang = { a.p, a.y, a.r } }
		end
	end
	file.CreateDir("nyrp")
	file.Write(FILE(), util.TableToJSON(out, true))
end

function S.Spawn(kind, pos, ang)
	if not S.Types[kind] then return end
	local e = ents.Create("nyrp_street_" .. kind)
	if not IsValid(e) then return end
	e:SetPos(pos)
	e:SetAngles(ang)
	e:Spawn()
	return e
end

local function load()
	S.Loading = true
	for _, e in ipairs(ents.GetAll()) do if e.NYRPStreet then e:Remove() end end
	for _, t in ipairs(util.JSONToTable(file.Read(FILE(), "DATA") or "") or {}) do
		S.Spawn(t.kind, Vector(t.pos[1], t.pos[2], t.pos[3]), Angle(t.ang[1], t.ang[2], t.ang[3]))
	end
	S.Loading = false
end
hook.Add("InitPostEntity", "nyrp.street", function() timer.Simple(1, load) end)
hook.Add("PostCleanupMap", "nyrp.street", function() timer.Simple(0, load) end)
hook.Add("PhysgunDrop", "nyrp.street", function(_, e) if e.NYRPStreet then timer.Simple(0, S.Save) end end)

NYRP.Chat.AddCommand("/street", function(ply, raw)
	if not ply:IsAdmin() then return end
	local kind = string.match(raw, "^%S+%s+(%S+)")
	if not S.Types[kind or ""] then
		local list = {}
		for k, t in pairs(S.Types) do list[#list + 1] = k .. " — " .. t.name end
		NYRP.Notify(ply, "/street <вид>: " .. table.concat(list, ", "), "info", 12)
		return
	end
	local tr = ply:GetEyeTrace()
	local e = S.Spawn(kind, tr.HitPos, Angle(0, ply:EyeAngles().y + 180, 0))
	if IsValid(e) then
		undo.Create("Уличный объект") undo.AddEntity(e) undo.SetPlayer(ply) undo.Finish()
		S.Save()
		NYRP.Notify(ply, S.Types[kind].name .. " поставлен(а) и сохранён(а)", "success")
	end
end)
NYRP.Chat.AddCommand("/streetremove", function(ply)
	if not ply:IsAdmin() then return end
	local e = ply:GetEyeTrace().Entity
	if IsValid(e) and e.NYRPStreet then e:Remove() timer.Simple(0, S.Save) NYRP.Notify(ply, "Убрано", "success") end
end)

local function pay(ply, sum)
	if NYRP.Money.Get(ply) < sum then NYRP.Notify(ply, "Не хватает наличных: нужно " .. NYRP.Money.Format(sum), "error") return false end
	NYRP.Money.Add(ply, -sum)
	return true
end

-- что делает объект по E
S.Use = {
	hydrant = function(ply, e)
		local w = ply:GetActiveWeapon()
		if IsValid(w) and w:GetClass() == "nyrp_extinguisher" then
			NYRP.Action(ply, "Заправляю огнетушитель...", 3, function()
				if IsValid(w) then w:SetCharge(100) end
				e:EmitSound("ambient/water/water_spray1.wav", 60)
				NYRP.Notify(ply, "Огнетушитель заправлен", "success")
			end, "droplet")
		else
			NYRP.Notify(ply, "Гидрант FDNY. С огнетушителем в руках — E, чтобы заправить.", "info", 4)
		end
	end,
	newsbox = function(ply)
		if not pay(ply, 1) then return end
		ply:EmitSound("physics/metal/metal_box_impact_soft2.wav", 55)
		local news = {}
		for _, n in ipairs(S.News) do news[#news + 1] = n.t .. " · " .. n.text end
		local pool = table.Copy(S.Headlines)
		for i = 1, 4 do news[#news + 1] = table.remove(pool, math.random(#pool)) end
		net.Start("nyrp.street") net.WriteString("news") net.WriteTable(news) net.Send(ply)
	end,
	parkingmeter = function(ply)
		if not pay(ply, 2) then return end
		ply:SetNW2Float("nyrp.parkedUntil", CurTime() + 3600)
		ply:EmitSound("buttons/button14.wav", 50)
		NYRP.Notify(ply, "Парковка оплачена на 1 час. Квитанция у вас.", "success")
	end,
	usps = function(ply)
		NYRP.Notify(ply, "Почта США: письма отсюда забирают почтальоны (профессия «Почтальон»).", "info", 5)
	end,
	hotdog = function(ply)
		net.Start("nyrp.street") net.WriteString("food") net.WriteTable(S.Food) net.Send(ply)
	end,
	trash = function(ply, e)
		local inv = NYRP.Inv.Get(ply)
		local n = 0
		for slot, it in pairs(inv.slots) do
			local def = NYRP.Items.Get(it.id)
			if def and def.buffs and def.buffs[1] and def.buffs[1][1] == "Мусор" then n = n + it.n inv.slots[slot] = nil end
		end
		if n == 0 then NYRP.Notify(ply, "Мусора в сумке нет", "info") return end
		NYRP.Inv.Sync(ply)
		e:EmitSound("physics/cardboard/cardboard_box_impact_soft" .. math.random(1, 3) .. ".wav", 55)
		NYRP.Notify(ply, "Выброшено: " .. n .. " шт. Город стал чище.", "success")
		hook.Run("NYRP.TrashThrown", ply, e, n)
	end,
	payphone = function(ply)
		net.Start("nyrp.street") net.WriteString("payphone") net.WriteTable({}) net.Send(ply)
	end,
	busstop = function(ply)
		local m = math.random(2, 14)
		NYRP.Notify(ply, "Автобус M15 (South Ferry ↔ East Harlem): следующий через " .. m .. " мин.", "info", 6)
	end,
}

net.Receive("nyrp.street.buy", function(_, ply)
	if (ply.nyrpStreetNext or 0) > CurTime() then return end
	ply.nyrpStreetNext = CurTime() + 0.4
	local ent, id = net.ReadEntity(), net.ReadString()
	if not IsValid(ent) or ent.Kind ~= "hotdog" or ent:GetPos():Distance(ply:GetPos()) > 160 then return end
	for _, f in ipairs(S.Food) do
		if f.id == id then
			if not pay(ply, f.price) then return end
			if NYRP.Inv.Add(ply, id, 1) <= 0 then NYRP.Inv.DropNew(ply, id, 1) end
			ply:EmitSound("nyrp/fx/cash.wav", 50)
			NYRP.Notify(ply, "Куплено: " .. NYRP.Items.Get(id).name, "success", 3)
		end
	end
end)

