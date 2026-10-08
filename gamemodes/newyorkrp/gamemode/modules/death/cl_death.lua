--[[
	Смерть: мягкая физика рэгдолла, камера сначала из глаз тела, потом медленно отъезжает,
	экран смерти с таймером и кнопкой «Возродиться», сердцебиение.
]]

local UI = NYRP.UI
local D = {}
NYRP.Death = D

-- Мягче падение: демпфирование вращения и скорости частей тела.
hook.Add("CreateClientsideRagdoll", "nyrp.death", function(ent, rag)
	if not IsValid(ent) or not ent:IsPlayer() then return end
	for i = 0, rag:GetPhysicsObjectCount() - 1 do
		local phys = rag:GetPhysicsObjectNum(i)
		if IsValid(phys) then
			phys:SetDamping(0.25, 4)
			phys:SetVelocity(phys:GetVelocity() * 0.85)
		end
	end
end)

local function deathTime() return LocalPlayer():GetNW2Float("nyrp.deathTime", 0) end

-- Камера смерти.
local camPos
hook.Add("NYRP.CalcView", "nyrp.death", function(ply, origin, angles, fov)
	if ply:Alive() or NYRP.State ~= "playing" then camPos = nil return end
	local rag = ply:GetRagdollEntity()
	if not IsValid(rag) then return end
	local t = CurTime() - deathTime()
	local att = rag:LookupAttachment("eyes")
	local eyes = att > 0 and rag:GetAttachment(att)
	local center = rag:GetPos()
	local bone = rag:LookupBone("ValveBiped.Bip01_Spine2")
	if bone then center = rag:GetBonePosition(bone) or center end
	if t < 2.2 and eyes then
		return { origin = eyes.Pos + eyes.Ang:Forward() * 3, angles = eyes.Ang, fov = fov, znear = 1, drawviewer = false }
	end
	local k = UI.EaseInOut(math.Clamp((t - 2.2) / 2.5, 0, 1))
	local yaw = t * 6
	local want = center + Angle(55, yaw, 0):Forward() * -110 * k + Vector(0, 0, 20 + 60 * k)
	local tr = util.TraceLine({ start = center + Vector(0, 0, 10), endpos = want, mask = MASK_SOLID_BRUSHONLY })
	camPos = tr.HitPos
	local from = eyes and eyes.Pos or center
	local pos = LerpVector(k, from, camPos)
	local ang = LerpAngle(k, eyes and eyes.Ang or angles, (center - pos):Angle())
	return { origin = pos, angles = ang, fov = fov, drawviewer = false }
end)

hook.Add("RenderScreenspaceEffects", "nyrp.death", function()
	if LocalPlayer():Alive() or NYRP.State ~= "playing" then return end
	local k = math.Clamp((CurTime() - deathTime()) / 2, 0, 1)
	DrawColorModify({
		["$pp_colour_addr"] = 0.03 * k, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
		["$pp_colour_brightness"] = -0.05 * k, ["$pp_colour_contrast"] = 1 + 0.1 * k,
		["$pp_colour_colour"] = 1 - 0.85 * k,
		["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
	})
end)

-- Экран смерти.
function D.Open()
	if IsValid(D.Panel) then return end
	local pnl = vgui.Create("EditablePanel")
	D.Panel = pnl
	pnl:SetSize(ScrW(), ScrH())
	pnl:MakePopup()
	pnl:SetKeyboardInputEnabled(false)
	pnl.Born = RealTime()
	pnl.NextBeat = RealTime() + 0.6
	pnl.Beat = 0
	pnl.Think = function(s)
		if LocalPlayer():Alive() then s:Remove() return end
		if RealTime() > s.NextBeat and s.Beat < 7 then
			s.Beat = s.Beat + 1
			s.NextBeat = RealTime() + 1.0 + s.Beat * 0.18
			surface.PlaySound("nyrp/fx/heartbeat.wav")
			s.Pulse = RealTime()
		end
	end
	pnl.Paint = function(s, w, h)
		local t = UI.Ease((RealTime() - s.Born) / 1.2)
		local pulse = s.Pulse and math.max(0, 1 - (RealTime() - s.Pulse) / 0.5) or 0
		UI.BlurPanel(s, 3 * t)
		surface.SetDrawColor(14, 2, 4, 150 * t)
		surface.DrawRect(0, 0, w, h)
		UI.Vignette(-UI.S(20) + pulse * UI.S(20), -UI.S(20) + pulse * UI.S(20), w + UI.S(40) - pulse * UI.S(40), h + UI.S(40) - pulse * UI.S(40), 255 * t)
		surface.SetMaterial(UI.Mat("vgui/gradient-u"))
		surface.SetDrawColor(80, 0, 6, 120 * t)
		surface.DrawTexturedRect(0, h * 0.5, w, h * 0.5)

		local shake = math.max(0, 1 - (RealTime() - s.Born) / 1.2) * UI.S(6)
		local sx, sy = math.Rand(-shake, shake), math.Rand(-shake, shake)
		draw.SimpleText("ВЫ ПОГИБЛИ", NYRP.Font("title", 92), w / 2 + sx, h * 0.38 + sy, Color(235, 228, 228, 255 * t), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		draw.SimpleText("Город не прощает ошибок. Кто-то найдёт вас на холодном асфальте Нью-Йорка...", NYRP.Font("regular", 18),
			w / 2, h * 0.38 + UI.S(66), Color(200, 180, 180, 200 * t), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

		local left = math.max(0, deathTime() + NYRP.Config.RespawnTime - CurTime())
		local frac = 1 - left / NYRP.Config.RespawnTime
		local cx, cy, r = w / 2, h * 0.6, UI.S(42)
		UI.Circle(cx, cy, r, Color(0, 0, 0, 120 * t))
		-- кольцо прогресса
		for i = 0, 59 do
			if i / 60 <= frac then
				local a = math.rad(-90 + i * 6)
				UI.Circle(cx + math.cos(a) * r, cy + math.sin(a) * r, UI.S(3), Color(214, 70, 64, 255 * t))
			end
		end
		UI.DrawIcon(left > 0 and "hourglass" or "heart", cx, cy - UI.S(6), UI.S(26), Color(235, 228, 228, 255 * t))
		draw.SimpleText(left > 0 and math.ceil(left) .. " с" or "готово", NYRP.Font("bold", 14), cx, cy + UI.S(18), Color(235, 228, 228, 220 * t), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	local btn = vgui.Create("NYRP.Button", pnl)
	btn:SetSize(UI.S(300), UI.S(56))
	btn:SetPos(ScrW() / 2 - UI.S(150), ScrH() * 0.6 + UI.S(70))
	btn:SetLabel("ВОЗРОДИТЬСЯ")
	btn:SetIcon("refresh")
	btn:SetStyle("solid")
	btn:SetAccent(UI.Col.red)
	btn:SetAlign(TEXT_ALIGN_CENTER)
	btn:SetFontStyle("title", 22)
	btn.Think = function(s)
		s:SetEnabled(CurTime() >= deathTime() + NYRP.Config.RespawnTime and not s.Sent)
	end
	btn.DoClick = function(s)
		s.Sent = true
		UI.Sound("start")
		net.Start("nyrp.death.respawn")
		net.SendToServer()
	end
	btn:SetAlpha(0)
	btn:AlphaTo(255, 0.5, 1.2)
end

hook.Add("Think", "nyrp.death.ui", function()
	local ply = LocalPlayer()
	if not IsValid(ply) or NYRP.State ~= "playing" then return end
	if not ply:Alive() and CurTime() - deathTime() > 1.2 then D.Open() end
end)
