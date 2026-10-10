--[[
	Позы на сервере: проверки (жив, на земле, не сидит, не в наручниках, не без сознания, не в воде),
	поиск стены за спиной, фиксация корпуса, руки (кости), выход по движению/прыжку, /act, /acts.
]]

local A = NYRP.Acts

local function viewOf(ply) return ply.nyrpActView or ply:GetViewOffset() end

-- Стена за спиной: луч назад от пояса. Возвращает точку, куда встать, и направление «от стены».
local function wallBehind(ply)
	local center = ply:GetPos() + Vector(0, 0, 36)
	local back = -Angle(0, ply:EyeAngles().y, 0):Forward()
	local tr = util.TraceLine({ start = center, endpos = center + back * 48, filter = ply, mask = MASK_SOLID })
	if not tr.Hit or tr.HitSky or math.abs(tr.HitNormal.z) > 0.4 then return end
	local n = Vector(tr.HitNormal.x, tr.HitNormal.y, 0):GetNormalized()
	local pos = Vector(tr.HitPos.x, tr.HitPos.y, ply:GetPos().z) + n * 17
	-- место свободно?
	local mins, maxs = ply:GetHull()
	local hull = util.TraceHull({ start = pos + Vector(0, 0, 2), endpos = pos + Vector(0, 0, 2), mins = mins, maxs = maxs, filter = ply, mask = MASK_PLAYERSOLID })
	if hull.Hit then pos = nil end
	return pos, n:Angle().y
end

local function setBones(ply, key, on)
	local t = key and A.Bones[key]
	if not t then return end
	for name, ang in pairs(t) do
		local b = ply:LookupBone(name)
		if b then ply:ManipulateBoneAngles(b, on and ang or angle_zero) end
	end
end

function A.CanEnter(ply)
	if not ply:Alive() or not NYRP.HasCharacter(ply) then return false, "Сейчас нельзя" end
	if ply:InVehicle() then return false, "Нельзя в машине" end
	if not ply:OnGround() then return false, "Встаньте на землю" end
	if ply:WaterLevel() > 1 then return false, "Нельзя в воде" end
	if NYRP.Sit and NYRP.Sit.Sitting(ply) then return false, "Сначала встаньте (Пробел)" end
	if NYRP.Cond and NYRP.Cond.KO(ply) then return false, "Вы без сознания" end
	if NYRP.Factions and NYRP.Factions.Cuffed and NYRP.Factions.Cuffed(ply) then return false, "Руки скованы наручниками" end
	if ply.nyrpAction then return false, "Вы заняты" end
	return true
end

function A.Leave(ply, quiet)
	local a = A.Current(ply)
	if not a and not ply.nyrpAct then return end
	local d = ply.nyrpAct
	ply.nyrpAct = nil
	ply:SetNW2Int("nyrp.act", 0)
	ply:SetNW2Bool("nyrp.actWall", false)
	if d then
		setBones(ply, d.bones, false)
		if d.view then ply:SetViewOffset(d.view) end
	end
	if not quiet and ply:Alive() then
		ply:EmitSound("physics/cardboard/cardboard_box_impact_soft" .. math.random(1, 7) .. ".wav", 40, 110, 0.3)
	end
end

