--[[
	Граффити (сервер): нанесение баллончиком, стирание губкой или руками, сохранение для карты.
	Данные: data/nyrp/graffiti_<карта>.json — список { id, p = {x,y,z}, n = {x,y,z}, tag, col, rot, s, by, name, t }.
]]

NYRP.StreetFun = NYRP.StreetFun or {}
local SF = NYRP.StreetFun

SF.Graffiti = SF.Graffiti or {}
local list = SF.Graffiti
local nextId = 1

local function path() return "nyrp/graffiti_" .. game.GetMap() .. ".json" end

local function save()
	file.CreateDir("nyrp")
	file.Write(path(), util.TableToJSON(list))
end

local function writeOne(g)
	net.WriteUInt(g.id, 32)
	net.WriteVector(Vector(g.p[1], g.p[2], g.p[3]))
	net.WriteVector(Vector(g.n[1], g.n[2], g.n[3]))
	net.WriteUInt(g.tag, 8)
	net.WriteString(g.col)
	net.WriteFloat(g.rot or 0)
	net.WriteFloat(g.s or 1)
end

local function sendAll(ply)
	net.Start("nyrp.graf.full")
	net.WriteUInt(#list, 8)
	for _, g in ipairs(list) do writeOne(g) end
	if ply then net.Send(ply) else net.Broadcast() end
end

local function load()
	list = util.JSONToTable(file.Read(path(), "DATA") or "") or {}
	SF.Graffiti = list
	nextId = 1
	for _, g in ipairs(list) do nextId = math.max(nextId, (g.id or 0) + 1) end
	sendAll()
end
hook.Add("InitPostEntity", "nyrp.graffiti", function(...) load(...) end)

net.Receive("nyrp.graf.req", function(_, ply)
	if ply.nyrpGrafReq then return end
	ply.nyrpGrafReq = true
	sendAll(ply)
end)

local function remove(idx)
	local g = table.remove(list, idx)
	if not g then return end
	net.Start("nyrp.graf.del")
	net.WriteUInt(g.id, 32)
	net.Broadcast()
	return g
end

local function nearest(pos, maxDist)
	local best, bestD
	for i, g in ipairs(list) do
		local d = pos:Distance(Vector(g.p[1], g.p[2], g.p[3]))
		if d <= maxDist and (not bestD or d < bestD) then best, bestD = i, d end
	end
	return best
end
SF.NearestGraffiti = nearest

local function charId(ply) return ply.nyrpChar and ply.nyrpChar.id end

-- годится ли место: стена (не пол/потолок), карта, недалеко
local function wallTrace(ply)
	local tr = util.TraceLine({ start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * 110, filter = ply, mask = MASK_SOLID })
	if not tr.Hit or tr.HitSky or not tr.HitWorld then return nil, "Наносите на стену рядом с собой" end
	if math.abs(tr.HitNormal.z) > 0.35 then return nil, "Рисуют на стенах — не на полу и не на потолке" end
	return tr
end

-- баллончик в руке: id предмета и сам предмет
local function canInHand(ply)
	local it = NYRP.Inv.Get(ply).equip.tool
	if it and SF.ColorOf(it.id) then return it end
end

local function useCan(ply, it)
	local def = NYRP.Items.Get(it.id)
	it.data = it.data or {}
	it.data.uses = (it.data.uses or (def and def.uses) or 8) - 1
	if it.data.uses <= 0 then
		NYRP.Inv.Get(ply).equip.tool = nil
		if ply:HasWeapon("nyrp_spraycan") then ply:StripWeapon("nyrp_spraycan") end
		NYRP.Notify(ply, "Баллончик пуст — выбросили", "warning", 4)
	end
	NYRP.Inv.Sync(ply)
end

function SF.Spray(ply, tag)
	if (ply.nyrpSprayNext or 0) > CurTime() then
		NYRP.Notify(ply, "Подождите немного", "warning", 2)
		return
	end
	local it = canInHand(ply)
	if not it or not SF.Tags[tag] then return end
	local tr, why = wallTrace(ply)
	if not tr then NYRP.Notify(ply, why, "warning", 3) return end
	local hit, normal = tr.HitPos, tr.HitNormal
	local snd = CreateSound(ply, "ambient/gas/steam_loop1.wav")
	if snd then snd:PlayEx(0.35, 170) end
	ply:EmitSound("weapons/smg1/switch_single.wav", 55, 160)
	ply:SetNW2Float("nyrp.sprayUntil", CurTime() + SF.SprayTime)
	ply:SetNW2String("nyrp.sprayCol", SF.ColorOf(it.id) or "white")
	local ok = NYRP.Action(ply, "Рисую граффити...", SF.SprayTime, function()
		if snd then snd:Stop() end
		local now = canInHand(ply)
		if now ~= it then return end
		local tr2 = wallTrace(ply)
		if not tr2 or tr2.HitPos:Distance(hit) > 40 then NYRP.Notify(ply, "Рука дёрнулась — рисунок не получился", "warning", 3) return end
		-- рисунок поверх старого — старый закрашивается
		local old = nearest(hit, 28)
		if old then remove(old) end
		while #list >= SF.MaxGraffiti do remove(1) end
		local p = hit + normal * 0.6
		local g = { id = nextId, p = { p.x, p.y, p.z }, n = { normal.x, normal.y, normal.z }, tag = tag, col = SF.ColorOf(it.id),
			rot = math.Rand(-7, 7), s = math.Rand(0.9, 1.1), by = charId(ply), name = NYRP.CharName(ply), t = os.time() }
		nextId = nextId + 1
		list[#list + 1] = g
		save()
		net.Start("nyrp.graf.add")
		writeOne(g)
		net.Broadcast()
		ply.nyrpSprayNext = CurTime() + 12
		useCan(ply, it)
		hook.Run("NYRP.GraffitiSprayed", ply, g)
		if math.random() < 0.15 and NYRP.E911 and NYRP.E911.Auto then
			NYRP.E911.Auto("police", p, "Вандализм: граффити на стене")
		end
	end, "flame")
	if not ok then
		if snd then snd:Stop() end
		ply:SetNW2Float("nyrp.sprayUntil", 0)
		return
	end
	-- если действие прервали (смерть и т.п.) — глушим звук
	timer.Simple(SF.SprayTime + 0.2, function() if snd then snd:Stop() end end)
end

net.Receive("nyrp.graf.spray", function(_, ply)
	if (ply.nyrpGrafNet or 0) > CurTime() then return end
	ply.nyrpGrafNet = CurTime() + 0.5
	local tag = net.ReadUInt(8)
	if not NYRP.HasCharacter(ply) or not ply:Alive() then return end
	local w = ply:GetActiveWeapon()
	if not IsValid(w) or w:GetClass() ~= "nyrp_spraycan" then return end
	SF.Spray(ply, tag)
end)

-- --------------------------------------------------------------- стирание --
function SF.TryErase(ply, sponge)
	if ply.nyrpAction then return false end
	local tr = util.TraceLine({ start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * 110, filter = ply })
	if not tr.Hit then return false end
	local idx = nearest(tr.HitPos, 50)
	if not idx then
		if sponge then NYRP.Notify(ply, "Здесь нечего оттирать", "info", 2) end
		return false
	end
	local g = list[idx]
	local gid = g.id
	local dur = sponge and SF.EraseSponge or SF.EraseHands
	ply:EmitSound("ambient/water/water_splash" .. math.random(1, 3) .. ".wav", 50, 120)
	local tname = "nyrp.graf.scrub." .. ply:EntIndex()
	timer.Create(tname, 0.7, math.floor(dur / 0.7), function()
		if IsValid(ply) and ply.nyrpAction then ply:EmitSound("player/footsteps/sand" .. math.random(1, 4) .. ".wav", 45, math.random(130, 150), 0.6) end
	end)
	NYRP.Action(ply, sponge and "Оттираю граффити губкой..." or "Оттираю граффити руками...", dur, function()
		timer.Remove(tname)
		local i
		for k, x in ipairs(list) do if x.id == gid then i = k break end end
		if not i then return end
		if ply:EyePos():Distance(Vector(g.p[1], g.p[2], g.p[3])) > 160 then NYRP.Notify(ply, "Вы отошли от рисунка", "warning", 3) return end
		remove(i)
		save()
		NYRP.Notify(ply, "Стена чистая", "success", 3)
		NYRP.Skills.AddXP(ply, "strength", 2, "уборка граффити")
		if ply:GetNW2String("nyrp.job", "") == "cleaner" and g.by ~= charId(ply) then
			NYRP.Money.Add(ply, SF.CleanerPay)
			NYRP.Notify(ply, "Городская служба: +" .. NYRP.Money.Format(SF.CleanerPay) .. " за очистку стены", "success", 4)
			ply:EmitSound("nyrp/fx/cash.wav", 50)
		end
		hook.Run("NYRP.GraffitiErased", ply, g)
	end, "droplet")
	return true
end

-- руками: E по рисунку на стене (если перед вами нет ничего, с чем можно взаимодействовать)
hook.Add("KeyPress", "nyrp.graffiti.erase", function(ply, key)
	if key ~= IN_USE or not ply:Alive() or not NYRP.HasCharacter(ply) or #list == 0 then return end
	if (ply.nyrpGrafUse or 0) > CurTime() then return end
	ply.nyrpGrafUse = CurTime() + 0.6
	local tr = ply:GetEyeTrace()
	if not tr.HitWorld or tr.HitPos:Distance(ply:EyePos()) > 110 then return end
	local w = ply:GetActiveWeapon()
	if IsValid(w) and (w:GetClass() == "nyrp_spraycan" or w:GetClass() == "nyrp_sponge") then return end
	SF.TryErase(ply, false)
end)

-- ------------------------------------------------------------- админам --
NYRP.Chat.AddCommand("/graffitiwipe", function(ply)
	if not ply:IsAdmin() then NYRP.Notify(ply, "Только для администрации", "error") return end
	local n = #list
	list = {}
	SF.Graffiti = list
	save()
	sendAll()
	NYRP.Notify(ply, "Стёрто граффити: " .. n, "success")
end)

NYRP.Chat.AddCommand("/graffitiremove", function(ply)
	if not ply:IsAdmin() then NYRP.Notify(ply, "Только для администрации", "error") return end
	local idx = nearest(ply:GetEyeTrace().HitPos, 60)
	if not idx then NYRP.Notify(ply, "Посмотрите на граффити", "warning") return end
	local g = remove(idx)
	save()
	NYRP.Notify(ply, "Граффити удалено (автор: " .. (g.name or "?") .. ")", "success")
end)
