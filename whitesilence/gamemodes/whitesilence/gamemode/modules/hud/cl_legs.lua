--[[
	Ноги от первого лица — по мотивам плагина «Legs» (Valkyrie & blackops7799, public domain / Unlicense).
	Копия модели игрока рисуется чуть позади камеры, верхняя часть тела (голова, руки, грудь) убрана масштабом костей,
	анимация повторяет анимацию игрока. Переписано без Helix: настройки — ws_legs, ws_legs_vehicle.
]]

local enabled = CreateClientConVar("ws_legs", "1", true, false, "Показывать свои ноги от первого лица")
local inVehicle = CreateClientConVar("ws_legs_vehicle", "1", true, false, "Показывать ноги в транспорте")

local Legs = { PlaybackRate = 1, Velocity = 0, BonesToRemove = {}, ClipVector = vector_up * -1, ForwardOffset = -22 }
WS.Legs = Legs

local function hideVehicle()
	if LocalPlayer():InVehicle() then
		return enabled:GetBool() and not inVehicle:GetBool()
	end
	return false
end

local function shouldDraw()
	if hook.Run("ShouldDisableLegs") == true or not enabled:GetBool() then return false end
	local client = LocalPlayer()
	return IsValid(Legs.LegEnt) and client:Alive() and WS.Lobby.InGame(client) and not hideVehicle()
		and GetViewEntity() == client and not client:ShouldDrawLocalPlayer() and not IsValid(client:GetObserverTarget())
		and not client:GetNoDraw()
end

function Legs:Setup(model)
	local client = LocalPlayer()
	model = model or client:GetModel()
	if not IsValid(self.LegEnt) then
		self.LegEnt = ClientsideModel(model, RENDERGROUP_OPAQUE)
	else
		self.LegEnt:SetModel(model)
	end
	if not IsValid(self.LegEnt) then return end
	self.LegEnt:SetNoDraw(true)
	for _, v in pairs(client:GetBodyGroups()) do
		self.LegEnt:SetBodygroup(v.id, client:GetBodygroup(v.id))
	end
	for k in ipairs(client:GetMaterials()) do
		self.LegEnt:SetSubMaterial(k - 1, client:GetSubMaterial(k - 1))
	end
	self.LegEnt:SetSkin(client:GetSkin())
	self.LegEnt:SetMaterial(client:GetMaterial())
	self.LegEnt:SetColor(client:GetColor())
	self.LegEnt.GetPlayerColor = function() return LocalPlayer():GetPlayerColor() end
	self.LegEnt.Anim = nil
	self.LegEnt.LastTick = 0
	self.Model = model
	self:FixBones()
	self:Update(0)
end

function Legs:Update(maxSeqGroundSpeed)
	if not IsValid(self.LegEnt) then return end
	local client = LocalPlayer()
	self.Velocity = client:GetVelocity():Length2D()
	self.PlaybackRate = 1
	if self.Velocity > 0.5 then
		if maxSeqGroundSpeed < 0.001 then
			self.PlaybackRate = 0.01
		else
			self.PlaybackRate = math.Clamp(self.Velocity / maxSeqGroundSpeed, 0.01, 10)
		end
	end
	self.LegEnt:SetPlaybackRate(self.PlaybackRate)
	local seq = client:GetSequence()
	if self.LegEnt.Anim ~= seq then
		self.LegEnt.Anim = seq
		self.LegEnt:ResetSequence(seq)
	end
	self.LegEnt:FrameAdvance(CurTime() - self.LegEnt.LastTick)
	self.LegEnt.LastTick = CurTime()
	-- дыхание чаще, когда устал
	local st = WS.Move and WS.Move.Stamina(client) / WS.Config.StaminaMax or 1
	self.LegEnt:SetPoseParameter("breathing", Lerp(1 - st, 0.5, 3))
	self.LegEnt:SetPoseParameter("move_x", client:GetPoseParameter("move_x") * 2 - 1)
	self.LegEnt:SetPoseParameter("move_y", client:GetPoseParameter("move_y") * 2 - 1)
	self.LegEnt:SetPoseParameter("move_yaw", client:GetPoseParameter("move_yaw") * 360 - 180)
	self.LegEnt:SetPoseParameter("body_yaw", client:GetPoseParameter("body_yaw") * 180 - 90)
	self.LegEnt:SetPoseParameter("spine_yaw", client:GetPoseParameter("spine_yaw") * 180 - 90)
	if client:InVehicle() then
		self.LegEnt:SetPoseParameter("vehicle_steer", client:GetVehicle():GetPoseParameter("vehicle_steer") * 2 - 1)
	end
