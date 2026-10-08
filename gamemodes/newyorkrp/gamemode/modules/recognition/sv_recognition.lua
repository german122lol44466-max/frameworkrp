--[[
	Знакомства. Пока вы не знакомы с персонажем, над ним «НЕИЗВЕСТНЫЙ».
	Познакомиться: /познакомиться (/introduce) глядя на человека, или показать ему удостоверение.
	Список знакомых хранится у персонажа (столбец recognized).
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
	if ply.nyrpRecog[id] then return end
	ply.nyrpRecog[id] = true
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
end

concommand.Add("nyrp_introduce", function(ply) if IsValid(ply) then R.Introduce(ply) end end)
net.Receive("nyrp.recog.introduce", function(_, ply) R.Introduce(ply) end)
