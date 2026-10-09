--[[
	Зоны на клиенте: показ при входе (иконка + печатная машинка) и редактор /areaedit.
]]

local Z = NYRP.Zones
local UI = NYRP.UI
local GOLD = Color(247, 198, 0)

net.Receive("nyrp.zones", function()
	Z.List = {}
	for _, t in ipairs(net.ReadTable()) do
		Z.List[#Z.List + 1] = { id = t.id, name = t.name, icon = t.icon, min = Vector(t.min[1], t.min[2], t.min[3]), max = Vector(t.max[1], t.max[2], t.max[3]) }
	end
	if IsValid(Z.EditWin) and Z.EditWin.Rebuild then Z.EditWin.Rebuild() end
end)

local function icon(name) return UI.Mat("nyrp/zones/" .. name .. ".png") end

-- ------------------------------------------------------------- показ при входе --
local SHOW_TIME, CPS = 8, 16
local cur, show, nextCheck = nil, nil, 0

hook.Add("Think", "nyrp.zones", function()
	if RealTime() < nextCheck then return end
	nextCheck = RealTime() + 0.3
	local ply = LocalPlayer()
	if not IsValid(ply) or NYRP.State ~= "playing" or not ply:Alive() then cur = nil return end
	local z = Z.At(ply:GetPos())
	if z ~= cur then
		cur = z
		if z and (not show or show.z ~= z or RealTime() - show.born > SHOW_TIME) then
			show = { z = z, born = RealTime(), typed = 0, len = utf8.len(z.name) or #z.name }
		end
	end
end)

local function utf8sub(s, n)
	if n <= 0 then return "" end
	local off = utf8.offset(s, n + 1)
	return off and string.sub(s, 1, off - 1) or s
end

hook.Add("HUDPaint", "nyrp.zones", function()
	if not show or (NYRP.HUDHidden and NYRP.HUDHidden()) then return end
	local t = RealTime() - show.born
	if t > SHOW_TIME then show = nil return end
	local a = math.min(1, t / 0.35) * math.Clamp((SHOW_TIME - t) / 0.7, 0, 1)
	-- печатная машинка: буква за буквой со щелчком
	local n = math.Clamp(math.floor((t - 0.45) * CPS), 0, show.len)
	if n > show.typed then
		local ch = utf8sub(show.z.name, n)
		local last = string.sub(ch, -1)
		if last ~= " " then surface.PlaySound("nyrp/fx/type.wav") end
		show.typed = n
		if n == show.len then timer.Simple(0.15, function() surface.PlaySound("nyrp/fx/zone_bell.wav") end) end
	end
	local x, y = UI.S(46), ScrH() * 0.5
	local r = UI.S(34)
	local pop = UI.Ease(math.min(1, t / 0.45))
	surface.SetAlphaMultiplier(a)
	UI.Glow(x + r, y, r * 5, r * 4, Color(0, 0, 0, 160))
	UI.Circle(x + r, y, r * pop, Color(12, 14, 22, 235))
	UI.Ring(x + r, y, r * pop, GOLD)
	surface.SetMaterial(icon(show.z.icon))
	surface.SetDrawColor(GOLD)
	local is = UI.S(36) * pop
	surface.DrawTexturedRect(x + r - is / 2, y - is / 2, is, is)
	local tx = x + r * 2 + UI.S(18)
	draw.SimpleText("ЛОКАЦИЯ", NYRP.Font("bold", 13), tx, y - UI.S(26), Color(247, 198, 0, 220), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	local text = utf8sub(show.z.name, show.typed)
	local font = NYRP.Font("title", 38)
	draw.SimpleText(text, font, tx + 2, y + UI.S(6) + 2, Color(0, 0, 0, 170), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	draw.SimpleText(text, font, tx, y + UI.S(6), color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	-- каретка мигает, пока печатается
	local tw = UI.TextSize(text, font)
	if show.typed < show.len or math.floor(t * 2.5) % 2 == 0 then
		surface.SetDrawColor(GOLD)
		surface.DrawRect(tx + tw + UI.S(4), y - UI.S(10), UI.S(3), UI.S(30))
	end
	local full = UI.TextSize(show.z.name, font)
	surface.SetDrawColor(255, 255, 255, 60)
	surface.DrawRect(tx, y + UI.S(30), full * math.min(1, show.typed / math.max(show.len, 1)), 1)
	surface.SetAlphaMultiplier(1)
end)

-- --------------------------------------------------------------------- редактор --
local edit -- { stage = 1|2, a = Vector }

local function aimPoint()
	local ply = LocalPlayer()
	local tr = util.TraceLine({ start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * 600, filter = ply })
	return tr.HitPos
end

local function nameWindow(a, b)
	local chosen = Z.Icons[1]
	local win, body = UI.Window("Новая зона", "zone", 640, 620, { keyboard = true })
	local entry = vgui.Create("DTextEntry", body)
	entry:Dock(TOP)
	entry:SetTall(UI.S(42))
	entry:SetFont(NYRP.Font("semibold", 18))
	entry:SetPlaceholderText("Название, например «Бруклин — Флэтбуш»")
	entry:RequestFocus()
	local grid = vgui.Create("DIconLayout", body)
	grid:Dock(FILL)
	grid:DockMargin(0, UI.S(12), 0, UI.S(12))
	grid:SetSpaceX(UI.S(6))
	grid:SetSpaceY(UI.S(6))
	for _, name in ipairs(Z.Icons) do
		local b = grid:Add("DButton")
		b:SetText("")
		b:SetSize(UI.S(52), UI.S(52))
		b:SetTooltip(name)
		b:SetCursor("hand")
		b.DoClick = function() chosen = name UI.Sound("click") end
		b.Paint = function(s, w, h)
			local sel = chosen == name
			UI.RoundedRect(UI.S(8), 0, 0, w, h, sel and GOLD or (s:IsHovered() and Color(255, 255, 255, 24) or Color(255, 255, 255, 8)))
			surface.SetMaterial(icon(name))
			surface.SetDrawColor(sel and Color(14, 14, 18) or Color(230, 232, 240))
			surface.DrawTexturedRect(w / 2 - UI.S(15), h / 2 - UI.S(15), UI.S(30), UI.S(30))
		end
	end
	UI.AddButton(body, "Сохранить зону", "save", function()
		local name = string.Trim(entry:GetValue())
		if name == "" then UI.Sound("error") entry:RequestFocus() return end
		net.Start("nyrp.zones.save")
		net.WriteString(name)
		net.WriteString(chosen)
		net.WriteVector(a)
		net.WriteVector(b)
		net.SendToServer()
		win:Close()
	end, { dock = BOTTOM, style = "solid", accent = GOLD, h = 44 })
end

hook.Add("PlayerBindPress", "nyrp.zones.edit", function(ply, bind, pressed)
	if not edit or not pressed then return end
	if string.find(bind, "+attack2", 1, true) then edit = nil NYRP.Notify("Создание зоны отменено", "warning", 2) return true end
	if string.find(bind, "+attack", 1, true) then
		if edit.stage == 1 then
			edit.a = aimPoint()
			edit.stage = 2
			UI.Sound("click")
		else
			local a, b = edit.a, aimPoint()
			edit = nil
			UI.Sound("success")
			nameWindow(a, b)
		end
		return true
	end
end)

hook.Add("PostDrawTranslucentRenderables", "nyrp.zones.edit", function(depth, sky)
	if depth or sky then return end
	local admin = IsValid(LocalPlayer()) and LocalPlayer():IsAdmin()
	if edit then
		local p = aimPoint()
		render.SetColorMaterial()
		render.DrawSphere(edit.a or p, 6, 12, 12, Color(247, 198, 0, 200))
		if edit.stage == 2 then
			local mn = Vector(math.min(edit.a.x, p.x), math.min(edit.a.y, p.y), math.min(edit.a.z, p.z))
			local mx = Vector(math.max(edit.a.x, p.x), math.max(edit.a.y, p.y), math.max(edit.a.z, p.z))
			render.DrawBox(vector_origin, angle_zero, mn, mx, Color(247, 198, 0, 22))
			render.DrawWireframeBox(vector_origin, angle_zero, mn, mx, Color(247, 198, 0), false)
			render.DrawSphere(p, 6, 12, 12, Color(255, 255, 255, 200))
		end
	end
	-- при открытом редакторе видны все зоны
	if admin and (edit or IsValid(Z.EditWin)) then
		for _, z in ipairs(Z.List) do render.DrawWireframeBox(vector_origin, angle_zero, z.min, z.max, Color(120, 200, 255), false) end
	end
end)

hook.Add("HUDPaint", "nyrp.zones.edit", function()
	if not edit then return end
	local w = UI.S(520)
	local x, y = ScrW() / 2 - w / 2, UI.S(30)
	UI.RoundedRect(UI.S(12), x, y, w, UI.S(70), Color(10, 12, 20, 225))
	draw.SimpleText(edit.stage == 1 and "ЛКМ — первый угол зоны" or "Долетите до второго угла — ЛКМ", NYRP.Font("bold", 20), ScrW() / 2, y + UI.S(24), GOLD, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText("Точка — там, куда вы смотрите (noclip — V) · ПКМ — отмена", NYRP.Font("regular", 14), ScrW() / 2, y + UI.S(50), UI.Col.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)

net.Receive("nyrp.zones.edit", function()
	if IsValid(Z.EditWin) then Z.EditWin:Remove() end
	local win, body = UI.Window("Зоны карты", "zone", 520, 560, { sub = #Z.List .. " шт." })
	Z.EditWin = win
	UI.AddButton(body, "Новая зона", "plus", function()
		win:Close()
		edit = { stage = 1 }
	end, { style = "solid", accent = GOLD, h = 44 })
	local scroll = vgui.Create("DScrollPanel", body)
	scroll:Dock(FILL)
	win.Rebuild = function()
		scroll:Clear()
		for _, z in ipairs(Z.List) do
			local row = scroll:Add("DPanel")
			row:Dock(TOP)
			row:SetTall(UI.S(44))
			row:DockMargin(0, 0, 0, UI.S(6))
			row.Paint = function(_, w, h)
				UI.RoundedRect(UI.S(8), 0, 0, w, h, Color(255, 255, 255, 8))
				surface.SetMaterial(icon(z.icon))
				surface.SetDrawColor(GOLD)
				surface.DrawTexturedRect(UI.S(10), h / 2 - UI.S(12), UI.S(24), UI.S(24))
				draw.SimpleText(z.name, NYRP.Font("semibold", 15), UI.S(44), h / 2, UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
			local del = vgui.Create("NYRP.IconButton", row)
			del:Dock(RIGHT)
			del:SetWide(UI.S(40))
			del:SetIcon("trash")
			del.DoClick = function()
				UI.Confirm("Удалить зону", "Удалить «" .. z.name .. "»?", "Удалить", function()
					net.Start("nyrp.zones.del") net.WriteString(z.id) net.SendToServer()
				end)
			end
		end
	end
	win.Rebuild()
end)
