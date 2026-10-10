--[[
	Удобство игрока (сервер):
	  • «печатает…»: клиент чата сообщает вид сообщения (nyrp.chat.typing), сервер рассылает его только тем,
	    кто в радиусе слышимости (шёпот — рядом, крик — далеко), и обновляет список слушателей каждые 0.5 с;
	  • поднятие/опускание оружия: /raise, удержание R (sh_ux), при смене оружия — снова опущено;
	  • сохранение патронов: запас по типам — в c.flags.ammo (при сохранении персонажа, выходе, смене
	    персонажа, смерти), выдаётся обратно при спавне; патроны в магазине — в данных предмета (it.data.clip);
	  • /help — справка.
	Команды: /raise (/поднять), /help (/помощь, /справка).
]]

NYRP.UX = NYRP.UX or {}
local UX = NYRP.UX
local SF = NYRP.Safety

UX.KeepAmmoOnDeath = true   -- патроны остаются после смерти (вещи в сумке тоже не теряются)

-- =============================================================== набор ==
local typing = {}   -- [ply] = { kind = n, seen = { [p] = true } }

local function sendTyping(to, ply, kind)
	net.Start("nyrp.ux.typing")
	net.WriteEntity(ply)
	net.WriteUInt(kind, 4)
	net.Send(to)
end

local function listeners(ply, kind)
	local out = {}
	local r = UX.TypingRange(kind)
	local pos = ply:GetPos()
	for _, p in pairs(player.GetAll()) do
		if p == ply or p:GetPos():DistToSqr(pos) <= r * r then out[p] = true end
	end
	return out
end

