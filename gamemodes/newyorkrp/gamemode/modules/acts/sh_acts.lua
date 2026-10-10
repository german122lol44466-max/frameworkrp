--[[
	Позы (/act): персонаж принимает позу и стоит в ней, пока игрок не пойдёт, не прыгнет или не наберёт /act снова.
	  /act <поза>  — принять позу (без аргумента — выйти из позы);  /acts — окно со всеми позами.
	Анимации — из общих анимаций моделей игроков (models/m_anm.mdl, f_anm.mdl): у каждой позы список
	последовательностей, берётся первая, которая есть у модели (ply:LookupSequence). Руки (сдаться, за голову)
	дополнительно ставятся поворотом костей ValveBiped. Корпус развёрнут по направлению при входе в позу,
	голова продолжает следить за взглядом. В позе нельзя сидеть (Alt+E) и наоборот — modules/sit.
]]

NYRP.Acts = NYRP.Acts or {}
local A = NYRP.Acts

if SERVER then
	util.AddNetworkString("nyrp.acts.do")
	util.AddNetworkString("nyrp.acts.menu")
end

-- Повороты костей для поз рук (подбираются на глаз, правятся здесь).
A.Bones = {
	handsup = {
		["ValveBiped.Bip01_R_UpperArm"] = Angle(73, 35, 128),
		["ValveBiped.Bip01_R_Forearm"] = Angle(-22, 1, 15),
		["ValveBiped.Bip01_R_Hand"] = Angle(33, 39, -21),
		["ValveBiped.Bip01_L_UpperArm"] = Angle(-77, -46, 4),
		["ValveBiped.Bip01_L_Forearm"] = Angle(-28, -29, 44),
		["ValveBiped.Bip01_L_Hand"] = Angle(-12, 12, 90),
	},
	handshead = {
		["ValveBiped.Bip01_R_UpperArm"] = Angle(40, -95, -30),
		["ValveBiped.Bip01_R_Forearm"] = Angle(0, -130, 0),
		["ValveBiped.Bip01_R_Hand"] = Angle(0, -20, 0),
		["ValveBiped.Bip01_L_UpperArm"] = Angle(-40, -95, 30),
		["ValveBiped.Bip01_L_Forearm"] = Angle(0, -130, 0),
		["ValveBiped.Bip01_L_Hand"] = Angle(0, -20, 0),
	},
}

--[[
	Поза: id, name (как писать в /act), aliases, icon (nyrp/icons), desc,
	seq — список последовательностей по порядку предпочтения,
	wall = "back" — нужна стена за спиной (игрок прижимается к ней спиной), "optional" — если есть, то wallSeq,
	view — множитель высоты камеры, bones — ключ A.Bones.
]]
A.List = {
	{ id = "squat", name = "сесть_на_корточки", aliases = { "корточки", "присесть", "squat", "crouch" }, icon = "fall",
		desc = "Присесть на корточки", seq = { "pose_ducking_01", "pose_ducking_02" }, view = 0.62 },
	{ id = "lean", name = "стоять_облокотившись", aliases = { "облокотиться", "прислониться", "lean" }, icon = "user",
		desc = "Облокотиться спиной о стену", seq = { "pose_standing_04", "pose_standing_01", "idle_all_01" }, wall = "back" },
	{ id = "handsup", name = "руки_вверх", aliases = { "сдаться", "сдаюсь", "surrender", "handsup" }, icon = "g_halt",
		desc = "Поднять руки — сдаться", seq = { "idle_all_01", "idle_all_scared" }, bones = "handsup" },
	{ id = "handshead", name = "руки_за_голову", aliases = { "за_голову", "handshead" }, icon = "user",
		desc = "Руки за голову", seq = { "idle_all_01", "pose_standing_01" }, bones = "handshead" },
	{ id = "crossarms", name = "скрестить_руки", aliases = { "скрестить", "crossarms", "arms" }, icon = "user",
		desc = "Стоять, скрестив руки", seq = { "pose_standing_02", "pose_standing_01" } },
	{ id = "stand", name = "стоять", aliases = { "стойка", "stand", "pose" }, icon = "user",
		desc = "Стоять в непринуждённой позе", seq = { "pose_standing_01", "pose_standing_03", "idle_all_01" } },
	{ id = "think", name = "задуматься", aliases = { "думать", "think" }, icon = "question",
		desc = "Задумчивая поза", seq = { "pose_standing_03", "pose_standing_04", "pose_standing_01" } },
	{ id = "cower", name = "испуг", aliases = { "бояться", "сжаться", "cower", "scared" }, icon = "warning",
		desc = "Сжаться от страха", seq = { "idle_all_cower", "idle_all_scared" } },
	{ id = "lie", name = "лечь", aliases = { "лежать", "lie", "laydown" }, icon = "bed",
		desc = "Лечь на землю", seq = { "zombie_slump_idle_02", "zombie_slump_idle_01", "sit_zen" }, view = 0.22 },
	{ id = "injured", name = "раненый", aliases = { "ранен", "ранение", "injured", "wounded" }, icon = "bandage",
		desc = "Раненый: у стены — сидя, иначе лёжа", seq = { "zombie_slump_idle_02", "zombie_slump_idle_01", "sit_zen" },
		wall = "optional", wallSeq = { "zombie_slump_idle_01", "sit_zen" }, view = 0.3, wallView = 0.42 },
	{ id = "sitwall", name = "сидеть_у_стены", aliases = { "у_стены", "sitwall" }, icon = "fall",
		desc = "Сесть на пол, прислонившись к стене", seq = { "sit_zen", "zombie_slump_idle_01", "pose_ducking_02" },
		wall = "back", view = 0.42 },
	{ id = "sitfloor", name = "сидеть", aliases = { "сесть", "sit", "sitfloor" }, icon = "fall",
		desc = "Сесть на пол", seq = { "sit_zen" }, view = 0.42 },
}
A.ById = {}
for i, a in ipairs(A.List) do a.index = i A.ById[a.id] = a end

