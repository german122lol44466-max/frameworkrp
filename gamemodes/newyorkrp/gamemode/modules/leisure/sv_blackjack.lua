--[[
	Блэкджек на сервере. У каждого игрока за столом — своя раздача против дилера (до 4 мест на стол).
	  Ставка $5–$500 наличными списывается сразу. «Ещё» — карта, «Хватит» — ход дилера,
	  «Удвоить» — только на первых двух картах: ставка ×2, одна карта и ход дилера.
	  Дилер добирает до 17 (на мягких 17 стоит). Блэкджек с двух карт — 3:2, ничья — ставка возвращается.
	  Отошли от стола, умерли, сменили персонажа или вышли посреди раздачи — ставка сгорает.
	Колода — новый «башмак» из 4 колод на каждую раздачу; клиенту не уходит ни одна неоткрытая карта.
]]

NYRP.Leisure = NYRP.Leisure or {}
local LS = NYRP.Leisure
LS.BJ = LS.BJ or {}
local BJ = LS.BJ

BJ.Sessions = BJ.Sessions or {}   -- [ply] = { ent, seat, phase, bet, lastBet, shoe, player, dealer, result, payout, msg }

local function seatsOf(ent)
	local used = {}
	for p, s in pairs(BJ.Sessions) do
		if IsValid(p) and s.ent == ent then used[s.seat] = p end
	end
	return used
end

-- надпись места над столом (без имён — незнакомцев не выдаём)
local function updateSeat(s)
	if not IsValid(s.ent) then return end
	local text = "занято"
	if s.phase == "play" then
		text = "в игре · " .. NYRP.Money.Format(s.bet)
	elseif s.phase == "done" and s.result ~= "" then
		local names = { win = "выигрыш", bj = "блэкджек!", push = "ничья", lose = "проигрыш", bust = "перебор" }
		text = names[s.result] or "ждёт ставку"
	elseif s.phase == "bet" then
		text = "делает ставку"
	end
	s.ent:SetNW2String("nyrp.bj.s" .. s.seat, text)
end

