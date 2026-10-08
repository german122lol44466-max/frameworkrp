--[[
	Взаимодействие с другим игроком (круговое меню по E): познакомиться, передать деньги
	(nyrp.money.give), показать удостоверение.
]]

local function near(ply, target)
	return IsValid(target) and target:IsPlayer() and target ~= ply and target:Alive() and NYRP.HasCharacter(target)
		and ply:Alive() and ply:GetPos():Distance(target:GetPos()) <= 150
end

-- Показ удостоверения: сначала спрашиваем человека, хочет ли он смотреть (Y — да, N — нет).
local function sendCard(ply, target, card)
	net.Start("nyrp.inv.view")
	net.WriteEntity(ply)
	net.WriteTable(card.data)
	net.Send(target)
	net.Start("nyrp.inv.anim") net.WriteEntity(ply) net.WriteUInt(ACT_GMOD_GESTURE_ITEM_GIVE, 16) net.SendPVS(ply:GetPos())
	if card.data.char == (ply.nyrpChar and ply.nyrpChar.id) and NYRP.Recog then NYRP.Recog.Add(target, ply) end
end

function NYRP.OfferID(ply, target, card)
	if not card then NYRP.Notify(ply, "У вас нет удостоверения", "warning") return end
	target.nyrpIdOffers = target.nyrpIdOffers or {}
	target.nyrpIdOffers[ply] = { card = card, till = CurTime() + 15 }
	net.Start("nyrp.id.request")
	net.WriteEntity(ply)
	net.Send(target)
	NYRP.Notify(ply, "Вы протягиваете удостоверение — ждём, посмотрит ли человек", "info", 4)
end

net.Receive("nyrp.id.answer", function(_, target)
	local ply, yes = net.ReadEntity(), net.ReadBool()
	local offer = target.nyrpIdOffers and target.nyrpIdOffers[ply]
	if not offer or not IsValid(ply) then return end
	target.nyrpIdOffers[ply] = nil
	if offer.till < CurTime() then return end
	if yes then
		if ply:GetPos():Distance(target:GetPos()) > 170 then NYRP.Notify(target, "Человек уже отошёл", "warning") return end
		sendCard(ply, target, offer.card)
		NYRP.Notify(ply, "Человек посмотрел ваше удостоверение", "success")
	else
		NYRP.Notify(ply, "Человек отказался смотреть удостоверение", "warning")
	end
end)

local function showID(ply, target)
	local inv = NYRP.Inv.Get(ply)
	local own = ply.nyrpChar and ply.nyrpChar.id
	local card
	for _, it in pairs(inv.slots) do
		if it.id == "idcard" and it.data.char == own then card = it break end
	end
	if not card then
		for _, it in pairs(inv.slots) do if it.id == "idcard" then card = it break end end
	end
	NYRP.OfferID(ply, target, card)
end

net.Receive("nyrp.player.act", function(_, ply)
	if (ply.nyrpActNext or 0) > CurTime() then return end
	ply.nyrpActNext = CurTime() + 0.8
	local act, target = net.ReadString(), net.ReadEntity()
	if not near(ply, target) then NYRP.Notify(ply, "Подойдите ближе к человеку", "warning") return end
	if act == "introduce" then
		NYRP.Recog.Add(target, ply)
		net.Start("nyrp.inv.anim") net.WriteEntity(ply) net.WriteUInt(ACT_GMOD_GESTURE_WAVE, 16) net.SendPVS(ply:GetPos())
		NYRP.Notify(ply, "Вы представились", "success")
	elseif act == "showid" then
		showID(ply, target)
	end
end)
