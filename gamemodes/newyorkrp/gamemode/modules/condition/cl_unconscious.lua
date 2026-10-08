--[[
	Без сознания: камера из глаз тела (рэгдолл от первого лица), экран «ВЫ БЕЗ СОЗНАНИЯ»
	с состоянием под ним; в критическом — ждём помощи других игроков (осмотр тела по E и первая помощь).
	После пробуждения — эффект открывания глаз (NYRP.Wakeup).
]]

local UI = NYRP.UI
local Cond = NYRP.Cond
local U = NYRP.Config.Unconscious

local function rag(ply)
	local r = ply:GetNW2Entity("nyrp.koRag")
	return IsValid(r) and r or nil
end

-- Камера из глаз тела.
local smoothAng
hook.Add("NYRP.CalcView", "nyrp.unconscious", function(ply, origin, angles, fov)
	if not ply:Alive() or not Cond.KO(ply) then smoothAng = nil return end
	local r = rag(ply)
	if not r then return end
	local att = r:LookupAttachment("eyes")
	local eyes = att > 0 and r:GetAttachment(att)
	if not eyes then return end
	smoothAng = smoothAng and LerpAngle(1 - math.exp(-10 * FrameTime()), smoothAng, eyes.Ang) or eyes.Ang
	return { origin = eyes.Pos + eyes.Ang:Forward() * 1.5, angles = smoothAng, fov = fov, znear = 1, drawviewer = false }
end)

-- Голова тела не должна закрывать камеру.
hook.Add("Think", "nyrp.unconscious.head", function()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local r = rag(ply)
	if r and r ~= ply.nyrpKORagHidden then
		local b = r:LookupBone("ValveBiped.Bip01_Head1")
		if b then r:ManipulateBoneScale(b, Vector(0.001, 0.001, 0.001)) end
		ply.nyrpKORagHidden = r
	end
	-- пришёл в себя — открываем глаза
	local ko = Cond.KO(ply)
	if ply.nyrpWasKO and not ko and ply:Alive() and NYRP.Wakeup then
		NYRP.Wakeup(ply:GetNW2String("nyrp.gender", "male"), true) -- звук играет сервер
	end
	ply.nyrpWasKO = ko
end)

local function fmt(t)
	t = math.max(0, math.ceil(t))
	return string.format("%d:%02d", math.floor(t / 60), t % 60)
end

hook.Add("HUDPaintBackground", "nyrp.unconscious", function()
	local ply = LocalPlayer()
	if not IsValid(ply) or not ply:Alive() or not Cond.KO(ply) then return end
	local w, h = ScrW(), ScrH()
	local t = CurTime() - ply:GetNW2Float("nyrp.koStart", CurTime())
	local crit = ply:GetNW2Bool("nyrp.koCritical")
	local left = ply:GetNW2Float("nyrp.koUntil", 0) - CurTime()
	local a = UI.Ease(t / 0.8)

	-- веки почти закрыты, иногда приоткрываются
	local open = 0.18 + 0.12 * math.max(0, math.sin(t * 0.9)) ^ 3
	local lid = h / 2 * (1 - open * a) * a + 0
	UI.BlurRect(0, 0, w, h, 6 * a)
	surface.SetDrawColor(0, 0, 0, 255)
	surface.DrawRect(0, 0, w, lid)
	surface.DrawRect(0, h - lid, w, lid)
	surface.SetMaterial(UI.Mat("vgui/gradient-u"))
	surface.DrawTexturedRect(0, lid, w, h * 0.2)
	surface.SetMaterial(UI.Mat("vgui/gradient-d"))
	surface.DrawTexturedRect(0, h - lid - h * 0.2, w, h * 0.2)
	surface.SetDrawColor(crit and 40 or 8, 2, 4, 120 * a)
	surface.DrawRect(0, 0, w, h)

	local cy = h * 0.42
	local pulse = (math.sin(RealTime() * 2.4) + 1) / 2
	draw.SimpleText("ВЫ БЕЗ СОЗНАНИЯ", NYRP.Font("title", 76), w / 2, cy, Color(236, 230, 228, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	local col = crit and Color(226, 80, 70) or Color(214, 178, 140)
	local state = crit and "СОСТОЯНИЕ: КРИТИЧЕСКОЕ" or "СОСТОЯНИЕ: СТАБИЛЬНОЕ"
	-- плашка состояния
	local font = NYRP.Font("bold", 18)
	local tw = UI.TextSize(state, font) + UI.S(64)
	local bx, by = w / 2 - tw / 2, cy + UI.S(52)
	UI.RoundedRect(UI.S(16), bx, by, tw, UI.S(36), Color(10, 10, 14, 200 * a))
	UI.Outline(UI.S(16), bx, by, tw, UI.S(36), UI.Alpha(col, (90 + 80 * (crit and pulse or 0)) * a), 1)
	surface.SetMaterial(UI.Mat("nyrp/status/" .. (crit and "critical" or "unconscious") .. ".png"))
	surface.SetDrawColor(col.r, col.g, col.b, 255 * a)
	surface.DrawTexturedRect(bx + UI.S(14), by + UI.S(7), UI.S(22), UI.S(22))
	draw.SimpleText(state, font, bx + UI.S(44), by + UI.S(18), UI.Alpha(col, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

	local sub
	if crit then
		sub = "Вы тяжело ранены и не можете встать сами. Нужна помощь: другой человек должен осмотреть вас (E) и оказать первую помощь аптечкой."
	else
		sub = "Вы придёте в себя через " .. math.max(1, math.ceil(left)) .. " с."
	end
	for i, l in ipairs(UI.Wrap(sub, NYRP.Font("regular", 17), UI.S(560))) do
		draw.SimpleText(l, NYRP.Font("regular", 17), w / 2, by + UI.S(62) + (i - 1) * UI.S(22), Color(200, 194, 194, 220 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	if crit then
		draw.SimpleText("Без помощи вы умрёте через " .. fmt(left), NYRP.Font("semibold", 15), w / 2, by + UI.S(118),
			Color(226, 80, 70, (150 + 100 * pulse) * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	else
		local frac = math.Clamp(1 - left / U.WakeTime, 0, 1)
		local bw = UI.S(220)
		UI.RoundedRect(UI.S(2), w / 2 - bw / 2, by + UI.S(100), bw, UI.S(4), Color(255, 255, 255, 25 * a))
		UI.RoundedRect(UI.S(2), w / 2 - bw / 2, by + UI.S(100), bw * frac, UI.S(4), UI.Alpha(col, 255 * a))
	end
end)

-- Свой HUD без лишнего, пока без сознания.
hook.Add("HUDShouldDraw", "nyrp.unconscious", function(name)
	local ply = LocalPlayer()
	if IsValid(ply) and Cond.KO(ply) and (name == "CHudWeaponSelection" or name == "CHudCrosshair") then return false end
end)

-- Другим игрокам у тела показывается значок «E» (меню тела — modules/interact/cl_body.lua).
