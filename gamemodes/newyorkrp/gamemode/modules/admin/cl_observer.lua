--[[
	Режим наблюдателя (клиент): ESP над игроками (имя персонажа, ник, здоровье, роль, расстояние, линия),
	плашка режима, камера слежки за игроком (/spectate). Видно только самому наблюдателю.
]]

NYRP.Admin = NYRP.Admin or {}
local A = NYRP.Admin
local UI = NYRP.UI
local GOLD = Color(247, 198, 0)

local function me() return LocalPlayer() end

local function active()
	local p = me()
	return IsValid(p) and p:IsAdmin() and A.IsObserver(p)
end

-- ------------------------------------------------------------- камера --
local specDist = 110
hook.Add("NYRP.CalcView", "nyrp.admin.observer", function(ply, origin, angles, fov)
	if not A.IsObserver(ply) then return end
	local t = A.Spectating(ply)
	if t then
		local rag = not t:Alive() and t:GetNW2Entity("nyrp.deathRag") or nil
		local center = IsValid(rag) and rag:GetPos() or (t:GetPos() + Vector(0, 0, 58 * (t:GetModelScale() or 1)))
		local tr = util.TraceHull({ start = center, endpos = center - angles:Forward() * specDist, filter = { t, ply, rag },
			mins = Vector(-6, -6, -6), maxs = Vector(6, 6, 6), mask = MASK_SOLID_BRUSHONLY })
		return { origin = tr.HitPos, angles = angles, fov = fov, drawviewer = false }
	end
	return { origin = origin, angles = angles, fov = fov, drawviewer = false }
end)

hook.Add("PlayerBindPress", "nyrp.admin.spectate", function(ply, bind, pressed)
	if not pressed or not A.Spectating(ply) then return end
	if string.find(bind, "invprev", 1, true) then specDist = math.max(50, specDist - 15) return true end
	if string.find(bind, "invnext", 1, true) then specDist = math.min(300, specDist + 15) return true end
end)

hook.Add("NYRP.ShouldDrawLocalPlayer", "nyrp.admin.observer", function(ply)
	if A.IsObserver(ply) then return false end
end)

-- невидимых наблюдателей не рисуем (страховка поверх SetNoDraw)
hook.Add("PrePlayerDraw", "nyrp.admin.observer", function(ply)
	if A.IsObserver(ply) then return true end
end)

-- ----------------------------------------------------------------- ESP --
local function roleOf(p)
	local R = NYRP.Roles
	if R and R.Of then
		local ok, r = pcall(R.Of, p)
		if ok and r then return r end
	end
end

local function shadowText(text, font, x, y, col, ax, ay)
	draw.SimpleText(text, font, x + 1, y + 1, Color(0, 0, 0, col.a * 0.8), ax, ay)
	draw.SimpleText(text, font, x, y, col, ax, ay)
end

