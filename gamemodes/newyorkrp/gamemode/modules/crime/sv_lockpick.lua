--[[
	Взлом замков (сервер). Предмет «Отмычки» (framework/items/tools/lockpick.lua) → оружие nyrp_lockpick.
	ЛКМ по запертой двери → мини-игра. Сервер загадывает угол «сладкого места» (-90°..90°) и его ширину
	(чем выше «Ловкость», тем шире), клиенту сообщает только широкую зону «вибрации», внутри которой оно лежит.
	Клиент присылает угол, при котором игрок проворачивает замок; сервер решает:
	  попал — дверь отпирается (владелец получает уведомление, с шансом срабатывает сигнализация → 911);
	  не попал — замок проворачивается частично, отмычка может сломаться (тратится одна из стопки).
	Служебные двери (полиция/медики/пожарные — /doorfaction) взломать нельзя.
]]

NYRP.Crime = NYRP.Crime or {}
local C = NYRP.Crime

local sessions = {}   -- [ply] = { door, sweet, width, start, nextTry }

local DOOR_CLASSES = { prop_door_rotating = true, func_door = true, func_door_rotating = true }

local function isLocked(door)
	local D = NYRP.Doors
	local id = D and D.IdOf and D.IdOf(door)
	if id and D.Data[id] then return D.Data[id].locked and true or false, id end
	return door:GetInternalVariable("m_bLocked") == true, nil
end

-- сколько отмычек в руке (стопка в слоте «В руке»)
local function picksInHand(ply)
	local it = NYRP.Inv.Get(ply).equip.tool
	return (it and it.id == "lockpick") and it.n or 0
end

-- сломалась отмычка: минус одна; кончились в руке — подкладываем из сумки
local function breakPick(ply)
	local inv = NYRP.Inv.Get(ply)
	local it = inv.equip.tool
	if not it or it.id ~= "lockpick" then return 0 end
	it.n = it.n - 1
	if it.n <= 0 then
		inv.equip.tool = nil
		for k, s in pairs(inv.slots) do
			if s.id == "lockpick" then
				inv.equip.tool = s
				inv.slots[k] = nil
				break
			end
		end
		if not inv.equip.tool and ply:HasWeapon("nyrp_lockpick") then ply:StripWeapon("nyrp_lockpick") end
	end
	NYRP.Inv.Sync(ply)
	return picksInHand(ply)
end

local function close(ply, why)
	sessions[ply] = nil
	if not IsValid(ply) then return end
	net.Start("nyrp.crime.lock")
	net.WriteBool(false)
	net.Send(ply)
	if why then NYRP.Notify(ply, why, "warning", 4) end
end

function C.StartLockpick(ply, door)
	if sessions[ply] or (ply.nyrpLockNext or 0) > CurTime() then return end
	if not IsValid(door) or not DOOR_CLASSES[door:GetClass()] then
		NYRP.Notify(ply, "Отмычкой вскрывают замки дверей", "warning", 3)
		return
	end
	if door:NearestPoint(ply:EyePos()):Distance(ply:EyePos()) > C.Lock.Range then
		NYRP.Notify(ply, "Подойдите к двери вплотную", "warning", 3)
		return
	end
	if door:GetNW2String("nyrp.doorRole", "") ~= "" then
		ply:EmitSound("doors/handle_pushbar_locked1.wav", 55)
		NYRP.Notify(ply, "Служебная дверь: электронный замок, отмычкой его не взять", "error", 5)
		return
	end
	local locked, id = isLocked(door)
	if not locked then NYRP.Notify(ply, "Дверь не заперта", "info", 3) return end
	if id and NYRP.Doors.HasAccess(ply, id) then NYRP.Notify(ply, "Это ваша дверь — откройте ключом", "info", 3) return end
	if picksInHand(ply) <= 0 then return end

	local lvl = NYRP.Skills.Level(ply, "agility") or 0
	local width = C.Lock.ZoneBase + lvl * C.Lock.ZonePerLevel
	local maxA = C.Lock.MaxAngle - width
	local sweet = math.Rand(-maxA, maxA)
	-- зона вибрации: сладкое место где-то внутри неё (не обязательно по центру)
	local hw = C.Lock.HintWidth
	local hint = math.Clamp(sweet + math.Rand(-(hw - width), hw - width), -C.Lock.MaxAngle, C.Lock.MaxAngle)
	sessions[ply] = { door = door, sweet = sweet, width = width, start = CurTime(), nextTry = CurTime() + 0.5, tries = 0 }
	ply:EmitSound("nyrp/fx/keys.wav", 45, 140)

	net.Start("nyrp.crime.lock")
	net.WriteBool(true)
	net.WriteEntity(door)
	net.WriteFloat(hint)
	net.WriteFloat(hw)
	net.WriteUInt(picksInHand(ply), 8)
	net.WriteUInt(lvl, 8)
	net.WriteString(id and (NYRP.Doors.Data[id].name or "Квартира") or "Дверь")
	net.Send(ply)
end

