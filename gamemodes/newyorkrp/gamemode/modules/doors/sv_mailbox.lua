--[[
	Почтовые ящики: ключи от квартиры выдаются здесь (после аренды или когда вас поселили).
	Ящики сохраняются в data/nyrp/mailboxes_<карта>.json.
]]

local D = NYRP.Doors
local Inv = NYRP.Inv

local function file_() return "nyrp/mailboxes_" .. game.GetMap() .. ".json" end

function D.SaveMailboxes()
	if D.MailLoading then return end
	local out = {}
	for _, e in ipairs(ents.FindByClass("nyrp_mailbox")) do
		local p, a = e:GetPos(), e:GetAngles()
		out[#out + 1] = { pos = { p.x, p.y, p.z }, ang = { a.p, a.y, a.r } }
	end
	file.CreateDir("nyrp")
	file.Write(file_(), util.TableToJSON(out, true))
end

function D.SpawnMailbox(pos, ang)
	local e = ents.Create("nyrp_mailbox")
	e:SetPos(pos)
	e:SetAngles(ang)
	e:Spawn()
	return e
end

local function loadMailboxes()
	D.MailLoading = true
	for _, e in ipairs(ents.FindByClass("nyrp_mailbox")) do e:Remove() end
	local list = util.JSONToTable(file.Read(file_(), "DATA") or "") or {}
	for _, m in ipairs(list) do
		D.SpawnMailbox(Vector(m.pos[1], m.pos[2], m.pos[3]), Angle(m.ang[1], m.ang[2], m.ang[3]))
	end
	D.MailLoading = false
end
hook.Add("InitPostEntity", "nyrp.mailbox", loadMailboxes)
hook.Add("PostCleanupMap", "nyrp.mailbox", loadMailboxes)

-- есть ли у игрока ключи (в сумке или в руке)
local function hasKeys(ply)
	local inv = Inv.Get(ply)
	for _, it in pairs(inv.equip or {}) do if it.id == "keys" then return true end end
	for _, it in pairs(inv.slots or {}) do if it.id == "keys" then return true end end
	return false
end

local function boxNumber(ply)
	local id = ply.nyrpChar and ply.nyrpChar.id or 0
	return 101 + (id * 7) % 30
end

local function homes(ply)
	local out = {}
	for _, id in ipairs(D.AccessList(ply)) do
		local d = D.Data[id]
		out[#out + 1] = { name = d.name or ("Помещение №" .. id), owner = d.ownerName or "", mine = d.owner == (ply.nyrpChar and ply.nyrpChar.id) }
	end
	return out
end

function D.OpenMailbox(ply, ent)
	if not NYRP.HasCharacter(ply) or (ply.nyrpMailNext or 0) > CurTime() then return end
	ply.nyrpMailNext = CurTime() + 0.6
	ent:EmitSound("doors/door_metal_thin_open1.wav", 55, 130, 0.6)
	net.Start("nyrp.mailbox")
	net.WriteEntity(ent)
	net.WriteUInt(boxNumber(ply), 10)
	net.WriteTable(homes(ply))
	net.WriteBool(hasKeys(ply))
	net.Send(ply)
end

net.Receive("nyrp.mailbox", function(_, ply)
	if (ply.nyrpMailNext or 0) > CurTime() then return end
	ply.nyrpMailNext = CurTime() + 0.6
	local ent = net.ReadEntity()
	if not IsValid(ent) or ent:GetClass() ~= "nyrp_mailbox" or ent:GetPos():Distance(ply:GetPos()) > 160 then return end
	if #D.AccessList(ply) == 0 then NYRP.Notify(ply, "Ящик пуст: у вас нет квартиры", "warning") return end
	if hasKeys(ply) then NYRP.Notify(ply, "Ключи уже у вас", "warning") return end
	if NYRP.Inv.Add(ply, "keys", 1) <= 0 then NYRP.Notify(ply, "В сумке нет места", "error") return end
	ply:EmitSound("nyrp/fx/keys.wav", 55)
	NYRP.Notify(ply, "Вы забрали ключи. Наденьте их в слот «Холодное» и нажмите ЛКМ по двери.", "success", 7)
	D.OpenMailbox(ply, ent)
end)

local function lookPos(ply)
	local tr = ply:GetEyeTrace()
	return tr.HitPos, tr.HitNormal
end

NYRP.Chat.AddCommand("/mailbox", function(ply)
	if not ply:IsAdmin() then NYRP.Notify(ply, "Только для администрации", "error") return end
	local pos, n = lookPos(ply)
	local ang = n:Angle()
	ang.p, ang.r = 0, 0
	if math.abs(n.z) > 0.7 then ang = Angle(0, ply:EyeAngles().y + 180, 0) end
	D.SpawnMailbox(pos + n * 9.5 - Vector(0, 0, math.abs(n.z) > 0.7 and 0 or 18), ang)
	D.SaveMailboxes()
	NYRP.Notify(ply, "Почтовые ящики поставлены и сохранены", "success")
end)

NYRP.Chat.AddCommand("/mailboxremove", function(ply)
	if not ply:IsAdmin() then return end
	local e = ply:GetEyeTrace().Entity
	if IsValid(e) and e:GetClass() == "nyrp_mailbox" then
		e:Remove()
		NYRP.Notify(ply, "Почтовые ящики удалены", "success")
	end
end)

-- ключи пропадают, если доступа больше нет (выселили / аренда кончилась) — это делает сам SWEP: ключ «не подходит»
