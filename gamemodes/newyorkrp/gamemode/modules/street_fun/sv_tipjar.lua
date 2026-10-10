--[[
	Шляпа для чаевых (сервер). Одна на игрока. Прохожие дают $1–1000 (не чаще раза в 2 с),
	владелец забирает шляпу с деньгами (E). Владелец вышел или ушёл дальше ~30 м на 5 минут —
	шляпа исчезает (если он в игре — деньги и шляпа возвращаются ему).
]]

NYRP.StreetFun = NYRP.StreetFun or {}
local SF = NYRP.StreetFun

local FAR = 1500
local FAR_TIME = 300

local function jarOf(ply)
	for _, e in ipairs(ents.FindByClass("nyrp_tipjar")) do
		if e.nyrpOwner == ply then return e end
	end
end

function SF.PlaceTipJar(ply)
	if IsValid(jarOf(ply)) then NYRP.Notify(ply, "Ваша шляпа уже стоит на улице", "warning") return false end
	local start = ply:GetPos() + Vector(0, 0, 30) + ply:GetForward() * 40
	local tr = util.TraceLine({ start = start, endpos = start - Vector(0, 0, 120), filter = ply })
	if not tr.Hit or tr.HitNormal.z < 0.7 then NYRP.Notify(ply, "Поставьте на ровную землю", "warning") return false end
	local e = ents.Create("nyrp_tipjar")
	if not IsValid(e) then return false end
	e:SetPos(tr.HitPos + Vector(0, 0, 6))
	e:SetAngles(Angle(0, ply:EyeAngles().y, 0))
	e:Spawn()
	e.nyrpOwner = ply
	e:SetJarOwner(ply)
	ply:AnimRestartGesture(GESTURE_SLOT_CUSTOM, ACT_GMOD_GESTURE_ITEM_PLACE, true)
	NYRP.Notify(ply, "Шляпа стоит. Играйте — прохожие бросят монетку. Забрать — E.", "success", 6)
	return true
end

local function collect(e, ply, silent)
	if e.nyrpTaken then return end
	e.nyrpTaken = true
	local n = e:GetAmount()
	if n > 0 then NYRP.Money.Add(ply, n) end
	if NYRP.Inv.Add(ply, "tipjar", 1) <= 0 then NYRP.Inv.DropNew(ply, "tipjar", 1) end
	ply:EmitSound("nyrp/fx/money.wav", 55)
	NYRP.Notify(ply, (silent and "Шляпа вернулась к вам" or "Вы забрали шляпу") .. (n > 0 and (": " .. NYRP.Money.Format(n)) or ""), "success", 5)
	e:Remove()
end

function SF.TipJarUse(e, ply)
	if e.nyrpOwner == ply then collect(e, ply) return end
	if (ply.nyrpTipNext or 0) > CurTime() then return end
	net.Start("nyrp.tip.open")
	net.WriteEntity(e)
	net.Send(ply)
end

net.Receive("nyrp.tip.give", function(_, ply)
	if (ply.nyrpTipNext or 0) > CurTime() then return end
	ply.nyrpTipNext = CurTime() + 2
	local e, n = net.ReadEntity(), net.ReadUInt(16)
	if not IsValid(e) or e:GetClass() ~= "nyrp_tipjar" or e.nyrpTaken or e.nyrpOwner == ply then return end
	if not NYRP.HasCharacter(ply) or not ply:Alive() or e:GetPos():Distance(ply:GetPos()) > 160 then return end
	n = math.floor(n)
	if n < 1 or n > 1000 then return end
	if NYRP.Money.Get(ply) < n then NYRP.Notify(ply, "Не хватает наличных", "error") return end
	NYRP.Money.Add(ply, -n)
	e:SetAmount(e:GetAmount() + n)
	e:EmitSound("nyrp/fx/money.wav", 55, 120)
	ply:AnimRestartGesture(GESTURE_SLOT_CUSTOM, ACT_GMOD_GESTURE_ITEM_GIVE, true)
	NYRP.Notify(ply, "Вы оставили чаевые: " .. NYRP.Money.Format(n), "success", 3)
	local owner = e.nyrpOwner
	if IsValid(owner) then NYRP.Notify(owner, "Вам бросили чаевые: +" .. NYRP.Money.Format(n), "item", 4) end
end)

timer.Create("nyrp.tipjar", 10, 0, function()
	for _, e in ipairs(ents.FindByClass("nyrp_tipjar")) do
		local o = e.nyrpOwner
		if IsValid(o) and o:GetPos():Distance(e:GetPos()) <= FAR then
			e.nyrpFarSince = nil
		else
			e.nyrpFarSince = e.nyrpFarSince or CurTime()
			if CurTime() - e.nyrpFarSince > FAR_TIME then
				if IsValid(o) and NYRP.HasCharacter(o) then collect(e, o, true) else e:Remove() end
			end
		end
	end
end)