local function unlock(ply, door)
	local D = NYRP.Doors
	local id = D and D.IdOf and D.IdOf(door)
	local d = id and D.Data[id]
	if d then
		d.locked = false
		D.Save()
		D.Apply(id)
		if d.owner then
			for _, p in ipairs(player.GetAll()) do
				if p.nyrpChar and p.nyrpChar.id == d.owner then
					NYRP.Notify(p, "Охранная система: замок «" .. (d.name or "помещение") .. "» вскрыт!", "error", 12)
				end
			end
		end
	else
		door:Fire("Unlock")
	end
	door:EmitSound("doors/door_latch3.wav", 60)
	door:EmitSound("nyrp/fx/lock_turn.wav", 55, 110)
	NYRP.Skills.AddXP(ply, "agility", 20, "взлом замка")
	NYRP.Notify(ply, "Замок поддался — дверь открыта", "success", 4)
	hook.Run("NYRP.DoorLockpicked", ply, door, id)
	local lvl = NYRP.Skills.Level(ply, "agility") or 0
	if math.random() < math.max(0.1, C.Lock.AlarmChance - lvl * 0.02) then
		door:EmitSound("nyrp/fx/alarm.wav", 85)
		timer.Create("nyrp.crime.alarm." .. door:EntIndex(), 1.2, 8, function() if IsValid(door) then door:EmitSound("nyrp/fx/alarm.wav", 85) end end)
		if NYRP.E911 and NYRP.E911.Auto then NYRP.E911.Auto("police", door:GetPos(), "Взлом двери") end
		NYRP.Notify(ply, "Сработала сигнализация!", "error", 5)
	end
end

net.Receive("nyrp.crime.lockTry", function(_, ply)
	local s = sessions[ply]
	local quit = net.ReadBool()
	if not s then return end
	if quit then close(ply) ply.nyrpLockNext = CurTime() + C.Lock.Cooldown return end
	local ang = net.ReadFloat()
	if CurTime() < s.nextTry then return end
	s.nextTry = CurTime() + C.Lock.TryDelay
	local door = s.door
	if not IsValid(door) or not ply:Alive() or door:NearestPoint(ply:EyePos()):Distance(ply:EyePos()) > C.Lock.Range + 30 then
		close(ply, "Вы отошли от двери")
		return
	end
	local w = ply:GetActiveWeapon()
	if not IsValid(w) or w:GetClass() ~= "nyrp_lockpick" or picksInHand(ply) <= 0 then close(ply) return end
	if not isLocked(door) then close(ply, "Дверь уже открыта") return end
	ang = math.Clamp(tonumber(ang) or 0, -C.Lock.MaxAngle, C.Lock.MaxAngle)
	s.tries = s.tries + 1
	local diff = math.abs(ang - s.sweet)

	net.Start("nyrp.crime.lockRes")
	if diff <= s.width then
		net.WriteUInt(1, 2)
		net.WriteFloat(1)
		net.WriteUInt(picksInHand(ply), 8)
		net.Send(ply)
		sessions[ply] = nil
		ply.nyrpLockNext = CurTime() + C.Lock.Cooldown
		unlock(ply, door)
		return
	end
	local frac = math.Clamp(1 - (diff - s.width) / 45, 0.05, 0.9)
	local lvl = NYRP.Skills.Level(ply, "agility") or 0
	local breakP = math.max(0.06, 0.28 - lvl * 0.02 + (1 - frac) * 0.12)
	door:EmitSound("physics/metal/metal_box_impact_soft" .. math.random(1, 3) .. ".wav", 45, math.random(150, 170))
	if math.random() < breakP then
		local left = breakPick(ply)
		ply:EmitSound("physics/metal/metal_solid_impact_bullet" .. math.random(1, 4) .. ".wav", 50, 180)
		NYRP.Skills.AddXP(ply, "agility", 3, "сломанная отмычка")
		net.WriteUInt(3, 2)
		net.WriteFloat(frac)
		net.WriteUInt(left, 8)
		net.Send(ply)
		if left <= 0 then
			sessions[ply] = nil
			ply.nyrpLockNext = CurTime() + C.Lock.Cooldown
			NYRP.Notify(ply, "Последняя отмычка сломалась", "error", 4)
		end
		return
	end
	net.WriteUInt(2, 2)
	net.WriteFloat(frac)
	net.WriteUInt(picksInHand(ply), 8)
	net.Send(ply)
end)

timer.Create("nyrp.crime.lock", 1, 0, function()
	for ply, s in pairs(sessions) do
		if not IsValid(ply) then sessions[ply] = nil
		elseif not ply:Alive() or not IsValid(s.door) or CurTime() - s.start > C.Lock.Timeout then close(ply, "Взлом прерван")
		elseif s.door:NearestPoint(ply:EyePos()):Distance(ply:EyePos()) > C.Lock.Range + 40 then close(ply, "Вы отошли от двери") end
	end
end)

hook.Add("PlayerDisconnected", "nyrp.crime.lock", function(ply) sessions[ply] = nil end)
