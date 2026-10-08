--[[
	Банкомат. E — вставить карту (нужна банковская карта в сумке). Банк задаёт вывеску и цвета экрана;
	в банкомате чужого банка снятие — с комиссией. Ставит админ: nyrp_spawnatm [банк] или спавн-меню,
	банк меняется через C-меню. Сеанс и меню — modules/bank/cl_atm.lua.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Банкомат"
ENT.Category = "New-York Roleplay"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "Bank")
	self:NetworkVar("Entity", 0, "User")
end

if SERVER then
	function ENT:Initialize()
		self:SetModel("models/nyrp/atm/atm.mdl")
		-- модель в чертёжных размерах — в игре увеличиваем до реального роста, коллизию тоже
		local K = NYRP.Bank.ATM.K
		self:SetModelScale(K, 0)
		local mn, mx = self:GetModelBounds()
		self:PhysicsInitBox(mn * K, mx * K)
		self:SetCollisionBounds(mn * K, mx * K)
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)
		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:EnableMotion(false) end
		if self:GetBank() == "" then self:SetBank("liberty") end
	end

	function ENT:SpawnFunction(ply, tr, class)
		if not tr.Hit then return end
		local e = NYRP.Bank.SpawnATM(tr.HitPos, Angle(0, ply:EyeAngles().y + 180, 0), "liberty")
		timer.Simple(0, function() if IsValid(e) then NYRP.Bank.SaveATMs() end end)
		return e
	end

	function ENT:Use(ply)
		if IsValid(ply) and ply:IsPlayer() then NYRP.Bank.StartATM(ply, self) end
	end

	function ENT:OnRemove()
		local user = self:GetUser()
		if IsValid(user) and NYRP.Bank.EndATM then NYRP.Bank.EndATM(user) end
		if not NYRP.Bank.Loading then timer.Simple(0, function() NYRP.Bank.SaveATMs() end) end
	end
end

-- C-меню: банк банкомата
properties.Add("nyrp_atm_bank", {
	MenuLabel = "Банк банкомата", Order = 1, MenuIcon = "icon16/money.png",
	Filter = function(self, ent, ply) return IsValid(ent) and ent:GetClass() == "nyrp_atm" and ply:IsSuperAdmin() end,
	MenuOpen = function(self, option, ent)
		local sub = option:AddSubMenu()
		for _, id in ipairs(NYRP.Bank.Order) do
			sub:AddOption(NYRP.Bank.Banks[id].name, function()
				self:MsgStart()
				net.WriteEntity(ent)
				net.WriteString(id)
				self:MsgEnd()
			end)
		end
	end,
	Action = function() end,
	Receive = function(self, len, ply)
		local ent, id = net.ReadEntity(), net.ReadString()
		if not IsValid(ent) or ent:GetClass() ~= "nyrp_atm" or not ply:IsSuperAdmin() or not NYRP.Bank.Banks[id] then return end
		ent:SetBank(id)
		NYRP.Bank.SaveATMs()
	end,
})

if CLIENT then
	function ENT:Initialize()
		local K = NYRP.Bank.ATM.K
		local mn, mx = self:GetModelBounds()
		self:SetRenderBounds(mn * K - Vector(4, 4, 4), mx * K + Vector(4, 4, 4))
	end

	function ENT:Draw()
		if self:GetModelScale() ~= NYRP.Bank.ATM.K then self:SetModelScale(NYRP.Bank.ATM.K, 0) end
		self:DrawModel()
	end

	function ENT:DrawTranslucent()
		local B = NYRP.Bank
		local bank = B.Banks[self:GetBank()] or B.Banks.liberty
		local dist = EyePos():DistToSqr(self:GetPos())
		if dist > 1600 * 1600 then return end
		-- вывеска: название банка с двух сторон короба (чуть впереди граней — без мерцания)
		local G = B.ATM
		local backX = -1 * G.K - 0.15
		for _, side in ipairs({ 1, -1 }) do
			local pos = self:LocalToWorld(Vector(side == 1 and G.topperX or backX, side * -G.topperY, G.topperTop))
			local ang = self:LocalToWorldAngles(Angle(0, side == 1 and 90 or -90, 90))
			cam.Start3D2D(pos, ang, G.topperY * 2 / 500)
			draw.RoundedBox(0, 0, 0, 500, 200, bank.color)
			surface.SetDrawColor(255, 255, 255, 30)
			surface.DrawRect(0, 0, 500, 6)
			draw.SimpleText(bank.short, NYRP.FontRaw("title", 96), 250, 84, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			draw.SimpleText("ATM · 24/7", NYRP.FontRaw("bold", 30), 250, 160, Color(255, 255, 255, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			cam.End3D2D()
		end
		-- экран (меню своего сеанса рисует cl_atm.lua)
		if B.DrawScreen then B.DrawScreen(self) end
	end
end
