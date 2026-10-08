--[[
	Контейнеры на клиенте: круговой прогресс «Открываю...» и окно контейнера справа от сумки.
]]

local UI = NYRP.UI
local C = NYRP.Containers
local Inv = NYRP.Inventory

local SLOT, GAP = 80, 8
local progress

-- Дуга (кольцо) от a0 до a1 градусов (0 — вверх, по часовой).
local function arc(cx, cy, r, thick, a0, a1, col)
	if a1 <= a0 then return end
	draw.NoTexture()
	surface.SetDrawColor(col)
	local steps = math.max(2, math.ceil((a1 - a0) / 4))
	local ri = r - thick
	for k = 0, steps - 1 do
		local t0 = math.rad(a0 + (a1 - a0) * k / steps)
		local t1 = math.rad(a0 + (a1 - a0) * (k + 1) / steps)
		surface.DrawPoly({
			{ x = cx + math.sin(t0) * r, y = cy - math.cos(t0) * r },
			{ x = cx + math.sin(t1) * r, y = cy - math.cos(t1) * r },
			{ x = cx + math.sin(t1) * ri, y = cy - math.cos(t1) * ri },
			{ x = cx + math.sin(t0) * ri, y = cy - math.cos(t0) * ri },
		})
	end
end
C.Arc = arc

net.Receive("nyrp.cont.progress", function()
	local ent, dur = net.ReadEntity(), net.ReadFloat()
	if not IsValid(ent) or dur <= 0 then
		if progress then progress.cancel = RealTime() end
		return
	end
	progress = { ent = ent, start = RealTime(), dur = dur }
	UI.Sound("progress")
end)

