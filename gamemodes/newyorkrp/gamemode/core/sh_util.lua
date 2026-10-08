--[[
	Общие утилиты.
]]

local prefix = Color(247, 198, 0)
local text = Color(230, 230, 235)

function NYRP.Print(...)
	MsgC(prefix, "[NYRP] ", text, table.concat({ ... }, " "), "\n")
end

-- Имя персонажа игрока (или ник Steam, если персонаж не выбран).
function NYRP.CharName(ply)
	if not IsValid(ply) then return "?" end
	local name = ply:GetNW2String("nyrp.name", "")
	return name ~= "" and name or ply:Nick()
end

function NYRP.HasCharacter(ply)
	return IsValid(ply) and ply:GetNW2Int("nyrp.charID", 0) > 0
end

-- Обрезка и очистка пользовательского текста.
function NYRP.CleanText(str, maxLen)
	str = tostring(str or "")
	str = string.gsub(str, "[%c]", " ")
	str = string.Trim(str)
	if maxLen and utf8.len(str) and utf8.len(str) > maxLen then
		str = string.sub(str, 1, utf8.offset(str, maxLen + 1) - 1)
	end
	return str
end

NYRP.Print("New-York Roleplay v" .. NYRP.Version .. " загружается (" .. (SERVER and "server" or "client") .. ")")

if SERVER then
	-- Поставить энтити на пол под ней (низ модели касается поверхности).
	function NYRP.SnapToFloor(ent)
		if not IsValid(ent) then return end
		local pos = ent:GetPos()
		local tr = util.TraceLine({ start = pos + Vector(0, 0, 24), endpos = pos - Vector(0, 0, 4096), filter = ent, mask = MASK_SOLID_BRUSHONLY })
		if not tr.Hit then return end
		local mins = ent:OBBMins()
		ent:SetPos(Vector(pos.x, pos.y, tr.HitPos.z - mins.z))
		local phys = ent:GetPhysicsObject()
		if IsValid(phys) then phys:Wake() end
	end

	-- Всё, что ставится из спавн-меню, и наши энтити — сразу на пол.
	local snapClasses = { nyrp_container = true, nyrp_npc = true, nyrp_vending = true }
	hook.Add("PlayerSpawnedSENT", "nyrp.snap", function(ply, ent) timer.Simple(0, function() NYRP.SnapToFloor(ent) end) end)
	hook.Add("OnEntityCreated", "nyrp.snap", function(ent)
		if snapClasses[ent:GetClass()] then timer.Simple(0, function() NYRP.SnapToFloor(ent) end) end
	end)
end