local function newShoe()
	local shoe = {}
	for _ = 1, BJ.Decks do
		for c = 1, 52 do shoe[#shoe + 1] = c end
	end
	for i = #shoe, 2, -1 do
		local j = math.random(i)
		shoe[i], shoe[j] = shoe[j], shoe[i]
	end
	return shoe
end

local function drawCard(s)
	if #s.shoe == 0 then s.shoe = newShoe() end
	return table.remove(s.shoe)
end

local function send(ply)
	local s = BJ.Sessions[ply]
	if not s then return end
	net.Start("nyrp.bj.state")
	net.WriteEntity(s.ent)
	net.WriteUInt(s.seat, 3)
	net.WriteUInt(s.hand or 0, 16)
	net.WriteString(s.phase)
	net.WriteUInt(s.bet, 16)
	net.WriteUInt(s.lastBet or BJ.MinBet, 16)
	net.WriteUInt(#s.player, 5)
	for _, c in ipairs(s.player) do net.WriteUInt(c, 6) end
	local hide = s.phase == "play"
	net.WriteUInt(#s.dealer, 5)
	for i, c in ipairs(s.dealer) do net.WriteUInt((hide and i == 2) and 0 or c, 6) end
	net.WriteString(s.result or "")
	net.WriteUInt(s.payout or 0, 16)
	net.WriteString(s.msg or "")
	net.Send(ply)
	updateSeat(s)
end

-- завершить раздачу: выплата и запись итога
local function settle(ply, s, result, payout, msg)
	s.phase = "done"
	s.result = result
	s.payout = payout
	s.msg = msg
	if payout > 0 then NYRP.Money.Add(ply, payout) end
	local gain = payout - s.bet
	if IsValid(s.ent) then
		if result == "bj" or result == "win" then
			s.ent:EmitSound("ambient/levels/labs/coinslot1.wav", 60, 100)
		end
	end
	if gain > 0 then
		NYRP.Notify(ply, "Блэкджек: выигрыш +" .. NYRP.Money.Format(gain), "success", 4)
	elseif result == "push" then
		NYRP.Notify(ply, "Блэкджек: ничья, ставка возвращена", "info", 3)
	end
	if result == "bj" and NYRP.Ach and NYRP.Ach.Add then NYRP.Ach.Add(ply, "bjNatural", 1) end
	hook.Run("NYRP.BlackjackRound", ply, s.bet, payout, result)
	send(ply)
end

-- ход дилера и сравнение
local function dealerPlay(ply, s)
	local pv = BJ.Value(s.player)
	while true do
		local dv = BJ.Value(s.dealer)
		if dv >= 17 then break end
		s.dealer[#s.dealer + 1] = drawCard(s)
	end
	local dv = BJ.Value(s.dealer)
	if dv > 21 then
		settle(ply, s, "win", s.bet * 2, "У дилера перебор (" .. dv .. ")")
	elseif pv > dv then
		settle(ply, s, "win", s.bet * 2, pv .. " против " .. dv .. " — вы выиграли")
	elseif pv == dv then
		settle(ply, s, "push", s.bet, "Ничья: " .. pv .. " — " .. dv)
	else
		settle(ply, s, "lose", 0, "У дилера " .. dv .. " против ваших " .. pv)
	end
end

local function deal(ply, s, bet)
	s.shoe = newShoe()
	s.hand = ((s.hand or 0) + 1) % 65536
	s.bet = bet
	s.lastBet = bet
	s.player, s.dealer = {}, {}
	s.result, s.payout, s.msg = "", 0, ""
	s.player[1] = drawCard(s)
	s.dealer[1] = drawCard(s)
	s.player[2] = drawCard(s)
	s.dealer[2] = drawCard(s)
	s.phase = "play"
	if IsValid(s.ent) then s.ent:EmitSound("physics/cardboard/cardboard_box_impact_soft1.wav", 55, 160) end
	local pbj, dbj = BJ.IsBlackjack(s.player), BJ.IsBlackjack(s.dealer)
	if pbj and dbj then
		settle(ply, s, "push", bet, "Блэкджек у обоих — ничья")
	elseif pbj then
		settle(ply, s, "bj", bet + math.floor(bet * 1.5), "БЛЭКДЖЕК! Выплата 3:2")
	elseif dbj then
		settle(ply, s, "lose", 0, "У дилера блэкджек")
	else
		s.msg = "Ваш ход"
		send(ply)
	end
end

function BJ.Leave(ply, why)
	local s = BJ.Sessions[ply]
	if not s then return end
	BJ.Sessions[ply] = nil
	if IsValid(s.ent) then s.ent:SetNW2String("nyrp.bj.s" .. s.seat, "") end
	if IsValid(ply) then
		if s.phase == "play" and s.bet > 0 then
			NYRP.Notify(ply, "Вы ушли посреди раздачи — ставка " .. NYRP.Money.Format(s.bet) .. " сгорела", "warning", 5)
		elseif why then
			NYRP.Notify(ply, why, "info", 3)
		end
		net.Start("nyrp.bj.close")
		net.Send(ply)
	end
end

-- E по столу
function BJ.Use(ent, ply)
	if (ply.nyrpBjUse or 0) > CurTime() then return end
	ply.nyrpBjUse = CurTime() + 0.8
	local s = BJ.Sessions[ply]
	if s and s.ent == ent then send(ply) return end
	if s then BJ.Leave(ply) end
	local used = seatsOf(ent)
	local seat
	for i = 1, BJ.Seats do
		if not used[i] then seat = i break end
	end
	if not seat then NYRP.Notify(ply, "Все " .. BJ.Seats .. " места за столом заняты", "warning") return end
	BJ.Sessions[ply] = { ent = ent, seat = seat, phase = "bet", bet = 0, lastBet = math.Clamp(ply.nyrpBjLast or 25, BJ.MinBet, BJ.MaxBet),
		shoe = {}, player = {}, dealer = {}, result = "", payout = 0, msg = "Сделайте ставку" }
	ent:EmitSound("physics/cardboard/cardboard_box_impact_soft2.wav", 50, 120)
	send(ply)
end

net.Receive("nyrp.bj.act", function(_, ply)
	if (ply.nyrpBjNext or 0) > CurTime() then return end
	ply.nyrpBjNext = CurTime() + 0.35
	local act = net.ReadString()
	local amount = net.ReadUInt(16)
	local s = BJ.Sessions[ply]
	if not s then return end
	if act == "leave" then BJ.Leave(ply, "Вы встали из-за стола") return end
	if not IsValid(s.ent) or not NYRP.HasCharacter(ply) or not ply:Alive()
		or s.ent:GetPos():Distance(ply:GetPos()) > BJ.Range then
		BJ.Leave(ply)
		return
	end
	if act == "bet" then
		if s.phase == "play" then return end
		local bet = math.floor(amount)
		if bet < BJ.MinBet or bet > BJ.MaxBet then
			NYRP.Notify(ply, "Ставка — от " .. NYRP.Money.Format(BJ.MinBet) .. " до " .. NYRP.Money.Format(BJ.MaxBet), "warning")
			return
		end
		if NYRP.Money.Get(ply) < bet then NYRP.Notify(ply, "Не хватает наличных", "error") return end
		NYRP.Money.Add(ply, -bet)
		ply.nyrpBjLast = bet
		deal(ply, s, bet)
	elseif act == "hit" then
		if s.phase ~= "play" then return end
		s.player[#s.player + 1] = drawCard(s)
		s.ent:EmitSound("physics/cardboard/cardboard_box_impact_soft1.wav", 50, 170)
		local v = BJ.Value(s.player)
		if v > 21 then
			settle(ply, s, "bust", 0, "Перебор: " .. v)
		elseif v == 21 then
			dealerPlay(ply, s)
		else
			s.msg = "У вас " .. v
			send(ply)
		end
	elseif act == "stand" then
		if s.phase ~= "play" then return end
		dealerPlay(ply, s)
	elseif act == "double" then
		if s.phase ~= "play" or #s.player ~= 2 then return end
		if NYRP.Money.Get(ply) < s.bet then NYRP.Notify(ply, "Для удвоения нужно ещё " .. NYRP.Money.Format(s.bet), "error") return end
		NYRP.Money.Add(ply, -s.bet)
		s.bet = s.bet * 2
		s.player[#s.player + 1] = drawCard(s)
		s.ent:EmitSound("ambient/levels/labs/coinslot1.wav", 50, 120)
		local v = BJ.Value(s.player)
		if v > 21 then
			settle(ply, s, "bust", 0, "Удвоение и перебор: " .. v)
		else
			dealerPlay(ply, s)
		end
	end
end)

-- отошёл, умер, нет персонажа, стол убрали
timer.Create("nyrp.bj.watch", 1, 0, function()
	for p, s in pairs(BJ.Sessions) do
		if not IsValid(p) then
			BJ.Sessions[p] = nil
			if IsValid(s.ent) then s.ent:SetNW2String("nyrp.bj.s" .. s.seat, "") end
		elseif not IsValid(s.ent) then
			BJ.Leave(p, "Стол убрали")
		elseif not p:Alive() or not NYRP.HasCharacter(p) or s.ent:GetPos():Distance(p:GetPos()) > BJ.Range then
			BJ.Leave(p, "Вы отошли от стола")
		end
	end
end)

hook.Add("PlayerDisconnected", "nyrp.bj", function(ply)
	local s = BJ.Sessions[ply]
	if not s then return end
	BJ.Sessions[ply] = nil
	if IsValid(s.ent) then s.ent:SetNW2String("nyrp.bj.s" .. s.seat, "") end
end)
hook.Add("NYRP.CharacterLoaded", "nyrp.bj", function(ply) BJ.Leave(ply) end)
