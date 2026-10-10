--[[
	Предметы на земле переживают рестарт (идея — saveitems из Helix).
	Все nyrp_item сохраняются в data/nyrp/items_<карта>.json при выключении/смене карты и каждые 5 минут,
	при старте восстанавливаются. Предметы, лежащие дольше суток реального времени, не восстанавливаются.
	Админ: nyrp_items_save — сохранить сейчас.
]]

NYRP.World = NYRP.World or {}
local W = NYRP.World

local MAX_ITEMS = 600

local function path() return "nyrp/items_" .. game.GetMap() .. ".json" end

-- Когда предмет появился в мире (реальное время).
hook.Add("OnEntityCreated", "nyrp.saveitems", function(ent)
	if IsValid(ent) and ent:GetClass() == "nyrp_item" and not ent.nyrpDroppedAt then
		ent.nyrpDroppedAt = os.time()
	end
end)

function W.SaveItems()
	local out = {}
	for _, ent in ipairs(ents.FindByClass("nyrp_item")) do
		if #out >= MAX_ITEMS then break end
		local id = IsValid(ent) and ent.GetItemID and ent:GetItemID() or ""
		if id ~= "" and NYRP.Items and NYRP.Items.Get(id) and not IsValid(ent:GetParent()) then
			local p, a = ent:GetPos(), ent:GetAngles()
			out[#out + 1] = {
				id = id, n = ent:GetAmount(), data = ent.ItemData,
				pos = { math.Round(p.x, 1), math.Round(p.y, 1), math.Round(p.z, 1) },
				ang = { math.Round(a.p, 1), math.Round(a.y, 1), math.Round(a.r, 1) },
				t = ent.nyrpDroppedAt or os.time(),
			}
		end
	end
	local ok, s = pcall(util.TableToJSON, out)
	if not ok or not s then
		NYRP.Print("Предметы на земле: не удалось сохранить (" .. tostring(s) .. ")")
		return
	end
	file.CreateDir("nyrp")
	file.Write(path(), s)
	return #out
end

function W.RestoreItems()
	local raw = file.Read(path(), "DATA")
	if not raw then return end
	local ok, list = pcall(util.JSONToTable, raw)
	if not ok or not istable(list) then return end
	local now, maxAge = os.time(), W.Config.ItemsMaxAge
	local n, old = 0, 0
	for _, d in ipairs(list) do
		local t = tonumber(d.t) or 0
		if now - t > maxAge then
			old = old + 1
		elseif isstring(d.id) and NYRP.Items and NYRP.Items.Get(d.id) and istable(d.pos) then
			local ent = ents.Create("nyrp_item")
			if IsValid(ent) then
				ent.nyrpDroppedAt = t
				ent:SetPos(Vector(tonumber(d.pos[1]) or 0, tonumber(d.pos[2]) or 0, (tonumber(d.pos[3]) or 0) + 1))
				local a = istable(d.ang) and d.ang or {}
				ent:SetAngles(Angle(tonumber(a[1]) or 0, tonumber(a[2]) or 0, tonumber(a[3]) or 0))
				ent:SetItem(d.id, math.max(1, math.floor(tonumber(d.n) or 1)), istable(d.data) and d.data or nil)
				ent:Spawn()
				local phys = ent:GetPhysicsObject()
				if IsValid(phys) then phys:Sleep() end
				n = n + 1
			end
		end
	end
	NYRP.Print(string.format("Предметы на земле: восстановлено %d, устарело %d", n, old))
end

hook.Add("InitPostEntity", "nyrp.saveitems", function()
	timer.Simple(2, function()
		W.RestoreItems()
		W.ItemsRestored = true
	end)
end)

-- Пока предметы не восстановлены, не перезаписываем файл пустым списком.
local function autosave()
	if W.ItemsRestored then W.SaveItems() end
end
timer.Create("nyrp.saveitems", W.Config.ItemsSaveEvery, 0, autosave)
hook.Add("ShutDown", "nyrp.saveitems", autosave)

concommand.Add("nyrp_items_save", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	local n = W.SaveItems() or 0
	if IsValid(ply) then NYRP.Notify(ply, "Предметов на земле сохранено: " .. n, "success") else print("сохранено: " .. n) end
end)