-- string.lower не понимает кириллицу
local function lowerRu(s)
	s = string.lower(s or "")
	s = string.gsub(s, "\208([\144-\159])", function(c) return "\208" .. string.char(string.byte(c) + 32) end)
	s = string.gsub(s, "\208([\160-\175])", function(c) return "\209" .. string.char(string.byte(c) - 32) end)
	s = string.gsub(s, "\208\129", "\209\145")
	return s
end

function A.Find(text)
	text = string.gsub(lowerRu(string.Trim(text or "")), "[%s%-]+", "_")
	text = string.gsub(text, "ё", "е")
	if text == "" then return end
	for _, a in ipairs(A.List) do
		if a.id == text or string.gsub(a.name, "ё", "е") == text then return a end
		for _, al in ipairs(a.aliases or {}) do if al == text then return a end end
	end
	-- по началу названия
	for _, a in ipairs(A.List) do
		if string.sub(a.name, 1, #text) == text then return a end
	end
end

-- Текущая поза игрока (таблица из A.List) или nil.
function A.Current(ply)
	local i = ply:GetNW2Int("nyrp.act", 0)
	return i > 0 and A.List[i] or nil
end
function A.OnWall(ply) return ply:GetNW2Bool("nyrp.actWall", false) end

-- Последовательность позы для модели (кеш по модели).
local seqCache = {}
function A.Sequence(ply, a, onWall)
	local list = (onWall and a.wallSeq) or a.seq
	local key = ply:GetModel() .. "#" .. a.id .. (onWall and "w" or "")
	local c = seqCache[key]
	if c ~= nil then return c end
	c = -1
	for _, name in ipairs(list) do
		local s = ply:LookupSequence(name)
		if s and s >= 0 then c = s break end
	end
	seqCache[key] = c
	return c
end

hook.Add("CalcMainActivity", "nyrp.acts", function(ply)
	local a = A.Current(ply)
	if not a or (NYRP.Sit and NYRP.Sit.Sitting(ply)) then return end
	local seq = A.Sequence(ply, a, A.OnWall(ply))
	if seq and seq >= 0 then return ACT_HL2MP_IDLE, seq end
end)

-- в позе не ходим, не прыгаем, не приседаем (выход из позы — на сервере по нажатию клавиш)
hook.Add("SetupMove", "nyrp.acts", function(ply, mv)
	if not A.Current(ply) then return end
	mv:SetForwardSpeed(0)
	mv:SetSideSpeed(0)
	mv:SetUpSpeed(0)
	mv:SetVelocity(vector_origin)
	mv:SetButtons(bit.band(mv:GetButtons(), bit.bnot(bit.bor(IN_DUCK, IN_SPEED, IN_JUMP))))
end)

-- в позе нельзя стрелять
hook.Add("StartCommand", "nyrp.acts", function(ply, cmd)
	if not A.Current(ply) then return end
	cmd:RemoveKey(IN_ATTACK)
	cmd:RemoveKey(IN_ATTACK2)
	cmd:RemoveKey(IN_RELOAD)
end)