function A.Enter(ply, a)
	if not a then return end
	if A.Current(ply) == a then A.Leave(ply) return end
	local ok, why = A.CanEnter(ply)
	if not ok then NYRP.Notify(ply, why, "warning", 2) return end
	if (ply.nyrpActNext or 0) > CurTime() then return end
	ply.nyrpActNext = CurTime() + 0.8

	local onWall, pos, yaw = false, nil, ply:EyeAngles().y
	if a.wall then
		local p, wy = wallBehind(ply)
		if p then
			onWall, pos, yaw = true, p, wy
		elseif a.wall == "back" then
			NYRP.Notify(ply, "Встаньте спиной к стене", "warning", 2)
			return
		end
	end
	if A.Sequence(ply, a, onWall) < 0 then
		NYRP.Notify(ply, "Эта поза недоступна для вашей модели", "warning", 3)
		return
	end

	if A.Current(ply) then A.Leave(ply, true) end
	-- поза — с пустыми руками
	if ply:HasWeapon("nyrp_hands") then ply:SelectWeapon("nyrp_hands") end
	if pos then ply:SetPos(pos) end
	ply:SetVelocity(-ply:GetVelocity())
	local view = ply:GetViewOffset()
	ply.nyrpAct = { id = a.id, bones = a.bones, view = view, at = CurTime() }
	ply:SetNW2Int("nyrp.act", a.index)
	ply:SetNW2Bool("nyrp.actWall", onWall)
	ply:SetNW2Float("nyrp.actYaw", yaw)
	local mul = (onWall and a.wallView) or a.view
	if mul then ply:SetViewOffset(Vector(0, 0, view.z * mul)) end
	setBones(ply, a.bones, true)
	ply:EmitSound("nyrp/fx/cloth.wav", 45, math.random(95, 105), 0.5)
end

-- Выход: пошёл, прыгнул, присел. Небольшая задержка, чтобы не выйти той же клавишей.
hook.Add("StartCommand", "nyrp.acts.leave", function(ply, cmd)
	local d = ply.nyrpAct
	if not d or CurTime() - d.at < 0.5 then return end
	if cmd:KeyDown(IN_JUMP) or cmd:KeyDown(IN_FORWARD) or cmd:KeyDown(IN_BACK) or cmd:KeyDown(IN_MOVELEFT)
		or cmd:KeyDown(IN_MOVERIGHT) or cmd:KeyDown(IN_DUCK) or (cmd:KeyDown(IN_USE) and cmd:KeyDown(IN_WALK)) then
		A.Leave(ply)
	end
end)

hook.Add("PlayerDeath", "nyrp.acts", function(ply) A.Leave(ply, true) end)
hook.Add("PlayerSpawn", "nyrp.acts", function(ply) A.Leave(ply, true) end)
hook.Add("PlayerEnteredVehicle", "nyrp.acts", function(ply) A.Leave(ply, true) end)
hook.Add("PlayerSwitchWeapon", "nyrp.acts", function(ply, old, new)
	if ply.nyrpAct and IsValid(new) and new:GetClass() ~= "nyrp_hands" then return true end
end)

-- без сознания, сел, надели наручники, сдвинули — выходим
timer.Create("nyrp.acts.check", 0.5, 0, function()
	for _, ply in pairs(player.GetAll()) do
		if ply.nyrpAct then
			local cuffed = NYRP.Factions and NYRP.Factions.Cuffed and NYRP.Factions.Cuffed(ply)
			if not ply:Alive() or (NYRP.Cond and NYRP.Cond.KO(ply)) or cuffed or (NYRP.Sit and NYRP.Sit.Sitting(ply))
				or not ply:OnGround() or ply:InVehicle() then
				A.Leave(ply, true)
			end
		end
	end
end)

local function actCmd(ply, raw)
	local arg = string.match(raw, "^%S+%s+(.+)$")
	if not arg or string.Trim(arg) == "" then
		if A.Current(ply) then A.Leave(ply) else
			net.Start("nyrp.acts.menu")
			net.Send(ply)
		end
		return
	end
	local a = A.Find(arg)
	if not a then
		local names = {}
		for _, x in ipairs(A.List) do names[#names + 1] = x.name end
		NYRP.Notify(ply, "Нет такой позы. Есть: " .. table.concat(names, ", "), "info", 10)
		return
	end
	A.Enter(ply, a)
end
NYRP.Chat.AddCommand("/act", actCmd)
NYRP.Chat.AddCommand("/поза", actCmd)

local function menuCmd(ply)
	net.Start("nyrp.acts.menu")
	net.Send(ply)
end
NYRP.Chat.AddCommand("/acts", menuCmd)
NYRP.Chat.AddCommand("/позы", menuCmd)

net.Receive("nyrp.acts.do", function(_, ply)
	local i = net.ReadUInt(8)
	if i == 0 then A.Leave(ply) return end
	A.Enter(ply, A.List[i])
end)
