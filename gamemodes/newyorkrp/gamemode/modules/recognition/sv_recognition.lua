--[[
	Знакомства. Пока вы не знакомы с персонажем, над ним «НЕИЗВЕСТНЫЙ».
	Познакомиться: /познакомиться (/introduce) глядя на человека, или показать ему удостоверение.
	Список знакомых хранится у персонажа (столбец recognized): { id = когда последний раз виделись }.

	Память: если долго не видеться, имя можно забыть. Чем выше «Интеллект», тем дольше помнит
	и тем меньше шанс забыть (Config.Memory). Встреча рядом обновляет память.
]]

NYRP.Recog = NYRP.Recog or {}
local R = NYRP.Recog

function R.Sync(ply)
	net.Start("nyrp.recog.sync")
	local ids = table.GetKeys(ply.nyrpRecog or {})
	net.WriteUInt(#ids, 16)
	for _, id in ipairs(ids) do net.WriteUInt(id, 32) end
	net.Send(ply)
end

-- ply узнаёт персонажа other.
function R.Add(ply, other)
	if not NYRP.HasCharacter(ply) or not NYRP.HasCharacter(other) then return end
	local id = other:GetNW2Int("nyrp.charID")
	ply.nyrpRecog = ply.nyrpRecog or {}
	if ply.nyrpRecog[id] then ply.nyrpRecog[id] = os.time() return end
	ply.nyrpRecog[id] = os.time()
	R.Sync(ply)
	NYRP.Notify(ply, "Теперь вы знаете: " .. NYRP.CharName(other), "success")
end

function R.Introduce(ply)
	local tr = ply:GetEyeTrace()
	local target = tr.Entity
	if not IsValid(target) or not target:IsPlayer() or target:GetPos():Distance(ply:GetPos()) > 160 then
		NYRP.Notify(ply, "Посмотрите на человека рядом, чтобы представиться", "warning")
		return
	end
	R.Add(target, ply)
	NYRP.Notify(ply, "Вы представились", "success")
	if NYRP.Skills then NYRP.Skills.AddXP(ply, "intellect", 10) end
end

concommand.Add("nyrp_introduce", function(ply) if IsValid(ply) then R.Introduce(ply) end end)
net.Receive("nyrp.recog.introduce", function(_, ply) R.Introduce(ply) end)

-- ----------------------------------------------------------------- память --
NYRP.Config.Memory = NYRP.Config.Memory or {
	Check = 300,        -- как часто проверяем (с)
	Grace = 20 * 60,    -- сколько можно не видеться без риска (с), умножается на (1 + интеллект)
	Chance = 0.14,      -- шанс забыть за проверку при интеллекте 0
	PerPoint = 0.18,    -- каждое очко интеллекта уменьшает шанс на 18%
	SeeRange = 600,     -- встреча на таком расстоянии освежает память
}

function R.Export(ply)
	local out = {}
	for id, ts in pairs(ply.nyrpRecog or {}) do out[tostring(id)] = ts end
	return out
end

timer.Create("nyrp.recog.memory", NYRP.Config.Memory.Check, 0, function()
	local M = NYRP.Config.Memory
	local now = os.time()
	local byChar = {}
	for _, p in ipairs(player.GetAll()) do
		if NYRP.HasCharacter(p) then byChar[p:GetNW2Int("nyrp.charID")] = p end
	end
	for _, ply in ipairs(player.GetAll()) do
		if NYRP.HasCharacter(ply) and ply.nyrpRecog then
			local intel = ply.nyrpChar.skills and ply.nyrpChar.skills.intellect or 0
			local grace = M.Grace * (1 + intel)
			local chance = M.Chance * math.max(0.05, 1 - intel * M.PerPoint)
			local forgot
			for id, ts in pairs(ply.nyrpRecog) do
				local other = byChar[id]
				if IsValid(other) and other:GetPos():Distance(ply:GetPos()) <= M.SeeRange then
					ply.nyrpRecog[id] = now
				elseif now - ts > grace and math.random() < chance then
					ply.nyrpRecog[id] = nil
					forgot = other or true
				end
			end
			if forgot then
				R.Sync(ply)
				local desc = IsValid(forgot) and forgot:GetNW2String("nyrp.desc", "") or ""
				if desc ~= "" then desc = " — «" .. string.sub(desc, 1, (utf8.offset(desc, 51) or (#desc + 1)) - 1) .. "…»" end
				NYRP.Notify(ply, "Вы никак не можете вспомнить, как зовут одного знакомого" .. desc, "warning", 8)
			end
		end
	end
end)

-- ----------------------------------------------------------- меню памяти (H) --
-- Клиент просит воспоминания: знакомые (имя, внешность, описание, когда виделись) и выполненные задания.
net.Receive("nyrp.memory", function(_, ply)
	if (ply.nyrpMemNext or 0) > CurTime() then return end
	ply.nyrpMemNext = CurTime() + 1
	if not NYRP.HasCharacter(ply) then return end
	local people = {}
	local ids = {}
	for id in pairs(ply.nyrpRecog or {}) do ids[#ids + 1] = tonumber(id) end
	if #ids > 0 then
		local rows = NYRP.DB.Query("SELECT id, name, model, gender, description, height FROM nyrp_characters WHERE id IN (" .. table.concat(ids, ",") .. ")") or {}
		for _, r in ipairs(rows) do
			local id = tonumber(r.id)
			people[#people + 1] = { id = id, name = r.name, model = r.model, gender = r.gender, desc = r.description,
				height = tonumber(r.height) or 175, seen = ply.nyrpRecog[id] or 0 }
		end
	end
	table.sort(people, function(a, b) return a.seen > b.seen end)
	net.Start("nyrp.memory")
	net.WriteTable(people)
	net.WriteTable(NYRP.NPC and NYRP.NPC.DoneQuests and NYRP.NPC.DoneQuests(ply) or {})
	net.WriteDouble(os.time())
	net.Send(ply)
end)
