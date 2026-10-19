--[[
	ws_crate — ящик снабжения: удерживать E — открыть, из него выпадают патроны и медицина.
	Открытый ящик остаётся пустым. Ставит сюжет у чекпоинтов (sv_story.lua) и редактор.
]]
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "ws_prop"
ENT.PrintName = "Ящик снабжения"
ENT.Author = "John Make"
ENT.Spawnable = false

ENT.Contents = {
	{ "ammo_rifle", 90, 120 }, { "ammo_rifle", 60, 90 }, { "ammo_pistol", 30, 50 },
	{ "bandage", 2, 3 }, { "medkit", 1, 1 }, { "painkillers", 1, 2 }, { "battery", 1, 1 },
}

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "MeshId")
	self:NetworkVar("Bool", 0, "Opened")
end

if SERVER then
	function ENT:Initialize()
		self:SetMeshId("crate")
		self.wsStatic = true
		self.BaseClass.Initialize(self)
		self:SetUseType(CONTINUOUS_USE)
	end

	function ENT:Use(ply)
		if self:GetOpened() or not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end
		-- удержание: 1.2 с непрерывного E
		if not ply.wsCrate or ply.wsCrate.ent ~= self or CurTime() - ply.wsCrate.last > 0.25 then
			ply.wsCrate = { ent = self, t0 = CurTime() }
			net.Start("ws.hand") net.WriteString("interact") net.WriteVector(self:WorldSpaceCenter()) net.WriteFloat(1.4) net.Send(ply)
		end
		ply.wsCrate.last = CurTime()
		ply:SetNW2Float("ws_use", math.min((CurTime() - ply.wsCrate.t0) / 1.2, 1))
		ply:SetNW2String("ws_use_label", "Открыть ящик")
		if CurTime() - ply.wsCrate.t0 < 1.2 then return end
		ply.wsCrate = nil
		ply:SetNW2Float("ws_use", 0)
		self:SetOpened(true)
		self:EmitSound("items/ammocrate_open.wav", 70)
		local top = self:WorldSpaceCenter() + Vector(0, 0, 14)
		for i, c in ipairs(self.Contents) do
			local e = ents.Create("ws_item")
			if IsValid(e) then
				e:SetItemId(c[1])
				e:SetCount(math.random(c[2], c[3]))
				e:SetPos(top + Vector(math.cos(i) * 10, math.sin(i) * 10, i * 2))
				e:Spawn()
				local ph = e:GetPhysicsObject()
				if IsValid(ph) then ph:SetVelocity(Vector(math.cos(i) * 60, math.sin(i) * 60, 120)) end
			end
		end
		hook.Run("WSCrateOpened", ply, self)
	end
	return
end

function ENT:Draw()
	if not WS.Props.Draw(self, "crate") then self:DrawModel() end
	-- открытый — крышка снята: рисуем сетку чуть темнее (подсказка издалека)
end