hook.Add("HUDPaint", "nyrp.containers.progress", function()
	local p = progress
	if not p then return end
	local now = RealTime()
	local el = now - p.start
	local frac = math.Clamp(el / p.dur, 0, 1)
	local out = p.cancel and (now - p.cancel) or (frac >= 1 and el - p.dur or 0)
	if out > 0.3 then progress = nil return end
	local a = UI.Ease(el / 0.2) * (1 - out / 0.3)
	local cx, cy = ScrW() / 2, ScrH() / 2
	local r = UI.S(44) * (0.9 + 0.1 * a)
	surface.SetAlphaMultiplier(a)
	UI.Glow(cx, cy, r * 3.4, r * 3.4, Color(0, 0, 0, 160))
	UI.Circle(cx, cy, r - UI.S(6), Color(10, 11, 16, 220))
	arc(cx, cy, r, UI.S(5), 0, 360, Color(255, 255, 255, 24))
	arc(cx, cy, r, UI.S(5), 0, 360 * frac, p.cancel and UI.Col.red or UI.Col.accent)
	UI.DrawIcon("box", cx, cy - UI.S(2), UI.S(28), p.cancel and UI.Col.red or Color(236, 237, 242))
	local dots = string.rep(".", math.floor(el * 3) % 3 + 1)
	local text = p.cancel and "Отменено" or ("Открываю" .. dots)
	draw.SimpleText(text, NYRP.Font("semibold", 18), cx + 1, cy + r + UI.S(20) + 2, Color(0, 0, 0, 170), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText(text, NYRP.Font("semibold", 18), cx, cy + r + UI.S(20), UI.Col.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	if IsValid(p.ent) then
		draw.SimpleText(C.TypeOf(p.ent).name, NYRP.Font("medium", 13), cx, cy + r + UI.S(42), UI.Col.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	surface.SetAlphaMultiplier(1)
end)

-- --------------------------------------------------------------- окно --
function Inv.ContainerWidth()
	local c = Inv.Container
	if not c then return 0 end
	return UI.S(30) * 2 + c.cols * (UI.S(SLOT) + UI.S(GAP)) - UI.S(GAP)
end

local function paintCrate(s, w, h, c)
	local r = UI.S(16)
	UI.Masked(r, 0, 0, w, h, function()
		-- сталь: тёмный градиент и «шлифовка»
		surface.SetDrawColor(30, 32, 36, 255)
		surface.DrawRect(0, 0, w, h)
		surface.SetMaterial(UI.Mat("vgui/gradient-d"))
		surface.SetDrawColor(8, 9, 11, 230)
		surface.DrawTexturedRect(0, 0, w, h)
		for y = 0, h, UI.S(3) do
			surface.SetDrawColor(255, 255, 255, (y / UI.S(3)) % 2 == 0 and 3 or 0)
			surface.DrawRect(0, y, w, 1)
		end
		-- предупреждающая полоса сверху
		local band = UI.S(12)
		surface.SetDrawColor(247, 198, 0, 230)
		surface.DrawRect(0, 0, w, band)
		draw.NoTexture()
		surface.SetDrawColor(14, 14, 16, 255)
		local step = UI.S(22)
		for x = -band, w + band, step do
			surface.DrawPoly({ { x = x, y = 0 }, { x = x + step / 2, y = 0 }, { x = x + step / 2 - band, y = band }, { x = x - band, y = band } })
		end
		UI.Vignette(-UI.S(30), -UI.S(30), w + UI.S(60), h + UI.S(60), 120)
	end)
	UI.Outline(r, 0, 0, w, h, Color(255, 255, 255, 18), 1)
	-- заклёпки по углам
	surface.SetMaterial(UI.Mat("nyrp/ui/rivet.png"))
	surface.SetDrawColor(255, 255, 255, 220)
	local rv = UI.S(12)
	for _, p in ipairs({ { UI.S(10), UI.S(22) }, { w - UI.S(22), UI.S(22) }, { UI.S(10), h - UI.S(22) }, { w - UI.S(22), h - UI.S(22) } }) do
		surface.DrawTexturedRect(p[1], p[2], rv, rv)
	end
	-- заголовок
	UI.DrawIcon("box", UI.S(44), UI.S(48), UI.S(22), UI.Col.accent)
	draw.SimpleText(string.upper(c.name), NYRP.Font("title", 24), UI.S(64), UI.S(48), UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	local used = table.Count(c.slots)
	draw.SimpleText(used .. " / " .. c.cols * c.rows, NYRP.Font("semibold", 15), w - UI.S(30), UI.S(48), UI.Col.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	draw.SimpleText("Перетаскивайте предметы между сумкой и контейнером", NYRP.Font("regular", 13), UI.S(30), h - UI.S(24), Color(255, 255, 255, 60), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

function Inv.BuildContainer()
	local c = Inv.Container
	if not c or not IsValid(Inv.Root) or not IsValid(Inv.Frame) then return end
	if IsValid(Inv.ContFrame) then Inv.ContFrame:Remove() end
	local slot, gap = UI.S(SLOT), UI.S(GAP)
	local pad, top = UI.S(30), UI.S(84)
	local gw, gh = c.cols * (slot + gap) - gap, c.rows * (slot + gap) - gap
	local w = pad * 2 + gw
	local h = math.max(top + gh + UI.S(54), Inv.Frame:GetTall())
	local f = vgui.Create("DPanel", Inv.Root)
	Inv.ContFrame = f
	f:SetSize(w, h)
	f.Born = RealTime()
	f.Think = function(s)
		local fr = Inv.Frame
		if not IsValid(fr) then return end
		local fx, fy = fr:GetPos()
		local x = fx + fr:GetWide() + UI.S(24)
		local cx = s:GetPos()
		s:SetPos(s.Placed and UI.Approach(cx, x, 14) or x + UI.S(40), fy + (fr:GetTall() - h) / 2)
		s.Placed = true
	end
	f.Paint = function(s, pw, ph)
		s:SetAlpha(255 * UI.Ease((RealTime() - s.Born) / 0.3))
		paintCrate(s, pw, ph, c)
	end
	local grid = vgui.Create("DPanel", f)
	grid:SetPos(pad, top)
	grid:SetSize(gw, gh)
	grid.Paint = function() end
	for i = 1, c.cols * c.rows do
		local sl = vgui.Create("NYRP.InvSlot", grid)
		sl:SetSize(slot, slot)
		sl:SetPos(((i - 1) % c.cols) * (slot + gap), math.floor((i - 1) / c.cols) * (slot + gap))
		sl:Setup("cont", i)
	end
end

net.Receive("nyrp.cont.open", function()
	local ent = net.ReadEntity()
	local name, cols, rows = net.ReadString(), net.ReadUInt(8), net.ReadUInt(8)
	local slots = net.ReadTable()
	progress = nil
	Inv.Container = { ent = ent, name = name, cols = cols, rows = rows, slots = slots }
	if Inv.IsOpen() then Inv.BuildFrame() else Inv.Open() end
end)

net.Receive("nyrp.cont.sync", function()
	local ent, slots = net.ReadEntity(), net.ReadTable()
	local c = Inv.Container
	if c and c.ent == ent then
		c.slots = slots
		if IsValid(Inv.Detail) and Inv.Detail.Ref and Inv.RefreshDetail then Inv.RefreshDetail() end
	end
end)

net.Receive("nyrp.cont.close", function()
	if not Inv.Container then return end
	Inv.Container = nil
	if IsValid(Inv.ContFrame) then Inv.ContFrame:Remove() end
	if Inv.IsOpen() then Inv.Close() end
end)
