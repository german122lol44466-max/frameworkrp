--[[
	Профессии из gamemode/framework/jobs/ (см. README там). Берут у NPC центра занятости (/npc jobs).
	У персонажа — c.flags.job, видно всем: NW2String nyrp.job, NW2Bool nyrp.onShift.
]]

NYRP.Jobs = NYRP.Jobs or {}
local J = NYRP.Jobs
J.List, J.Order = {}, {}

do
	local root = NYRP.Root .. "framework/jobs/"
	local files = file.Find(root .. "*.lua", "LUA")
	for i = 1, #files do
		local f = files[i]
		local id = string.gsub(f, "%.lua$", "")
		JOB = {}
		if SERVER then AddCSLuaFile(root .. f) end
		include(root .. f)
		local j = JOB
		JOB = nil
		if j and j.Name and not j.Disabled then
			j.id = id
			j.Color = j.Color or Color(247, 198, 0)
			J.List[id] = j
			J.Order[#J.Order + 1] = id
		end
	end
	table.sort(J.Order, function(a, b)
		local ca, cb = J.List[a].Criminal and 1 or 0, J.List[b].Criminal and 1 or 0
		if ca ~= cb then return ca < cb end
		return J.List[a].Name < J.List[b].Name
	end)
end

function J.Of(ply) return J.List[ply:GetNW2String("nyrp.job", "")] end
function J.Wanted(ply) return ply:GetNW2Float("nyrp.wantedUntil", 0) > CurTime() end
