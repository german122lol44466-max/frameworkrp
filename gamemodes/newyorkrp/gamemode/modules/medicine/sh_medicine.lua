--[[
	Бой и «динамическая медицина».
	Попадание по частям тела:
	  голова  — без каски два попадания из пистолета смертельны; каска (ProtectZone = "head") держит удар;
	  тело    — кровотечение (−1 HP раз в 4 с) и одышка, бронежилет (ProtectZone = "body") снижает урон и шанс ранения;
	  рука    — рука дрожит: разброс ×1.6, сильнее отдача;
	  нога    — хромота (бег недоступен, медленнее) и шанс упасть.
	Аптечка лечит ранения; навык «Стрельба» уменьшает разброс и отдачу.
	Ранения: NW2Float nyrp.wound_<часть>Until (как другие состояния), nyrp.bleeding.
]]

NYRP.Combat = NYRP.Combat or {}
local CB = NYRP.Combat
local Cond = NYRP.Cond

CB.WoundTime = { leg = 240, arm = 240, body = 300, head = 180 }

function CB.Wound(ply, part) return Cond.Until(ply, "wound_" .. part) > 0 end

-- множитель разброса/отдачи: навык 0 → 1.3, 10 → 0.7; рука ранена → ×1.6
function CB.AimFactor(ply)
	local sk = ply.nyrpChar and ply.nyrpChar.skills and ply.nyrpChar.skills.combat or ply:GetNW2Int("nyrp.skillCombat", 0)
	local f = 1.3 - math.min(sk, 10) * 0.06
	if CB.Wound(ply, "arm") then f = f * 1.6 end
	if Cond.Until(ply, "concussion") > 0 then f = f * 1.25 end
	return f
end

-- разброс пуль (у стандартного оружия HL2 и большинства SWEP через FireBullets)
hook.Add("EntityFireBullets", "nyrp.combat", function(ent, data)
	if not IsValid(ent) or not ent:IsPlayer() then return end
	local f = CB.AimFactor(ent)
	data.Spread = (data.Spread or vector_origin) * f + Vector(0.004, 0.004, 0) * math.max(0, f - 1)
	if CLIENT and IsFirstTimePredicted() and ent == LocalPlayer() and CB.OnLocalFire then CB.OnLocalFire(ent, data, f) end
	return true
end)

-- раненая нога: без бега и медленнее
local origFactor = Cond.SpeedFactor
function Cond.SpeedFactor(ply)
	local f = origFactor(ply)
	if CB.Wound(ply, "leg") then f = f * 0.72 end
	return f
end
local origSprint = Cond.CanSprint
function Cond.CanSprint(ply)
	return origSprint(ply) and not CB.Wound(ply, "leg")
end

local function secs(t)
	t = math.ceil(t)
	return t >= 60 and string.format("%d:%02d", math.floor(t / 60), t % 60) or (t .. " с")
end

for _, st in ipairs({
	{ id = "wound_head", name = "Ранение в голову", icon = "wound_head", level = "danger",
		desc = "Пуля задела голову: кружится голова, плывёт картинка. Ещё одно попадание может стать смертельным.",
		part = "head" },
	{ id = "wound_body", name = "Ранение в корпус", icon = "wound_body", level = "danger",
		desc = "Кровотечение: здоровье медленно уходит, тяжело дышать. Нужна аптечка или медик.", part = "body" },
	{ id = "wound_arm", name = "Ранение в руку", icon = "wound_arm", level = "warn",
		desc = "Рука дрожит: оружие сильнее разбрасывает и уводит при отдаче.", part = "arm" },
	{ id = "wound_leg", name = "Ранение в ногу", icon = "wound_leg", level = "warn",
		desc = "Хромаете: бег недоступен, вы медленнее. Попадание в ногу может свалить с ног.", part = "leg" },
	{ id = "heavy", name = "Тяжёлая броня", icon = "heavy", level = "info",
		desc = "Тяжёлый бронежилет хорошо держит пули, но вы двигаетесь медленнее.",
		check = function(ply) return ply:GetNW2Bool("nyrp.heavyArmor") end, value = function() return "Скорость снижена" end },
}) do
	if st.part then
		local part = st.part
		st.check = function(ply) return CB.Wound(ply, part) end
		st.value = function(ply) return "Заживёт через " .. secs(Cond.Until(ply, "wound_" .. part)) end
	end
	Cond.Statuses[#Cond.Statuses + 1] = st
end
