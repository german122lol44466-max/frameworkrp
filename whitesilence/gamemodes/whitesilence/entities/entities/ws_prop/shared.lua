--[[
	ws_prop — предмет со своей моделью (сетка из tools/content/props.py), физика — по габаритам сетки.
	ent:SetMeshId("radio") до Spawn(); ent.wsStatic = true — не двигается (сюжетные объекты).
]]
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Предмет"
ENT.Author = "John Make"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_OPAQUE

local HIDDEN = "models/hunter/blocks/cube025x025x025.mdl"

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "MeshId")
end

local function def(self)
	return WS.Props and WS.Props.Defs and WS.Props.Defs[self:GetMeshId()]
end

function ENT:Initialize()
	local d = def(self)
	local mins = d and d.mins or Vector(-4, -4, 0)
	local maxs = d and d.maxs or Vector(4, 4, 8)
	if SERVER then
		self:SetModel(HIDDEN)
		self:PhysicsInitBox(mins, maxs)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetMoveType(self.wsStatic and MOVETYPE_NONE or MOVETYPE_VPHYSICS)
		self:SetUseType(SIMPLE_USE)
		self:DrawShadow(false)
		local ph = self:GetPhysicsObject()
		if IsValid(ph) then
			ph:SetMass(math.Clamp(d and d.mass or 2, 0.1, 5000))
			ph:SetMaterial(d and d.mass and d.mass > 20 and "metal" or "cardboard")
			if self.wsStatic then ph:EnableMotion(false) else ph:Wake() end
		end
	end
	self:SetCollisionBounds(mins, maxs)
	if CLIENT then self:SetRenderBounds(mins, maxs) end
end

if CLIENT then
	function ENT:Draw()
		if not WS.Props.Draw(self, self:GetMeshId()) then self:DrawModel() end
	end

	function ENT:OnRemove()
		WS.Props.Release(self)
	end
end
