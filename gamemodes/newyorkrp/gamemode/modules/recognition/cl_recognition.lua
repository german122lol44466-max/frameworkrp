--[[
	Клиентская часть знакомств: кого знает локальный игрок.
]]

NYRP.Recog = NYRP.Recog or {}
local R = NYRP.Recog
R.Known = R.Known or {}

net.Receive("nyrp.recog.sync", function()
	R.Known = {}
	for _ = 1, net.ReadUInt(16) do R.Known[net.ReadUInt(32)] = true end
end)

-- Знает ли локальный игрок этого персонажа (маска скрывает лицо).
function R.Knows(ply)
	if ply == LocalPlayer() then return true end
	if ply:GetNW2Bool("nyrp.masked") then return false end
	return R.Known[ply:GetNW2Int("nyrp.charID")] == true
end