-- Обновить, кто видит значок: новым — показать, ушедшим из радиуса — скрыть.
local function refresh(ply, kindChanged)
	local st = typing[ply]
	if not st then return end
	local now = IsValid(ply) and listeners(ply, st.kind) or {}
	local add, gone = {}, {}
	for p in pairs(now) do
		if kindChanged or not st.seen[p] then add[#add + 1] = p end
	end
	for p in pairs(st.seen) do
		if IsValid(p) and not now[p] then gone[#gone + 1] = p end
	end
	if #add > 0 then sendTyping(add, ply, st.kind) end
	if #gone > 0 and IsValid(ply) then sendTyping(gone, ply, 0) end
	st.seen = now
end

function UX.SetTyping(ply, kind)
	local st = typing[ply]
	if kind == 0 then
		if not st then return end
		typing[ply] = nil
		local to = {}
		for p in pairs(st.seen) do if IsValid(p) then to[#to + 1] = p end end
		if #to > 0 and IsValid(ply) then sendTyping(to, ply, 0) end
		return
	end
	if st and st.kind == kind then return end
	if not st then
		st = { kind = kind, seen = {} }
		typing[ply] = st
		refresh(ply, false)
	else
		st.kind = kind
		refresh(ply, true)
	end
end

local VALID = {}
local function validKinds()
	if next(VALID) then return VALID end
	local T = NYRP.Chat.Types
	for _, k in ipairs({ T.IC, T.WHISPER, T.YELL, T.ME, T.IT, T.OOC, T.LOOC }) do VALID[k] = true end
	return VALID
end

-- Заменяет приёмник из modules/chat/sv_chat.lua (модуль ux грузится позже): та же сеть от клиента,
-- но вместо NW2-переменной (видна всем в PVS) — адресная рассылка в радиусе слышимости.
net.Receive("nyrp.chat.typing", function(_, ply)
	local k = net.ReadUInt(4)
	if k ~= 0 then
		if (ply.nyrpTypingNext or 0) > CurTime() then return end
		ply.nyrpTypingNext = CurTime() + 0.15
		if not validKinds()[k] or not NYRP.HasCharacter(ply) or not ply:Alive() then k = 0 end
	end
	ply:SetNW2Int("nyrp.typing", 0)
	UX.SetTyping(ply, k)
end)

timer.Create("nyrp.ux.typing", 0.5, 0, function()
	for ply in pairs(typing) do
		if not IsValid(ply) then
			typing[ply] = nil
		elseif not ply:Alive() then
			UX.SetTyping(ply, 0)
		else
			refresh(ply, false)
		end
	end
end)

hook.Add("NYRP.ChatMessage", "nyrp.ux.typing", function(ply) UX.SetTyping(ply, 0) end)
hook.Add("PlayerDeath", "nyrp.ux.typing", function(ply) UX.SetTyping(ply, 0) end)
hook.Add("PlayerDisconnected", "nyrp.ux.typing", function(ply)
	UX.SetTyping(ply, 0)
	for _, st in pairs(typing) do st.seen[ply] = nil end
end)

-- ============================================================= оружие ==
function SF.Set(ply, raised)
	if SF.Raised(ply) == raised then return end
	ply:SetNW2Bool("nyrp.wepRaised", raised)
	ply:SetNW2Float("nyrp.wepRaiseT", CurTime())
	local wep = ply:GetActiveWeapon()
	if raised then
		ply:EmitSound("nyrp/fx/weapon_draw.wav", 52, math.random(108, 116), 0.55)
	else
		ply:EmitSound("nyrp/fx/cloth.wav", 48, math.random(95, 105), 0.6)
	end
	hook.Run("NYRP.WeaponRaised", ply, raised, wep)
end

function SF.Toggle(ply)
	if not ply:Alive() then return end
	local wep = ply:GetActiveWeapon()
	if not SF.Applies(wep) then
		NYRP.Notify(ply, "В руках нет оружия", "warning", 2)
		return
	end
	SF.Set(ply, not SF.Raised(ply))
end

local function raiseCmd(ply)
	if (ply.nyrpRaiseCmd or 0) > CurTime() then return end
	ply.nyrpRaiseCmd = CurTime() + 0.5
	SF.Toggle(ply)
end
NYRP.Chat.AddCommand("/raise", raiseCmd)
NYRP.Chat.AddCommand("/поднять", raiseCmd)
NYRP.Chat.AddCommand("/toggleraise", raiseCmd)
-- удержание R (клиент) и бинд: bind <клавиша> nyrp_raise
concommand.Add("nyrp_raise", function(ply) if IsValid(ply) then raiseCmd(ply) end end)

-- Взял другое оружие — оно опущено.
hook.Add("PlayerSwitchWeapon", "nyrp.safety", function(ply, old, new)
	if old ~= new and SF.Raised(ply) then
		timer.Simple(0, function()
			if IsValid(ply) and ply:GetActiveWeapon() ~= old then SF.Set(ply, false) end
		end)
	end
end)
hook.Add("PlayerSpawn", "nyrp.safety", function(ply) ply:SetNW2Bool("nyrp.wepRaised", false) end)
hook.Add("PlayerDeath", "nyrp.safety", function(ply) ply:SetNW2Bool("nyrp.wepRaised", false) end)

-- ============================================================ патроны ==
-- Предмет, из которого выдано оружие: ищем в снаряжении по классу.
local function itemFor(ply, wep)
	if not NYRP.Inv or not NYRP.Items then return end
	local inv = NYRP.Inv.Get(ply)
	for _, it in pairs(inv.equip or {}) do
		local def = NYRP.Items.Get(it.id)
		if def and def.class == wep:GetClass() then return it end
	end
end

local function storeClip(wep)
	local it = wep.nyrpItem
	if not it or not wep.Clip1 then return end
	local clip = wep:Clip1()
	if clip and clip >= 0 then
		it.data = it.data or {}
		it.data.clip = clip
	end
end

-- Выдали оружие из предмета — возвращаем патроны в магазин.
hook.Add("WeaponEquip", "nyrp.ux.clip", function(wep, ply)
	timer.Simple(0, function()
		if not IsValid(wep) or not IsValid(ply) or wep:GetOwner() ~= ply then return end
		local it = itemFor(ply, wep)
		if not it then return end
		wep.nyrpItem = it
		local clip = it.data and tonumber(it.data.clip)
		if clip and wep:GetMaxClip1() > 0 then
			wep:SetClip1(math.Clamp(math.floor(clip), 0, wep:GetMaxClip1()))
		end
	end)
end)

-- Оружие убрали / выбросили / забрали при смерти — запоминаем, сколько было в магазине.
hook.Add("EntityRemoved", "nyrp.ux.clip", function(ent)
	if ent.nyrpItem then storeClip(ent) end
end)

local function storeClips(ply)
	for _, w in pairs(ply:GetWeapons()) do
		if w.nyrpItem then storeClip(w) end
	end
end

timer.Create("nyrp.ux.clips", 0.5, 0, function()
	for _, ply in pairs(player.GetAll()) do
		if ply:Alive() then storeClips(ply) end
	end
end)

-- Запас патронов по типам -> c.flags.ammo. Только когда патроны в руках — этого персонажа.
function UX.SnapshotAmmo(ply, dead)
	local c = ply.nyrpChar
	if not c or ply.nyrpAmmoChar ~= c.id or ply.nyrpInvChar ~= c.id then return end
	if not dead and not ply:Alive() then return end
	storeClips(ply)
	local t = {}
	for id, n in pairs(ply:GetAmmo() or {}) do
		local name = game.GetAmmoName(id)
		if name and n > 0 then t[name] = math.floor(n) end
	end
	c.flags = c.flags or {}
	c.flags.ammo = next(t) and t or nil
end

-- Перед каждым сохранением персонажа (автосохранение, выход, смена персонажа, выход в меню)
-- снимаем патроны. Оборачиваем NYRP.Chars.Save, не правя модуль персонажей.
local function wrapSave()
	local Chars = NYRP.Chars
	if not Chars or not Chars.Save or Chars.Save == UX.SaveWrapper then return end
	local orig = Chars.Save
	UX.SaveWrapper = function(ply, ...)
		if IsValid(ply) then ProtectedCall(function() UX.SnapshotAmmo(ply) end) end
		return orig(ply, ...)
	end
	Chars.Save = UX.SaveWrapper
end
hook.Add("Initialize", "nyrp.ux.ammo", function(...) wrapSave(...) end)
hook.Add("InitPostEntity", "nyrp.ux.ammo", function(...) wrapSave(...) end)
wrapSave()

hook.Add("DoPlayerDeath", "nyrp.ux.ammo", function(ply)
	if UX.KeepAmmoOnDeath then
		UX.SnapshotAmmo(ply, true)
	elseif ply.nyrpChar and ply.nyrpChar.flags then
		ply.nyrpChar.flags.ammo = nil
	end
end)

-- Спавн (хук идёт до GM:PlayerSpawn, т.е. до выдачи оружия): ставим запас этого персонажа.
hook.Add("PlayerSpawn", "nyrp.ux.ammo", function(ply)
	local c = ply.nyrpChar
	if not c or not NYRP.HasCharacter(ply) then ply.nyrpAmmoChar = nil return end
	ply:RemoveAllAmmo()
	local saved = c.flags and c.flags.ammo
	if type(saved) == "table" then
		for name, n in pairs(saved) do
			n = tonumber(n)
			if n and n > 0 and game.GetAmmoID(name) >= 0 then ply:SetAmmo(math.min(math.floor(n), 9999), name) end
		end
	end
	ply.nyrpAmmoChar = c.id
end)

-- ============================================================ справка ==
local function helpCmd(ply)
	if (ply.nyrpHelpNext or 0) > CurTime() then return end
	ply.nyrpHelpNext = CurTime() + 1
	net.Start("nyrp.ux.help")
	net.Send(ply)
end
NYRP.Chat.AddCommand("/help", helpCmd)
NYRP.Chat.AddCommand("/помощь", helpCmd)
NYRP.Chat.AddCommand("/справка", helpCmd)
