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
	local rag = ply:GetNW2Entity("nyrp.deathRag")
	if not IsValid(rag) then rag = ply:GetRagdollEntity() end
	if not IsValid(rag) then return end
	-- своя голова не закрывает камеру в первые секунды (вид из глаз тела)
	local hb = rag:LookupBone("ValveBiped.Bip01_Head1")
	if hb then
		local t0 = CurTime() - deathTime()
		rag:ManipulateBoneScale(hb, t0 < 2.2 and Vector(0.001, 0.001, 0.001) or Vector(1, 1, 1))
	end
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

-- Экран смерти: кинематографичные полосы сверху/снизу, крупный заголовок, причина смерти,
-- полоса с отсчётом до автоматического возрождения и затухающее сердцебиение.
local function fmt(t)
	t = math.max(0, math.ceil(t))
	return string.format("%d:%02d", math.floor(t / 60), t % 60)
end

function D.Open()
	if IsValid(D.Panel) then return end
	local pnl = vgui.Create("EditablePanel")
	D.Panel = pnl
	pnl:SetSize(ScrW(), ScrH())
	pnl:SetMouseInputEnabled(false)
	pnl:SetKeyboardInputEnabled(false)
	pnl.Born = RealTime()
	pnl.NextBeat = RealTime() + 0.4
	pnl.Beat = 0
	pnl.Think = function(s)
		if LocalPlayer():Alive() then s:Remove() return end
		if RealTime() > s.NextBeat and s.Beat < 9 then
			s.Beat = s.Beat + 1
			s.NextBeat = RealTime() + 0.9 + s.Beat * 0.22
			LocalPlayer():EmitSound("nyrp/fx/heartbeat.wav", 75, 100 - s.Beat * 3, 1 - s.Beat * 0.09, CHAN_STATIC)
			s.Pulse = RealTime()
		end
	end
	pnl.Paint = function(s, w, h)
		local el = RealTime() - s.Born
		local t = UI.Ease(el / 1.4)
		local pulse = s.Pulse and math.max(0, 1 - (RealTime() - s.Pulse) / 0.6) or 0
		-- затемнение, виньетка, красный «пульс»
		UI.BlurPanel(s, 2.5 * t)
		surface.SetDrawColor(6, 2, 3, 170 * t)
		surface.DrawRect(0, 0, w, h)
		UI.Vignette(-UI.S(30), -UI.S(30), w + UI.S(60), h + UI.S(60), 255 * t)
		surface.SetMaterial(UI.Mat("nyrp/ui/blood_edges.png"))
		surface.SetDrawColor(255, 255, 255, (70 + 90 * pulse) * t)
		surface.DrawTexturedRect(0, 0, w, h)
		-- полосы как в кино
		local bar = h * 0.11 * UI.Ease(el / 0.9)
		surface.SetDrawColor(0, 0, 0, 255)
		surface.DrawRect(0, 0, w, bar)
		surface.DrawRect(0, h - bar, w, bar)

		local cx, cy = w / 2, h * 0.43
		-- заголовок: буквы разъезжаются из сжатого состояния
		local title = "ВЫ ПОГИБЛИ"
		local font = NYRP.Font("title", 104)
		local spread = UI.S(14) * UI.Ease(el / 2.2)
		local chars = {}
		for _, c in utf8.codes(title) do chars[#chars + 1] = utf8.char(c) end
		surface.SetFont(font)
		local total = 0
		for _, c in ipairs(chars) do total = total + surface.GetTextSize(c) + spread end
		total = total - spread
		local x = cx - total / 2
		for i, c in ipairs(chars) do
			local ca = UI.Ease((el - 0.3 - i * 0.05) / 0.5)
			local cw = surface.GetTextSize(c)
			draw.SimpleText(c, font, x + 3, cy + 4 + (1 - ca) * UI.S(18), Color(0, 0, 0, 200 * ca), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText(c, font, x, cy + (1 - ca) * UI.S(18), Color(236, 226, 224, 255 * ca), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			x = x + cw + spread
		end
		-- тонкая красная линия и причина смерти
		local la = UI.Ease((el - 1.0) / 0.6)
		local lw = UI.S(420) * la
		UI.RoundedRect(1, cx - lw / 2, cy + UI.S(66), lw, UI.S(2), Color(200, 50, 46, 220 * la))
		local cause = LocalPlayer():GetNW2String("nyrp.deathCause", "")
		if cause ~= "" then
			draw.SimpleText("ПРИЧИНА СМЕРТИ", NYRP.Font("bold", 12), cx, cy + UI.S(88), Color(200, 120, 110, 200 * la), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			draw.SimpleText(cause, NYRP.Font("semibold", 22), cx, cy + UI.S(114), Color(232, 224, 222, 255 * la), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		draw.SimpleText("Город не прощает ошибок. Кто-то найдёт вас на холодном асфальте Нью-Йорка...", NYRP.Font("regular", 16),
			cx, cy + UI.S(150), Color(190, 176, 176, 170 * la), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

		-- отсчёт до возрождения (в нижней полосе)
		local left = math.max(0, deathTime() + NYRP.Config.RespawnTime - CurTime())
		local frac = 1 - left / NYRP.Config.RespawnTime
		local ba = UI.Ease((el - 1.4) / 0.6)
		local bw = UI.S(360)
		local by = h - bar / 2
		draw.SimpleText("ВОЗРОЖДЕНИЕ", NYRP.Font("bold", 12), cx - bw / 2, by - UI.S(14), Color(160, 150, 150, 220 * ba), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText(fmt(left), NYRP.Font("bold", 14), cx + bw / 2, by - UI.S(14), Color(236, 226, 224, 255 * ba), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		UI.RoundedRect(UI.S(2), cx - bw / 2, by + UI.S(2), bw, UI.S(4), Color(255, 255, 255, 22 * ba))
		UI.RoundedRect(UI.S(2), cx - bw / 2, by + UI.S(2), math.max(bw * frac, UI.S(4)), UI.S(4), Color(214, 70, 64, 255 * ba))
		draw.SimpleText("вы возродитесь автоматически", NYRP.Font("regular", 12), cx, by + UI.S(20), Color(130, 124, 124, 200 * ba), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end

hook.Add("Think", "nyrp.death.ui", function()
	local ply = LocalPlayer()
	if not IsValid(ply) or NYRP.State ~= "playing" then return end
	if not ply:Alive() and CurTime() - deathTime() > 1.2 then D.Open() end
end)
