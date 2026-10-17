--[[
	Бумбокс на сервере. Предмет «Бумбокс» (ПКМ «Поставить») — энтити nyrp_boombox, один на игрока.
	  E владельца — меню: станция, громкость, выключить, забрать; E остальных — что играет и личные настройки звука.
	  Станция и громкость хранятся в самом энтити (NetworkVar) — каждый клиент сам играет поток рядом с бумбоксом.
	  Владелец ушёл дальше ~30 м на 5 минут — бумбокс возвращается в сумку; вышел или сменил персонажа —
	  бумбокс остаётся на месте предметом.
]]

NYRP.Leisure = NYRP.Leisure or {}
local LS = NYRP.Leisure
LS.Boombox = LS.Boombox or {}
local BB = LS.Boombox

local function boxOf(ply)
	for _, e in ipairs(ents.FindByClass("nyrp_boombox")) do
		if e.nyrpOwner == ply then return e end
	end
end

function BB.Place(ply)
	if not IsValid(ply) or not NYRP.HasCharacter(ply) or not ply:Alive() then return false end
	if IsValid(boxOf(ply)) then NYRP.Notify(ply, "Ваш бумбокс уже стоит рядом — заберите его через меню (E)", "warning") return false end
	local start = ply:GetPos() + Vector(0, 0, 30) + ply:GetForward() * 40
	local tr = util.TraceLine({ start = start, endpos = start - Vector(0, 0, 120), filter = ply })
	if not tr.Hit or tr.HitNormal.z < 0.7 then NYRP.Notify(ply, "Поставьте на ровную поверхность", "warning") return false end
	local e = ents.Create("nyrp_boombox")
	if not IsValid(e) then return false end
	e:SetPos(tr.HitPos + Vector(0, 0, 10))
	e:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))
	e:Spawn()
	e.nyrpOwner = ply
	e.nyrpOwnerChar = ply.nyrpChar and ply.nyrpChar.id
	e:SetBoxOwner(ply)
	e:SetBoxVolume(70)
	ply:AnimRestartGesture(GESTURE_SLOT_CUSTOM, ACT_GMOD_GESTURE_ITEM_PLACE, true)
	NYRP.Notify(ply, "Бумбокс стоит. E — выбрать радиостанцию.", "success", 5)
	return true
end

-- вернуть бумбокс владельцу в сумку (или под ноги)
local function collect(e, ply, silent)
	if e.nyrpTaken then return end
	e.nyrpTaken = true
	if NYRP.Inv.Add(ply, "boombox", 1) <= 0 then NYRP.Inv.DropNew(ply, "boombox", 1) end
	ply:EmitSound("nyrp/fx/cloth.wav", 55)
	NYRP.Notify(ply, silent and "Бумбокс вернулся к вам в сумку" or "Вы забрали бумбокс", "success", 4)
	e:Remove()
end

-- владелец пропал — бумбокс остаётся на месте обычным предметом
local function toItem(e)
	if e.nyrpTaken then return end
	e.nyrpTaken = true
	local it = ents.Create("nyrp_item")
	if IsValid(it) and it.SetItem then
		it:SetItem("boombox", 1)
		it:SetPos(e:GetPos() + Vector(0, 0, 8))
		it:Spawn()
	elseif IsValid(it) then
		it:Remove()
	end
	e:Remove()
end

function BB.Use(e, ply)
	if (ply.nyrpBbUse or 0) > CurTime() then return end
	ply.nyrpBbUse = CurTime() + 0.6
	net.Start("nyrp.bb.open")
	net.WriteEntity(e)
	net.WriteBool(e.nyrpOwner == ply)
	net.Send(ply)
end

net.Receive("nyrp.bb.act", function(_, ply)
	if (ply.nyrpBbNext or 0) > CurTime() then return end
	ply.nyrpBbNext = CurTime() + 0.25
	local e = net.ReadEntity()
	local act = net.ReadString()
	local val = net.ReadUInt(8)
	if not IsValid(e) or e:GetClass() ~= "nyrp_boombox" or e.nyrpTaken or e.nyrpOwner ~= ply then return end
	if not NYRP.HasCharacter(ply) or not ply:Alive() or e:GetPos():Distance(ply:GetPos()) > 220 then
		NYRP.Notify(ply, "Подойдите к бумбоксу", "warning")
		return
	end
	if act == "station" then
		if val < 1 or val > #BB.Stations then return end
		e:SetBoxStation(val)
		e:EmitSound("buttons/lightswitch2.wav", 50, 110)
	elseif act == "volume" then
		e:SetBoxVolume(math.Clamp(val, 0, 100))
	elseif act == "off" then
		e:SetBoxStation(0)
		e:EmitSound("buttons/lightswitch2.wav", 50, 90)
	elseif act == "take" then
		collect(e, ply)
	end
end)

timer.Create("nyrp.boombox", 10, 0, function()
	for _, e in ipairs(ents.FindByClass("nyrp_boombox")) do
		local o = e.nyrpOwner
		if not IsValid(o) or not o.nyrpChar or o.nyrpChar.id ~= e.nyrpOwnerChar then
			toItem(e)
		elseif o:GetPos():Distance(e:GetPos()) <= BB.FarOwner then
			e.nyrpFarSince = nil
		else
			e.nyrpFarSince = e.nyrpFarSince or CurTime()
			if CurTime() - e.nyrpFarSince > BB.FarTime then collect(e, o, true) end
		end
	end
end)

hook.Add("PlayerDisconnected", "nyrp.boombox", function(ply)
	local e = boxOf(ply)
	if IsValid(e) then toItem(e) end
end)
