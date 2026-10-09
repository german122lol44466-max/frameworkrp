--[[
	Сигарета во рту: у других — модель у губ (кость головы), у себя от первого лица — внизу по центру кадра.
	Горящая — тлеющий кончик и дым при выдохе.
]]

local S = NYRP.Smoking
local glow = Material("sprites/light_glow02_add")
local cigModels = {}

local function cigModel(ply)
	local m = cigModels[ply]
	if not IsValid(m) then
		m = ClientsideModel("models/nyrp/props/w_cigarette.mdl", RENDERGROUP_OPAQUE)
		if not IsValid(m) then return end
		m:SetNoDraw(true)
		cigModels[ply] = m
	end
	return m
end

-- рот относительно кости головы ValveBiped (X — вверх по шее, Y — вперёд от лица)
local function mouthPose(ply)
	-- у моделей HL2 есть точка «mouth»: Forward — изо рта наружу
	local att = ply:LookupAttachment("mouth")
	if att and att > 0 then
		local a = ply:GetAttachment(att)
		if a then
			local ang = a.Ang
			ang:RotateAroundAxis(ang:Right(), -12)       -- чуть вниз, как держат сигарету
			return a.Pos + a.Ang:Forward() * 0.2, ang
		end
	end
	local b = ply:LookupBone("ValveBiped.Bip01_Head1")
	if not b then return end
	local m = ply:GetBoneMatrix(b)
	if not m then return end
	local hp, ha = m:GetTranslation(), m:GetAngles()
	local pos = hp + ha:Forward() * 1.2 + ha:Right() * -5.6 + ha:Up() * 0.6
	local fwd = (ha:Right() * -1 + ha:Forward() * -0.25):GetNormalized()
	local ang = fwd:Angle()
	return pos, ang
end

local function drawEmber(pos, size)
	render.SetMaterial(glow)
	local f = 0.75 + 0.25 * math.sin(RealTime() * 7 + pos.x)
	render.DrawSprite(pos, size * f, size * f, Color(255, 120, 40, 230))
end

hook.Add("PostPlayerDraw", "nyrp.smoking", function(ply)
	if S.State(ply) == 0 or not ply:Alive() then return end
	if ply == LocalPlayer() and not (NYRP.Camera and NYRP.Camera.IsThirdPerson and NYRP.Camera.IsThirdPerson()) then return end
	local pos, ang = mouthPose(ply)
	if not pos then return end
	local m = cigModel(ply)
	if not IsValid(m) then return end
	m:SetRenderOrigin(pos)
	m:SetRenderAngles(ang)
	m:SetupBones()
	m:DrawModel()
	if S.Lit(ply) then drawEmber(pos + ang:Forward() * 3.2, 2.2) end
end)

-- от первого лица: сигарета торчит снизу по центру кадра
hook.Add("HUDPaintBackground", "nyrp.smoking.fp", function()
	local ply = LocalPlayer()
	if not IsValid(ply) or S.State(ply) == 0 or not ply:Alive() then return end
	if NYRP.Camera and NYRP.Camera.IsThirdPerson and NYRP.Camera.IsThirdPerson() then return end
	local m = cigModel(ply)
	if not IsValid(m) then return end
	local eye, view = EyePos(), EyeAngles()
	local base = eye + view:Forward() * 2.6 - view:Up() * 3.0 + view:Right() * 0.4
	local ang = Angle(view.p + 14, view.y - 4, view.r)
	cam.Start3D(eye, view, 62, nil, nil, nil, nil, 0.5, 100)
	render.SuppressEngineLighting(true)
	render.ResetModelLighting(0.5, 0.5, 0.52)
	render.SetModelLighting(BOX_TOP, 0.9, 0.88, 0.85)
	m:SetRenderOrigin(base)
	m:SetRenderAngles(ang)
	m:SetupBones()
	m:DrawModel()
	render.SuppressEngineLighting(false)
	if S.Lit(ply) then drawEmber(base + ang:Forward() * 3.2, 1.6) end
	cam.End3D()
end)

-- дым при выдохе
net.Receive("nyrp.smoke.puff", function()
	local ply = net.ReadEntity()
	if not IsValid(ply) then return end
	local pos, ang = mouthPose(ply)
	if not pos then return end
	if ply == LocalPlayer() and not (NYRP.Camera and NYRP.Camera.IsThirdPerson and NYRP.Camera.IsThirdPerson()) then
		pos, ang = EyePos() + EyeAngles():Forward() * 6 - EyeAngles():Up() * 3, EyeAngles()
	end
	local em = ParticleEmitter(pos)
	if not em then return end
	for i = 1, 14 do
		local p = em:Add("particle/smokesprites_000" .. math.random(1, 9), pos + VectorRand() * 0.5)
		if p then
			p:SetVelocity(ang:Forward() * math.Rand(10, 22) + VectorRand() * 4 + Vector(0, 0, 6))
			p:SetDieTime(math.Rand(1.6, 2.6))
			p:SetStartAlpha(70)
			p:SetEndAlpha(0)
			p:SetStartSize(1.5)
			p:SetEndSize(math.Rand(10, 16))
			p:SetRoll(math.Rand(0, 360))
			p:SetRollDelta(math.Rand(-1, 1))
			p:SetColor(210, 210, 214)
			p:SetAirResistance(40)
			p:SetGravity(Vector(0, 0, 8))
		end
	end
	em:Finish()
end)

hook.Add("EntityRemoved", "nyrp.smoking", function(ent)
	if cigModels[ent] then
		if IsValid(cigModels[ent]) then cigModels[ent]:Remove() end
		cigModels[ent] = nil
	end
end)
