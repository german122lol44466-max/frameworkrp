--[[
	Эффекты стрельбы: вспышка света у дула, дымок, отдача камеры (зависит от навыка и ранений),
	лёгкая тряска; у раненой руки — дрожание прицела. Надетая броня/каска видна на игроке.
]]

local CB = NYRP.Combat
local kick = Angle()
local kickVel = Angle()

local function muzzlePos(ply)
	local Cam = NYRP.Camera
	local fp = ply == LocalPlayer() and not (Cam and Cam.IsThirdPerson and Cam.IsThirdPerson())
	if fp then
		local vm = ply:GetViewModel()
		local att = IsValid(vm) and vm:LookupAttachment("muzzle") or 0
		local a = att > 0 and vm:GetAttachment(att)
		if a then return a.Pos, a.Ang end
		return EyePos() + EyeAngles():Forward() * 30 - EyeAngles():Up() * 4, EyeAngles()
	end
	local w = ply:GetActiveWeapon()
	local att = IsValid(w) and w:LookupAttachment("muzzle") or 0
	local a = att > 0 and w:GetAttachment(att)
	if a then return a.Pos, a.Ang end
	return ply:EyePos() + ply:GetAimVector() * 30, ply:EyeAngles()
end

local function flashAndSmoke(ply)
	local pos, ang = muzzlePos(ply)
	local dl = DynamicLight(ply:EntIndex() + 6000)
	if dl then
		dl.pos, dl.r, dl.g, dl.b = pos, 255, 190, 110
		dl.brightness, dl.size, dl.decay, dl.dietime = 3, 180, 2400, CurTime() + 0.06
	end
	local em = ParticleEmitter(pos)
	if not em then return end
	for i = 1, 4 do
		local p = em:Add("particle/smokesprites_000" .. math.random(1, 9), pos)
		if p then
			p:SetVelocity(ang:Forward() * math.Rand(20, 60) + VectorRand() * 8 + Vector(0, 0, 10))
			p:SetDieTime(math.Rand(0.8, 1.6))
			p:SetStartAlpha(55)
			p:SetEndAlpha(0)
			p:SetStartSize(2)
			p:SetEndSize(math.Rand(12, 20))
			p:SetRoll(math.Rand(0, 360))
			p:SetColor(200, 200, 205)
			p:SetAirResistance(80)
			p:SetGravity(Vector(0, 0, 12))
		end
	end
	em:Finish()
end

-- свой выстрел: отдача камеры
function CB.OnLocalFire(ply, data, f)
	local dmg = data.Damage or 10
	local power = math.Clamp(dmg / 12, 0.4, 2.5) * f
	kickVel.p = kickVel.p - 26 * power
	kickVel.y = kickVel.y + math.Rand(-9, 9) * power
	flashAndSmoke(ply)
	util.ScreenShake(EyePos(), 0.6 * power, 18, 0.12, 50)
end

-- чужие выстрелы: вспышка и дымок
hook.Add("EntityFireBullets", "nyrp.combat.fx", function(ent)
	if CLIENT and IsValid(ent) and ent:IsPlayer() and ent ~= LocalPlayer() and IsFirstTimePredicted() then flashAndSmoke(ent) end
end)

hook.Add("NYRP.CalcView", "nyrp.combat", function(ply, origin, angles, fov)
	local dt = FrameTime()
	-- пружина: отдача возвращается
	kickVel = kickVel - kick * 90 * dt - kickVel * 12 * dt
	kick = kick + kickVel * dt
	local shake = Angle()
	if CB.Wound(ply, "arm") then
		local t = RealTime()
		shake = Angle(math.sin(t * 7.3) * 0.35, math.sin(t * 5.1 + 1) * 0.35, 0)
	end
	if math.abs(kick.p) + math.abs(kick.y) + math.abs(shake.p) < 0.001 then return end
	angles:Add(kick + shake)
end)

-- --------------------------------------------------------------- надетая броня --
-- ITEM.Wear = { Follow = "body" | "head", Pos = Vector, Ang = Angle, Scale = 1, Model = "..." }
local wearModels = {}

local function wearModel(ply, id, mdl)
	wearModels[ply] = wearModels[ply] or {}
	local m = wearModels[ply][id]
	if not IsValid(m) then
		m = ClientsideModel(mdl, RENDERGROUP_OPAQUE)
		if not IsValid(m) then return end
		m:SetNoDraw(true)
		wearModels[ply][id] = m
	end
	return m
end

hook.Add("PostPlayerDraw", "nyrp.combat.wear", function(ply)
	local list = ply:GetNW2String("nyrp.wear", "")
	if list == "" or not ply:Alive() then return end
	local fp = ply == LocalPlayer() and not (NYRP.Camera and NYRP.Camera.IsThirdPerson and NYRP.Camera.IsThirdPerson())
	for id in string.gmatch(list, "[^,]+") do
		local def = NYRP.Items.Get(id)
		local w = def and def.wear
		local head = w and w.Follow == "head"
		if w and not (fp and head) then
			local b = ply:LookupBone(head and "ValveBiped.Bip01_Head1" or "ValveBiped.Bip01_Spine2")
			local mtx = b and ply:GetBoneMatrix(b)
			local m = mtx and wearModel(ply, id, w.Model or def.model)
			if m then
				-- ориентация: корпус — по повороту тела, голова — по взгляду (кости ValveBiped повёрнуты по-разному у моделей)
				local base
				if head then
					local e = ply:EyeAngles()
					base = Angle(math.Clamp(e.p, -50, 50) * 0.7, e.y, 0)
				else
					base = Angle(0, ply:GetRenderAngles().y, 0)
				end
				local pos, ang = LocalToWorld(w.Pos or vector_origin, w.Ang or angle_zero, mtx:GetTranslation(), base)
				m:SetRenderOrigin(pos)
				m:SetRenderAngles(ang)
				if w.Scale and m:GetModelScale() ~= w.Scale then m:SetModelScale(w.Scale, 0) end
				m:SetupBones()
				m:DrawModel()
			end
		end
	end
end)

hook.Add("EntityRemoved", "nyrp.combat.wear", function(ent)
	for _, m in pairs(wearModels[ent] or {}) do if IsValid(m) then m:Remove() end end
	wearModels[ent] = nil
end)
