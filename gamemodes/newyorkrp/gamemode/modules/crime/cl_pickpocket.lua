--[[
	Карманная кража (клиент): пункт «Обчистить карманы» в круговом меню игрока (E по человеку)
	и индикатор «насколько вас видно» во время кражи — глаз над жертвой и шкала опасности.
]]

NYRP.Crime = NYRP.Crime or {}
local C = NYRP.Crime
local UI = NYRP.UI

local cur   -- { victim, start, dur }

hook.Add("NYRP.PlayerMenuOptions", "nyrp.crime.pick", function(target, options)
	if not IsValid(target) then return end
	local me = LocalPlayer()
	local behind = C.IsBehind(target, me)
	local near = me:GetPos():Distance(target:GetPos()) <= C.Pick.Range
	options[#options + 1] = {
		id = "crime_pick", name = "Обчистить карманы", icon = "hand",
		disabled = not (behind and near),
		note = not behind and "Только со спины" or "Подойдите вплотную",
		func = function(t)
			net.Start("nyrp.crime.pick")
			net.WriteEntity(t)
			net.SendToServer()
		end,
	}
end)

net.Receive("nyrp.crime.pickState", function()
	local on, victim, dur = net.ReadBool(), net.ReadEntity(), net.ReadFloat()
	if on and IsValid(victim) then
		cur = { victim = victim, start = RealTime(), dur = dur }
	else
		cur = nil
	end
end)

hook.Add("HUDPaint", "nyrp.crime.pick", function()
	if not cur then return end
	local v = cur.victim
	if not IsValid(v) or RealTime() - cur.start > cur.dur + 1 then cur = nil return end
	local ang = C.ViewAngle(v, LocalPlayer())
	-- 0 — безопасно (вы ровно за спиной), 1 — сейчас заметит
	local danger = math.Clamp((180 - ang) / (180 - C.Pick.NoticeAngle), 0, 1)
	local col = UI.LerpColor and UI.LerpColor(danger, UI.Col.green, UI.Col.red) or (danger > 0.6 and UI.Col.red or UI.Col.green)

	-- глаз над головой жертвы
	local head = v:LookupBone("ValveBiped.Bip01_Head1")
	local hp = head and v:GetBonePosition(head) or v:EyePos()
	local sc = (hp + Vector(0, 0, 14)):ToScreen()
	if sc.visible then
		local pulse = 1 + math.sin(RealTime() * (6 + danger * 14)) * 0.08 * danger
		local r = UI.S(16) * pulse
		UI.Circle(sc.x, sc.y, r + UI.S(3), Color(0, 0, 0, 140))
		UI.Circle(sc.x, sc.y, r, Color(col.r, col.g, col.b, 230))
		UI.DrawIcon("eye", sc.x, sc.y, r * 1.2, Color(12, 14, 20))
	end

	-- шкала «заметность» под прогресс-баром
	local w, h = UI.S(260), UI.S(8)
	local x, y = ScrW() / 2 - w / 2, ScrH() * 0.72
	draw.SimpleText(danger > 0.66 and "ОБОРАЧИВАЕТСЯ!" or (danger > 0.33 and "Осторожно..." or "Вас не видят"),
		NYRP.Font("semibold", 15), ScrW() / 2, y - UI.S(12), col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	UI.RoundedRect(UI.S(4), x, y, w, h, Color(0, 0, 0, 150))
	UI.RoundedRect(UI.S(4), x, y, math.max(h, w * danger), h, Color(col.r, col.g, col.b, 230))
	draw.SimpleText("Не двигайтесь и не попадайтесь на глаза", NYRP.Font("regular", 12), ScrW() / 2, y + h + UI.S(12), UI.Col.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)
