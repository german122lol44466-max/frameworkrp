--[[
	Мелкие общие утилиты.
]]

local prefix = Color(247, 198, 0)
local text = Color(230, 230, 235)

function NYRP.Print(...)
	MsgC(prefix, "[NYRP] ", text, table.concat({ ... }, " "), "\n")
end

NYRP.Print("New-York Roleplay v" .. NYRP.Version .. " загружается (" .. (SERVER and "server" or "client") .. ")")