local function drawESP()
	local self = me()
	local maxd = NYRP.Config.Admin and NYRP.Config.Admin.ESPDistance or 8000
	local eye = EyePos()
	local spec = A.Spectating(self)
	local cx, cy = ScrW() / 2, ScrH()
	local fName, fSmall, fTag = NYRP.Font("bold", 15), NYRP.Font("medium", 12), NYRP.Font("bold", 10)
	for _, p in ipairs(player.GetAll()) do
		if p ~= self and IsValid(p) then
			local rag = not p:Alive() and p:GetNW2Entity("nyrp.deathRag") or nil
			local base = IsValid(rag) and rag:GetPos() or p:GetPos()
			local dist = eye:Distance(base)
			if dist <= maxd then
				local headPos = (IsValid(rag) and base or p:EyePos()) + Vector(0, 0, 14)
				local head = headPos:ToScreen()
				local foot = (base + Vector(0, 0, 36)):ToScreen()
				local r = roleOf(p)
				local rc = r and r.Color or Color(200, 200, 200)
				local fade = math.Clamp(1.15 - dist / maxd, 0.35, 1)
				-- линия к игроку
				if foot.visible and p ~= spec then
					surface.SetDrawColor(rc.r, rc.g, rc.b, 70 * fade)
					surface.DrawLine(cx, cy, foot.x, foot.y)
				end
				if head.visible then
					local x, y = math.floor(head.x), math.floor(head.y)
					local alpha = 255 * fade
					local name = p:GetNW2String("nyrp.name", "")
					if name == "" then name = "без персонажа" end
					local tags = {}
					if not p:Alive() then tags[#tags + 1] = { "МЁРТВ", UI.Col.red } end
					if NYRP.Cond and NYRP.Cond.KO and p:Alive() and NYRP.Cond.KO(p) then tags[#tags + 1] = { "БЕЗ СОЗНАНИЯ", UI.Col.orange } end
					if p:GetNW2Bool("nyrp.frozen", false) then tags[#tags + 1] = { "ЗАМОРОЖЕН", UI.Col.blue } end
					if A.IsObserver(p) then tags[#tags + 1] = { "НАБЛЮДАТЕЛЬ", GOLD } end
					if p:IsAdmin() then tags[#tags + 1] = { "АДМИН", Color(255, 90, 140) } end

					local w = math.max(UI.TextSize(name, fName), UI.TextSize(p:Nick(), fSmall), UI.S(110)) + UI.S(22)
					local h = UI.S(62)
					local bx, by = x - w / 2, y - h
					UI.RoundedRect(UI.S(6), bx, by, w, h, Color(10, 12, 20, 190 * fade))
					UI.RoundedRect(UI.S(2), bx, by + UI.S(8), UI.S(3), h - UI.S(16), Color(rc.r, rc.g, rc.b, alpha))
					shadowText(name, fName, x, by + UI.S(4), Color(255, 255, 255, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
					shadowText(p:Nick() .. "  ·  " .. (r and r.Name or "—"), fSmall, x, by + UI.S(22), Color(rc.r, rc.g, rc.b, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
					-- здоровье
					local hp = math.max(0, p:Alive() and p:Health() or 0)
					local frac = math.Clamp(hp / math.max(p:GetMaxHealth(), 1), 0, 1)
					local bw = w - UI.S(56)
					local hx, hy = bx + UI.S(10), by + h - UI.S(16)
					UI.RoundedRect(UI.S(2), hx, hy, bw, UI.S(5), Color(255, 255, 255, 25 * fade))
					UI.RoundedRect(UI.S(2), hx, hy, math.max(bw * frac, UI.S(4)), UI.S(5), UI.LerpColor(frac, Color(214, 70, 64, alpha), Color(104, 200, 120, alpha)))
					shadowText(hp .. "", fSmall, hx + bw + UI.S(6), hy + UI.S(2), Color(230, 230, 235, alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					shadowText(math.Round(dist / 52) .. " м", fSmall, x, by + h + UI.S(3), Color(170, 175, 190, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
					-- метки
					local tx = x
					local total = 0
					for _, t in ipairs(tags) do total = total + UI.TextSize(t[1], fTag) + UI.S(12) end
					tx = x - total / 2
					for _, t in ipairs(tags) do
						local tw = UI.TextSize(t[1], fTag) + UI.S(8)
						UI.RoundedRect(UI.S(3), tx, by - UI.S(17), tw, UI.S(14), Color(t[2].r, t[2].g, t[2].b, 210 * fade))
						draw.SimpleText(t[1], fTag, tx + tw / 2, by - UI.S(10), Color(10, 10, 14, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
						tx = tx + tw + UI.S(4)
					end
				end
			end
		end
	end
end

local function drawBanner()
	local self = me()
	local spec = A.Spectating(self)
	local title = spec and ("НАБЛЮДЕНИЕ: " .. NYRP.CharName(spec)) or "РЕЖИМ НАБЛЮДАТЕЛЯ"
	local hint = spec and "Пробел — выйти  ·  колесо мыши — дистанция камеры" or "V или /observer — выйти  ·  невидимы, без коллизий, бессмертны"
	local ft, fh = NYRP.Font("title", 20), NYRP.Font("regular", 13)
	local w = math.max(UI.TextSize(title, ft), UI.TextSize(hint, fh)) + UI.S(60)
	local h = UI.S(54)
	local x, y = ScrW() / 2 - w / 2, UI.S(16)
	UI.RoundedRect(UI.S(10), x, y, w, h, Color(10, 12, 20, 215))
	UI.Outline(UI.S(10), x, y, w, h, Color(247, 198, 0, 90), 1)
	UI.DrawIcon("eye", x + UI.S(22), y + h / 2, UI.S(20), GOLD)
	draw.SimpleText(title, ft, ScrW() / 2 + UI.S(12), y + UI.S(17), color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText(hint, fh, ScrW() / 2 + UI.S(12), y + UI.S(38), UI.Col.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	-- у цели слежки — карточка состояния
	if spec then
		local r = roleOf(spec)
		local txt = string.format("%s  ·  %s  ·  HP %d  ·  %s", spec:Nick(), r and r.Name or "—", math.max(spec:Health(), 0),
			NYRP.Money and NYRP.Money.Format and NYRP.Money.Format(spec:GetNW2Int("nyrp.money", 0)) or "")
		local f = NYRP.Font("medium", 14)
		local tw = UI.TextSize(txt, f) + UI.S(30)
		UI.RoundedRect(UI.S(8), ScrW() / 2 - tw / 2, ScrH() - UI.S(130), tw, UI.S(32), Color(10, 12, 20, 200))
		draw.SimpleText(txt, f, ScrW() / 2, ScrH() - UI.S(114), UI.Col.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end

hook.Add("HUDPaint", "nyrp.admin.observer", function()
	if not active() then return end
	drawESP()
	drawBanner()
end)
