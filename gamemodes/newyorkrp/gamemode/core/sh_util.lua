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
