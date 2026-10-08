--[[
	Деньги на сервере: загрузка/сохранение вместе с персонажем, передача другому игроку.
]]

local M = NYRP.Money

function M.Set(ply, n)
	n = math.max(0, math.floor(n))
	ply:SetNW2Int("nyrp.money", n)
	local c = ply.nyrpChar
	if c then
		c.flags = c.flags or {}
		c.flags.money = n
		if NYRP.Chars.Save then NYRP.Chars.Save(ply) end
	end
end

function M.Add(ply, n) M.Set(ply, M.Get(ply) + n) end

hook.Add("NYRP.CharacterLoaded", "nyrp.money", function(ply, c)
	c.flags = c.flags or {}
	if c.flags.money == nil then c.flags.money = NYRP.Config.StartMoney end
	ply:SetNW2Int("nyrp.money", c.flags.money)
end)

-- Передать деньги человеку рядом.
function M.Give(ply, target, amount)
	amount = math.floor(tonumber(amount) or 0)
	if not IsValid(target) or not target:IsPlayer() or target == ply or not NYRP.HasCharacter(target) then return end
	if not ply:Alive() or not target:Alive() or ply:GetPos():Distance(target:GetPos()) > 150 then
		NYRP.Notify(ply, "Подойдите ближе к человеку", "warning")
		return
	end
	if amount <= 0 then return end
	if M.Get(ply) < amount then NYRP.Notify(ply, "У вас нет такой суммы", "error") return end
	M.Set(ply, M.Get(ply) - amount)
	M.Add(target, amount)
	ply:AnimRestartGesture(GESTURE_SLOT_CUSTOM, ACT_GMOD_GESTURE_ITEM_GIVE, true)
	net.Start("nyrp.inv.anim") net.WriteEntity(ply) net.WriteUInt(ACT_GMOD_GESTURE_ITEM_GIVE, 16) net.SendPVS(ply:GetPos())
	ply:EmitSound("physics/cardboard/cardboard_box_impact_soft" .. math.random(1, 3) .. ".wav", 55)
	NYRP.Notify(ply, "Вы передали " .. M.Format(amount), "success")
	NYRP.Notify(target, "Вам передали " .. M.Format(amount), "success")
end

net.Receive("nyrp.money.give", function(_, ply)
	if (ply.nyrpMoneyNext or 0) > CurTime() then return end
	ply.nyrpMoneyNext = CurTime() + 1
	M.Give(ply, net.ReadEntity(), net.ReadUInt(32))
end)

concommand.Add("nyrp_givemoney", function(ply, _, args)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	if IsValid(ply) then M.Add(ply, tonumber(args[1]) or 100) end
end)
