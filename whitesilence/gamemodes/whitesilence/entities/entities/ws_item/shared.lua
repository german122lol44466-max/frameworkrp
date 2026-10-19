--[[
	ws_item — предмет инвентаря на земле (бинт, аптечка, патроны...). E — подобрать в рюкзак.
	Модель — своя сетка предмета (WS.Inv.Items[id].mesh).
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
	self:NetworkVar("String", 0, "ItemId")
	self:NetworkVar("Int", 0, "Count")
	self:NetworkVar("Int", 1, "Charges")
end

function ENT:MeshId()
	local d = WS.Inv.Def(self:GetItemId())
	return d and d.mesh
end

function ENT:Initialize()
	local def = WS.Props.Defs[self:MeshId() or ""]
	local mins = def and def.mins or Vector(-3, -3, 0)
	local maxs = def and def.maxs or Vector(3, 3, 4)
	if SERVER then
		self:SetModel(HIDDEN)
		self:PhysicsInitBox(mins, maxs)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
		self:SetUseType(SIMPLE_USE)
		self:DrawShadow(false)
		local ph = self:GetPhysicsObject()
		if IsValid(ph) then ph:SetMass(math.max(def and def.mass or 1, 0.2)) ph:SetMaterial("cardboard") ph:Wake() end
	end
	self:SetCollisionBounds(mins, maxs)
	if CLIENT then self:SetRenderBounds(mins, maxs) end
end

if SERVER then
	function ENT:Use(activator)
		if IsValid(activator) and activator:IsPlayer() then WS.Inv.Pickup(activator, self) end
	end
	return
end

function ENT:Draw()
	if not WS.Props.Draw(self, self:MeshId()) then self:DrawModel() end
end

function ENT:OnRemove() WS.Props.Release(self) end
