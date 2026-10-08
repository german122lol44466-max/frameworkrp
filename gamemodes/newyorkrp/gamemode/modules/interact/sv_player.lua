--[[
	Взаимодействие с другим игроком (круговое меню по E): познакомиться, передать деньги
	(nyrp.money.give), показать удостоверение.
]]

local function near(ply, target)
	return IsValid(target) and target:IsPlayer() and target ~= ply and target:Alive() and NYRP.HasCharacter(target)
		and ply:Alive() and ply:GetPos():Distance(target:GetPos()) <= 150
end

-- Показать своё удостоверение конкретному человеку.
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
	if not card then NYRP.Notify(ply, "У вас нет удостоверения", "warning") return end
	net.Start("nyrp.inv.view")
	net.WriteEntity(ply)
	net.WriteTable(card.data)
	net.Send(target)
	net.Start("nyrp.inv.anim") net.WriteEntity(ply) net.WriteUInt(ACT_GMOD_GESTURE_ITEM_GIVE, 16) net.SendPVS(ply:GetPos())
	if card.data.char == own and NYRP.Recog then NYRP.Recog.Add(target, ply) end
	NYRP.Notify(ply, "Вы показали удостоверение", "success")
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
