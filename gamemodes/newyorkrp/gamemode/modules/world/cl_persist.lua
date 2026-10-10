--[[
	Постоянные пропы — клиент: админ с физганом в руках видит их подсвеченными (голубой контур),
	тот, на который смотрит, — ярче.
]]

NYRP.World = NYRP.World or {}
local W = NYRP.World

local cache, nextScan = {}, 0
local colAll, colAim = Color(90, 170, 255), Color(170, 220, 255)

local function holdingPhysgun(me)
	local wep = me:GetActiveWeapon()
	return IsValid(wep) and wep:GetClass() == "weapon_physgun"
end

hook.Add("PreDrawHalos", "nyrp.persist", function()
	local me = LocalPlayer()
	if not IsValid(me) or not me:IsAdmin() or not me:Alive() or not holdingPhysgun(me) then return end
	if CurTime() >= nextScan then
		nextScan = CurTime() + 0.75
		cache = {}
		local eye = me:EyePos()
		for _, ent in ipairs(ents.FindInSphere(eye, 2500)) do
			if IsValid(ent) and ent:GetNW2Bool("nyrp.persist") then cache[#cache + 1] = ent end
		end
	end
	local aim = me:GetEyeTrace().Entity
	local list, focus = {}, nil
	for _, ent in ipairs(cache) do
		if IsValid(ent) then
			if ent == aim then focus = ent else list[#list + 1] = ent end
		end
	end
	if #list > 0 then halo.Add(list, colAll, 2, 2, 1, true, false) end
	if focus then halo.Add({ focus }, colAim, 4, 4, 2, true, true) end
end)
