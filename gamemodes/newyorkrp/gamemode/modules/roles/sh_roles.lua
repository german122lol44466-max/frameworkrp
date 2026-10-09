--[[
	Роли (фракции) из папки gamemode/framework/roles/ (см. framework/roles/README.md). У персонажа — c.flags.role,
	видна всем как NW2String nyrp.role.
]]

NYRP.Roles = NYRP.Roles or {}
local Roles = NYRP.Roles
Roles.List = {}
Roles.Order = {}

do
	local root = NYRP.Root .. "framework/roles/"
	local files = file.Find(root .. "*.lua", "LUA")
	for i = 1, #files do
		local f = files[i]
		local id = string.gsub(f, "%.lua$", "")
		ROLE = {}
		if SERVER then AddCSLuaFile(root .. f) end
		include(root .. f)
		local r = ROLE
		ROLE = nil
		if r and r.Name and not r.Disabled then
			r.id = id
			r.Color = r.Color or Color(200, 200, 200)
			Roles.List[id] = r
			Roles.Order[#Roles.Order + 1] = id
			if r.Default then Roles.Default = id end
		end
	end
	table.sort(Roles.Order, function(a, b) return (Roles.List[a].Default and 0 or 1) < (Roles.List[b].Default and 0 or 1) end)
	Roles.Default = Roles.Default or Roles.Order[1]
end

function Roles.Get(id) return Roles.List[id] or Roles.List[Roles.Default] end
function Roles.Of(ply) return Roles.Get(ply:GetNW2String("nyrp.role", Roles.Default or "")) end
