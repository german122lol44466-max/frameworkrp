--[[
	Деньги персонажа (наличные). Хранятся в flags персонажа, видны через NW2Int "nyrp.money".
]]

NYRP.Money = NYRP.Money or {}
NYRP.Config.StartMoney = NYRP.Config.StartMoney or 250

function NYRP.Money.Get(ply) return ply:GetNW2Int("nyrp.money", 0) end

function NYRP.Money.Format(n)
	local s = tostring(math.floor(n or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return "$" .. string.Trim(out)
end
