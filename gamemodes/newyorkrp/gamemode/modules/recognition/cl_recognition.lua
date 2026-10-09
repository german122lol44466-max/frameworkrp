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

-- Как локальный игрок называет человека: имя, если знакомы, иначе — по описанию внешности.
function R.NameFor(ply)
	if not IsValid(ply) then return "?" end
	if R.Knows(ply) then return NYRP.CharName(ply) end
	local desc = ply:GetNW2String("nyrp.desc", "")
	if desc ~= "" then
		local off = utf8.offset(desc, 41)
		return "Незнакомец: " .. (off and (string.sub(desc, 1, off - 1) .. "…") or desc)
	end
	return "Незнакомец"
end
