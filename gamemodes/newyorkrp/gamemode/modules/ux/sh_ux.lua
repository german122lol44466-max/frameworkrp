--[[
	Удобство игрока (общая часть):
	  • индикатор набора «печатает…» над головой — сеть и дальность слышимости (sv_ux / cl_typing);
	  • поднятое/опущенное оружие (safety): огнестрельное и холодное оружие из предметов (папка weapons)
	    по умолчанию опущено — стрелять нельзя, поза «руки вниз». Поднять/опустить: держать R 0.4 с или /raise;
	  • сохранение патронов персонажа и патронов в магазине оружия (sv_ux);
	  • счётчик патронов (cl_ammo), экран потери связи (cl_connection), справка /help (cl_help).
]]

NYRP.UX = NYRP.UX or {}
local UX = NYRP.UX

if SERVER then
	util.AddNetworkString("nyrp.ux.typing")
	util.AddNetworkString("nyrp.ux.help")
end

-- ---------------------------------------------------------------- набор --
-- На каком расстоянии видно «печатает…» (по виду сообщения). OOC — глобальный чат,
-- но значок над головой видят только те, кто стоит рядом (как обычную речь).
function UX.TypingRange(kind)
	local T = NYRP.Chat and NYRP.Chat.Types
	local R = NYRP.Config.Ranges
	if not T then return R.Say end
	if kind == T.WHISPER then return math.max(R.Whisper, 140) end
	if kind == T.YELL then return R.Yell end
	if kind == T.LOOC then return R.LOOC end
	return R.Say
end

-- ------------------------------------------------------------- оружие --
NYRP.Safety = NYRP.Safety or {}
local SF = NYRP.Safety

SF.HoldTime = 0.4        -- сколько держать R
SF.RaiseDelay = 0.35     -- после подъёма столько секунд нельзя выстрелить (оружие ещё поднимается)
-- Оружие, которое опускается, даже если его нет среди предметов.
SF.Extra = {
	weapon_pistol = true, weapon_357 = true, weapon_smg1 = true, weapon_ar2 = true, weapon_shotgun = true,
	weapon_crossbow = true, weapon_rpg = true, weapon_crowbar = true, weapon_stunstick = true,
}
-- Опущенное — поза «руки вдоль тела» (normal) вместо «оружие у груди» (passive).
SF.NormalPose = { weapon_pistol = true, weapon_357 = true, weapon_crowbar = true, weapon_stunstick = true }

local classes, builtAt = nil, 0
-- Классы оружия из предметов: категория weapon, тип weapon (не инструменты), слоты primary/secondary/melee.
function SF.Classes()
	if classes and CurTime() - builtAt < 15 then return classes end
	classes = table.Copy(SF.Extra)
	builtAt = CurTime()
	local list = NYRP.Items and NYRP.Items.List or {}
	for _, def in pairs(list) do
		local slot = def.weaponSlot
		if def.class and def.category == "weapon" and def.type == "weapon"
			and (slot == "primary" or slot == "secondary" or slot == "melee") then
			classes[def.class] = true
		end
	end
	return classes
end

-- огнестрел из популярных баз (TFA, ARC9, CW 2.0, M9K, MW Base) — тоже опускается
local GUN_BASES = { tfa_gun_base = true, tfa_bash_base = true, arc9_base = true, arc9_go_base = true, cw_base = true,
	bobs_gun_base = true, bobs_shotty_base = true, bobs_scoped_base = true, mg_base = true, weapon_base = false }
local function isGunBase(wep)
	local b = wep.Base
	local guard = 0
	while b and guard < 8 do
		if GUN_BASES[b] then return true end
		local t = weapons.GetStored(b)
		b = t and t.Base
		guard = guard + 1
	end
	return false
end

function SF.Applies(wep)
	if not IsValid(wep) then return false end
	local cls = tostring(wep:GetClass())
	if string.sub(cls, 1, 5) == "nyrp_" then return false end   -- ключи, рация, телефон, руки и т.д.
	if SF.Classes()[cls] == true then return true end
	if wep.nyrpGunBase == nil then wep.nyrpGunBase = isGunBase(wep) end
	return wep.nyrpGunBase
end

function SF.Raised(ply) return ply:GetNW2Bool("nyrp.wepRaised", false) end

-- Оружие в руках опущено (стрелять нельзя).
function SF.Lowered(ply, wep)
	wep = wep or ply:GetActiveWeapon()
	return SF.Applies(wep) and not SF.Raised(ply)
end

-- Держать R — поднять/опустить. Из опущенного нельзя стрелять и перезаряжаться.
-- Удержание R отслеживает КЛИЕНТ (ниже клавиша R вырезается из команды, пока оружие опущено,
-- и сервер её не увидел бы), переключение — консольной командой nyrp_raise на сервер.
hook.Add("StartCommand", "nyrp.safety", function(ply, cmd)
	if not ply:Alive() then ply.nyrpRHold = nil return end
	local wep = ply:GetActiveWeapon()
	if not SF.Applies(wep) then ply.nyrpRHold = nil return end
	local raised = SF.Raised(ply)
	if CLIENT and ply == LocalPlayer() then
		if cmd:KeyDown(IN_RELOAD) and not vgui.GetKeyboardFocus() then
			local now = RealTime()
			if not ply.nyrpRHold then
				ply.nyrpRHold = now
				ply.nyrpRDone = false
			end
			if not ply.nyrpRDone and now - ply.nyrpRHold >= SF.HoldTime then
				ply.nyrpRDone = true
				RunConsoleCommand("nyrp_raise")
			end
		else
			ply.nyrpRHold = nil
		end
	end
	if not raised or CurTime() < ply:GetNW2Float("nyrp.wepRaiseT", 0) + SF.RaiseDelay then
		cmd:RemoveKey(IN_ATTACK)
		cmd:RemoveKey(IN_ATTACK2)
		if not raised then cmd:RemoveKey(IN_RELOAD) end
	end
end)

-- Анимации опущенного оружия: подменяем активности стойки, ходьбы, бега, приседа, прыжка, плавания.
local OFFSETS
local function offsets()
	if OFFSETS then return OFFSETS end
	OFFSETS = {
		{ ACT_MP_STAND_IDLE, 0 }, { ACT_MP_WALK, 1 }, { ACT_MP_RUN, 2 }, { ACT_MP_CROUCH_IDLE, 3 },
		{ ACT_MP_CROUCHWALK, 4 }, { ACT_MP_JUMP, 7 }, { ACT_MP_SWIM, 9 },
	}
	return OFFSETS
end
local PASSIVE, NORMAL
local function poseTables()
	if PASSIVE then return PASSIVE, NORMAL end
	PASSIVE, NORMAL = {}, {}
	for _, o in ipairs(offsets()) do
		PASSIVE[o[1]] = ACT_HL2MP_IDLE_PASSIVE + o[2]
		NORMAL[o[1]] = ACT_HL2MP_IDLE + o[2]
	end
	NORMAL[ACT_MP_JUMP] = ACT_HL2MP_JUMP_SLAM
	return PASSIVE, NORMAL
end

hook.Add("TranslateActivity", "nyrp.safety", function(ply, act)
	if not IsValid(ply) or not ply:IsPlayer() then return end
	local wep = ply:GetActiveWeapon()
	if not SF.Lowered(ply, wep) then return end
	if (NYRP.Sit and NYRP.Sit.Sitting(ply)) or (NYRP.Acts and NYRP.Acts.Current(ply)) then return end
	local P, N = poseTables()
	local t = SF.NormalPose[wep:GetClass()] and N or P
	return t[act]
end)
