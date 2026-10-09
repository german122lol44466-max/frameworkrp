--[[
	Зажигалка в руке (слот «В руке»). ЛКМ — поднести ко рту и чиркнуть: если во рту сигарета — она загорится.
	Газ ограничен (предмет «Зажигалка», 40 раз).
]]

AddCSLuaFile()

SWEP.Base = "nyrp_handheld"
SWEP.PrintName = "Зажигалка"
SWEP.Instructions = "ЛКМ — поджечь сигарету во рту"
SWEP.Slot = 4
SWEP.SlotPos = 3
SWEP.ViewModel = "models/nyrp/props/v_lighter.mdl"
SWEP.WorldModel = "models/nyrp/props/w_lighter.mdl"
SWEP.HoldType = "slam"
SWEP.WMOffset = { pos = Vector(3.0, -1.4, -0.4), ang = Angle(0, -90, -90) }

-- кадры анимации use (30 к/с): чирк на 18 и 30, пламя с 30 по 44
local FLICK1, FLICK2, FLAME_END = 18 / 30, 30 / 30, 44 / 30

function SWEP:PrimaryAttack()
	self:SetNextPrimaryFire(CurTime() + 1.9)
	if self.HolsterAt then return end
	self:PlaySeq("use")
	self.UseStart = CurTime()
	if SERVER then
		local ply = self:GetOwner()
		ply:SetNW2Float("nyrp.lighterT", CurTime())
		timer.Simple(FLICK1, function() if IsValid(ply) then ply:EmitSound("nyrp/fx/lighter_fail.wav", 50) end end)
		timer.Simple(FLICK2, function()
			if not IsValid(ply) or not IsValid(self) or ply:GetActiveWeapon() ~= self then return end
			if not NYRP.Smoking.UseLighter(ply) then return end
			ply:EmitSound("nyrp/fx/lighter.wav", 55)
			if NYRP.Smoking.Light(ply) then
				timer.Simple(0.5, function() if IsValid(ply) then ply:EmitSound("nyrp/fx/smoke_inhale.wav", 50, 100, 0.7) end end)
			end
		end)
	end
end

function SWEP:SecondaryAttack() end

if CLIENT then
	local glow = Material("sprites/light_glow02_add")
	local function flame(pos, s)
		render.SetMaterial(glow)
		local f = 0.85 + 0.15 * math.sin(RealTime() * 30)
		render.DrawSprite(pos + Vector(0, 0, 0.5), 2.4 * s * f, 4.2 * s * f, Color(255, 170, 60, 255))
		render.DrawSprite(pos + Vector(0, 0, 0.3), 1.0 * s, 1.8 * s, Color(120, 160, 255, 200))
	end

	local function lit(ply)
		local t = CurTime() - ply:GetNW2Float("nyrp.lighterT", -10)
		return t >= FLICK2 and t <= FLAME_END
	end

	-- пламя у вьюмодели (рисуется в её проходе, см. nyrp_handheld)
	function SWEP:DrawFPExtra(vm)
		local ply = self:GetOwner()
		if not IsValid(ply) or not lit(ply) then return end
		local b = vm:LookupBone("nyrp_lighter")
		local m = b and vm:GetBoneMatrix(b)
		if not m then return end
		flame(m:GetTranslation() + m:GetUp() * 1.75, 1)
	end

	hook.Add("PostDrawTranslucentRenderables", "nyrp.lighter", function(depth, sky)
		if depth or sky then return end
		for _, ply in ipairs(player.GetAll()) do
			local w = ply:GetActiveWeapon()
			if IsValid(w) and w:GetClass() == "nyrp_lighter" and lit(ply)
				and (ply ~= LocalPlayer() or (NYRP.Camera and NYRP.Camera.IsThirdPerson and NYRP.Camera.IsThirdPerson())) then
				local bone = ply:LookupBone("ValveBiped.Bip01_R_Hand")
				local m = bone and ply:GetBoneMatrix(bone)
				if m then
					local pos = LocalToWorld(Vector(3.0, -1.4, 1.6), Angle(), m:GetTranslation(), m:GetAngles())
					flame(pos, 1)
					local dl = DynamicLight(ply:EntIndex() + 4000)
					if dl then
						dl.pos, dl.r, dl.g, dl.b, dl.brightness, dl.size, dl.decay, dl.dietime = pos, 255, 160, 60, 1, 90, 400, CurTime() + 0.1
					end
				end
			end
		end
	end)
end
