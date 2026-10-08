--[[
	Диалог с NPC: панель слева от NPC — белая шапка с именем, тёмное тело с репликой (печатается)
	и ответами, выбранный — на оранжевой скошенной плашке; от NPC к панели тянутся тонкие линии.
	Курсор свободен: наведите на ответ и кликните (или колесо + E), ПКМ — уйти.
]]

local UI = NYRP.UI
local N = NYRP.NPC
local D

local ORANGE = Color(247, 198, 0) -- жёлтый «такси», как в логотипе

local function close(silent, fromServer)
	if D and not D.closing then
		D.closing = RealTime()
		gui.EnableScreenClicker(false)
		if not silent then UI.Sound("close") end
		-- сервер должен знать, что разговор окончен
		if not fromServer and IsValid(D.ent) then
			net.Start("nyrp.npc.choose") net.WriteEntity(D.ent) net.WriteUInt(0, 4) net.SendToServer()
		end
	end
end
N.CloseDialog = close
function N.InDialog() return D ~= nil and not D.closing end

net.Receive("nyrp.npc.node", function()
	local ent, nodeId = net.ReadEntity(), net.ReadString()
	if nodeId == "" then close(false, true) return end
	local text = net.ReadString()
	local opts = {}
	for _ = 1, net.ReadUInt(4) do
		opts[#opts + 1] = { i = net.ReadUInt(4), text = net.ReadString(), act = net.ReadString() }
	end
	local fresh = not D or D.closing or D.ent ~= ent
	D = { ent = ent, text = text, opts = opts, sel = 1, acc = 0, typed = 0,
		born = fresh and RealTime() or D.born, nodeBorn = RealTime(), hover = {} }
	UI.Sound(fresh and "open" or "swipe")
	if fresh then gui.EnableScreenClicker(true) end
end)

local function choose()
	if not N.InDialog() then return end
	local o = D.opts[D.sel]
	if not o then return end
	-- реплика ещё печатается — сначала допечатать
	if D.typed < utf8.len(D.text) then D.typed = utf8.len(D.text) return end
	UI.Sound("click")
	net.Start("nyrp.npc.choose")
	net.WriteEntity(D.ent)
	net.WriteUInt(o.i, 4)
	net.SendToServer()
end

local function move(dir)
	if not N.InDialog() or #D.opts == 0 then return end
	D.sel = (D.sel - 1 + dir) % #D.opts + 1
	UI.Sound("hover")
end

-- Мышь: наведение выбирает ответ, ЛКМ — ответить, ПКМ — уйти.
local function optionAt(mx, my)
	for i, r in pairs(D and D.rects or {}) do
		if mx >= r[1] and mx <= r[1] + r[3] and my >= r[2] and my <= r[2] + r[4] then return i end
	end
end

hook.Add("GUIMousePressed", "nyrp.npc.dialog", function(code)
	if not N.InDialog() then return end
	if code == MOUSE_RIGHT then close() return end
	if code == MOUSE_LEFT then
		local i = optionAt(gui.MousePos())
		if i then D.sel = i choose() end
	end
end)

hook.Add("PlayerBindPress", "nyrp.npc.dialog", function(ply, bind, pressed)
	if not N.InDialog() or not pressed then return end
	if bind == "invnext" then move(1) return true end
	if bind == "invprev" then move(-1) return true end
	if string.find(bind, "+attack2", 1, true) then close() return true end
	if string.find(bind, "+use", 1, true) or string.find(bind, "+attack", 1, true) then choose() return true end
	if string.find(bind, "slot", 1, true) then return true end
end)

hook.Add("Think", "nyrp.npc.dialog", function()
	if not D then return end
	if D.closing then
		if RealTime() - D.closing > 0.25 then D = nil end
		return
	end
	if not IsValid(D.ent) or not LocalPlayer():Alive() or D.ent:GetPos():Distance(LocalPlayer():GetPos()) > 180 then close() return end
	D.typed = math.min(utf8.len(D.text) or 0, D.typed + FrameTime() * 55)
	local i = optionAt(gui.MousePos())
	if i and i ~= D.sel then D.sel = i UI.Sound("hover") end
end)

local function anchor(ent)
	local b = ent:LookupBone("ValveBiped.Bip01_Spine2")
	local p = b and ent:GetBonePosition(b) or ent:WorldSpaceCenter()
	return p:ToScreen()
end

local function utf8sub(s, n)
	n = math.floor(n)
	if n <= 0 then return "" end
	local off = utf8.offset(s, n + 1)
	return off and string.sub(s, 1, off - 1) or s
end

hook.Add("HUDPaint", "nyrp.npc.dialog", function()
	if not D or not IsValid(D.ent) then return end
	local t = UI.Ease((RealTime() - D.born) / 0.3)
	if D.closing then t = t * (1 - UI.Ease((RealTime() - D.closing) / 0.25)) end
	if t <= 0 then return end
	local sc = anchor(D.ent)
	local pw = UI.S(560)
	local textFont, optFont = NYRP.Font("tag", 19), NYRP.Font("tag", 18)
	local lines = UI.Wrap(utf8sub(D.text, D.typed), textFont, pw - UI.S(40))
	local allLines = UI.Wrap(D.text, textFont, pw - UI.S(40))
	local headH, optH = UI.S(54), UI.S(34)
	local ph = headH + UI.S(22) + #allLines * UI.S(24) + UI.S(16) + #D.opts * optH + UI.S(24)
	local px = math.Clamp(sc.x - UI.S(140) - pw, UI.S(20), ScrW() - pw - UI.S(20))
	local py = math.Clamp(sc.y - ph * 0.55, UI.S(20), ScrH() - ph - UI.S(90))
	local reveal = UI.Ease((RealTime() - D.born) / 0.35)
	surface.SetAlphaMultiplier(t)

	-- линии от NPC к правым углам панели и точка на NPC
	local ex, ey = px + pw, py
	surface.SetDrawColor(247, 198, 0, 150)
	surface.DrawLine(sc.x, sc.y, sc.x + (ex - sc.x) * reveal, sc.y + (ey - sc.y) * reveal)
	surface.DrawLine(sc.x, sc.y, sc.x + (ex - sc.x) * reveal, sc.y + (py + ph - sc.y) * reveal)
	UI.Glow(sc.x, sc.y, UI.S(22), UI.S(22), Color(247, 198, 0, 180))
	UI.Circle(sc.x, sc.y, UI.S(3), Color(255, 240, 190))

	render.SetScissorRect(px + pw * (1 - reveal), py, px + pw, py + ph, true)
	-- тело панели
	UI.BlurRect(px, py, pw, ph, 3)
	surface.SetDrawColor(14, 16, 26, 225)
	surface.DrawRect(px, py, pw, ph)
	surface.SetMaterial(UI.Mat("vgui/gradient-d"))
	surface.SetDrawColor(4, 5, 10, 170)
	surface.DrawTexturedRect(px, py + headH, pw, ph - headH)
	-- шапка: тёмная, снизу полоса «шашечек такси»
	surface.SetDrawColor(8, 9, 14, 245)
	surface.DrawRect(px, py, pw, headH)
	local cs = UI.S(6)
	for i = 0, math.ceil(pw / cs) do
		for r = 0, 1 do
			if (i + r) % 2 == 0 then surface.SetDrawColor(247, 198, 0) else surface.SetDrawColor(10, 10, 12) end
			surface.DrawRect(px + i * cs, py + headH - cs * 2 + r * cs, math.min(cs, px + pw - (px + i * cs)), cs)
		end
	end
	local name = D.ent:GetNW2String("nyrp.npcName", "NPC")
	local icon = D.ent:GetNW2String("nyrp.npcKind") == "trader" and "npc_trader" or "npc_talk"
	surface.SetMaterial(UI.Mat("nyrp/status/" .. icon .. ".png"))
	surface.SetDrawColor(247, 198, 0)
	surface.DrawTexturedRect(px + UI.S(16), py + UI.S(10), UI.S(26), UI.S(26))
	draw.SimpleText(name, NYRP.Font("tag", 24), px + UI.S(52), py + (headH - cs * 2) / 2 + UI.S(2), Color(240, 241, 245), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	-- «сигнал» справа
	local sx = px + pw - UI.S(60)
	surface.SetDrawColor(247, 198, 0)
	surface.DrawRect(sx, py + UI.S(18), UI.S(10), UI.S(4))
	surface.DrawRect(sx + UI.S(3), py + UI.S(18), UI.S(4), UI.S(18))
	for k = 0, 2 do
		local bh = UI.S(5 + k * 5)
		surface.DrawRect(sx + UI.S(18 + k * 9), py + UI.S(36) - bh, UI.S(4), bh)
	end
	-- реплика NPC
	local y = py + headH + UI.S(16)
	for i, l in ipairs(lines) do
		draw.SimpleText(l, textFont, px + UI.S(20), y + (i - 1) * UI.S(24), Color(235, 238, 245))
	end
	y = y + #allLines * UI.S(24) + UI.S(14)
	-- ответы
	local done = D.typed >= (utf8.len(D.text) or 0)
	D.rects = {}
	for i, o in ipairs(D.opts) do
		D.hover[i] = UI.Approach(D.hover[i] or 0, D.sel == i and 1 or 0, 18)
		local hv = D.hover[i]
		local oy = y + (i - 1) * optH
		D.rects[i] = { px, oy, pw, optH }
		local oa = done and 1 or 0.35
		if hv > 0.01 then
			local w = (pw - UI.S(40)) * (0.75 + 0.25 * hv)
			local slant = UI.S(12)
			draw.NoTexture()
			surface.SetDrawColor(ORANGE.r, ORANGE.g, ORANGE.b, 255 * hv)
			surface.DrawPoly({
				{ x = px + UI.S(14), y = oy + UI.S(2) }, { x = px + UI.S(14) + w, y = oy + UI.S(2) },
				{ x = px + UI.S(14) + w - slant, y = oy + optH - UI.S(2) }, { x = px + UI.S(14), y = oy + optH - UI.S(2) },
			})
			UI.Glow(px + UI.S(14) + w / 2, oy + optH / 2, w * 1.1, optH * 1.6, Color(247, 198, 0, 30 * hv))
		end
		local col = UI.LerpColor(hv, Color(232, 235, 242, 255 * oa), Color(18, 18, 22))
		local prefix = o.act == "trade" and "» " or (o.act == "quest" and "+ " or (o.act == "turnin" and "• " or ""))
		draw.SimpleText(prefix .. o.text, optFont, px + UI.S(26), oy + optH / 2, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	-- жёлтая кромка снизу
	surface.SetDrawColor(247, 198, 0, 230)
	surface.DrawRect(px, py + ph - UI.S(3), pw, UI.S(3))
	render.SetScissorRect(0, 0, 0, 0, false)

	-- подсказка справа внизу
	local kx, ky = ScrW() - UI.S(60), ScrH() - UI.S(70)
	UI.Outline(UI.S(4), kx, ky - UI.S(14), UI.S(28), UI.S(28), Color(255, 255, 255, 220), 1)
	draw.SimpleText("E", NYRP.Font("bold", 15), kx + UI.S(14), ky, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText("ВЫБРАТЬ", NYRP.Font("title", 18), kx - UI.S(12), ky, color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	draw.SimpleText("клик или колесо + E — ответ · ПКМ — уйти", NYRP.Font("regular", 12), kx + UI.S(28), ky + UI.S(26), UI.Col.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	surface.SetAlphaMultiplier(1)
end)

-- В диалоге не показываем прицел и подсказки взаимодействия.
hook.Add("HUDShouldDraw", "nyrp.npc.dialog", function(name)
	if N.InDialog() and name == "CHudCrosshair" then return false end
end)