end

local UPPER = {
	"ValveBiped.Bip01_Head1", "ValveBiped.Bip01_L_Hand", "ValveBiped.Bip01_L_Forearm", "ValveBiped.Bip01_L_Upperarm",
	"ValveBiped.Bip01_L_Clavicle", "ValveBiped.Bip01_R_Hand", "ValveBiped.Bip01_R_Forearm", "ValveBiped.Bip01_R_Upperarm",
	"ValveBiped.Bip01_R_Clavicle", "ValveBiped.Bip01_Spine4", "ValveBiped.Bip01_Spine2",
}
for _, side in ipairs({ "L", "R" }) do
	for f = 0, 4 do
		for _, n in ipairs({ "", "1", "2" }) do
			UPPER[#UPPER + 1] = "ValveBiped.Bip01_" .. side .. "_Finger" .. f .. n
		end
	end
end

function Legs:FixBones()
	if not IsValid(self.LegEnt) then return end
	for i = 0, self.LegEnt:GetBoneCount() do
		self.LegEnt:ManipulateBoneScale(i, Vector(1, 1, 1))
		self.LegEnt:ManipulateBonePosition(i, vector_origin)
	end
	local list = LocalPlayer():InVehicle() and { "ValveBiped.Bip01_Head1" } or UPPER
	for _, v in ipairs(list) do
		local bone = self.LegEnt:LookupBone(v)
		if bone then
			self.LegEnt:ManipulateBoneScale(bone, vector_origin)
			if not LocalPlayer():InVehicle() then
				self.LegEnt:ManipulateBonePosition(bone, Vector(0, -100, 0))
				self.LegEnt:ManipulateBoneAngles(bone, angle_zero)
			end
		end
	end
end

function Legs:Render()
	cam.Start3D(EyePos(), EyeAngles())
	if shouldDraw() then
		local client = LocalPlayer()
		local pos = client:GetPos()
		local ang
		if client:InVehicle() then
			ang = client:GetVehicle():GetAngles()
			ang:RotateAroundAxis(ang:Up(), 90)
		else
			local eye = client:EyeAngles()
			ang = Angle(0, eye.y, 0)
			local rad = math.rad(eye.y)
			pos.x = pos.x + math.cos(rad) * self.ForwardOffset
			pos.y = pos.y + math.sin(rad) * self.ForwardOffset
			if client:GetGroundEntity() == NULL then
				pos.z = pos.z + 8
				if client:KeyDown(IN_DUCK) then pos.z = pos.z - 28 end
			end
		end
		local col = client:GetColor()
		local clip = render.EnableClipping(true)
		render.PushCustomClipPlane(self.ClipVector, self.ClipVector:Dot(EyePos()))
		render.SetColorModulation(col.r / 255, col.g / 255, col.b / 255)
		render.SetBlend(col.a / 255)
		self.LegEnt:SetRenderOrigin(pos)
		self.LegEnt:SetRenderAngles(ang)
		self.LegEnt:SetupBones()
		self.LegEnt:DrawModel()
		self.LegEnt:SetRenderOrigin()
		self.LegEnt:SetRenderAngles()
		render.SetBlend(1)
		render.SetColorModulation(1, 1, 1)
		render.PopCustomClipPlane()
		render.EnableClipping(clip)
	end
	cam.End3D()
end

hook.Add("UpdateAnimation", "ws.legs", function(client, velocity, maxSeqGroundSpeed)
	if client ~= LocalPlayer() then return end
	if not IsValid(Legs.LegEnt) or Legs.Model ~= client:GetModel() then
		Legs:Setup()
	else
		Legs:Update(maxSeqGroundSpeed)
	end
end)

-- смена оружия или транспорта — заново убрать кости верха
local lastWep, lastVeh
hook.Add("Think", "ws.legs", function()
	local client = LocalPlayer()
	if not IsValid(client) or not IsValid(Legs.LegEnt) then return end
	local wep, veh = client:GetActiveWeapon(), client:InVehicle()
	if wep ~= lastWep or veh ~= lastVeh then
		lastWep, lastVeh = wep, veh
		Legs:FixBones()
	end
end)

hook.Add("PostDrawTranslucentRenderables", "ws.legs", function(depth, skybox)
	if skybox then return end
	local client = LocalPlayer()
	if IsValid(client) and not client:InVehicle() then Legs:Render() end
end)

hook.Add("RenderScreenspaceEffects", "ws.legs", function()
	local client = LocalPlayer()
	if IsValid(client) and client:InVehicle() then Legs:Render() end
end)
