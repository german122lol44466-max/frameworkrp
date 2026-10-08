--[[
	Редактор расстановки персонажей (только суперадмин): nyrp_chareditor
	Камера встаёт в точку выбора персонажей, на местах стоят модели.
	Клик по модели — выбор (обводка), справа панель: сдвиг по осям, поворот, добавить/удалить, сохранить.
]]

local UI = NYRP.UI
local Chars = NYRP.Chars
local E = {}
NYRP.Editor = E

local function V(t) return Vector(t[1], t[2], t[3]) end

function E.Close()
	Chars.EditorActive = false
	for _, s in ipairs(E.Spots or {}) do if IsValid(s.ent) then s.ent:Remove() end end
	E.Spots = nil
	if IsValid(E.Panel) then E.Panel:Remove() end
end

local function makeEnt(spot)
	local ent = ClientsideModel(NYRP.Config.Models.male[1], RENDERGROUP_OPAQUE)
	ent:SetPos(spot.pos)
	ent:SetAngles(Angle(0, spot.yaw, 0))
	local seq = ent:LookupSequence("idle_all_01")
	if seq >= 0 then ent:ResetSequence(seq) end
	return ent
end

function E.Open()
	if not LocalPlayer():IsSuperAdmin() then NYRP.Notify("Только для суперадминов", "error") return end
	local P = NYRP.ClientPoints
	if not P.chars then
		NYRP.Notify("Сначала поставьте камеру выбора: nyrp_point chars set", "warning", 8)
		return
	end
	E.Close()
	Chars.EditorActive = true
	E.Cam = { pos = V(P.chars.pos), ang = Angle(P.chars.ang[1], P.chars.ang[2], P.chars.ang[3]) }
	E.Spots = {}
	for _, s in ipairs(P.spots or {}) do
		local spot = { pos = V(s.pos), yaw = s.ang[2] }
		spot.ent = makeEnt(spot)
		E.Spots[#E.Spots + 1] = spot
	end
	E.Selected = E.Spots[1]

	local pnl = vgui.Create("EditablePanel")
	E.Panel = pnl
	pnl:SetSize(ScrW(), ScrH())
	pnl:MakePopup()
	pnl:SetKeyboardInputEnabled(false)
	pnl.Paint = function(_, w, h)
		draw.SimpleText("РЕДАКТОР РАССТАНОВКИ", NYRP.Font("title", 30), UI.S(40), UI.S(30), UI.Col.text)
		draw.SimpleText("Клик по модели — выбрать. Мест: " .. #E.Spots, NYRP.Font("regular", 16), UI.S(42), UI.S(70), UI.Col.dim)
		for i, s in ipairs(E.Spots) do
			if IsValid(s.ent) then
				local sc = (s.pos + Vector(0, 0, 82)):ToScreen()
				UI.Circle(sc.x, sc.y, UI.S(14), s == E.Selected and UI.Col.accent or Color(255, 255, 255, 220))
				draw.SimpleText(i, NYRP.Font("bold", 15), sc.x, sc.y, UI.Col.black, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		end
	end
	pnl.OnMousePressed = function(_, code)
		if code ~= MOUSE_LEFT then return end
		local dir = Chars.ScreenRay(E.Cam.ang, 70, gui.MouseX(), gui.MouseY())
		for _, s in ipairs(E.Spots) do
			local mn, mx = s.ent:GetModelBounds()
			if util.IntersectRayWithOBB(E.Cam.pos, dir * 4000, s.ent:GetPos(), s.ent:GetAngles(), mn, mx) then
				E.Selected = s
				UI.Sound("click")
				return
			end
		end
	end

	local side = vgui.Create("DPanel", pnl)
	side:SetSize(UI.S(360), UI.S(560))
	side:SetPos(ScrW() - UI.S(400), ScrH() / 2 - UI.S(280))
	side.Paint = function(_, w, h)
		UI.RoundedRect(UI.S(14), 0, 0, w, h, Color(10, 12, 20, 230))
		UI.Outline(UI.S(14), 0, 0, w, h, UI.Col.stroke, 1)
		local idx = table.KeyFromValue(E.Spots, E.Selected)
		draw.SimpleText(idx and ("Место #" .. idx) or "Ничего не выбрано", NYRP.Font("title", 22), UI.S(20), UI.S(18), UI.Col.text)
		if E.Selected then
			local p = E.Selected.pos
			draw.SimpleText(string.format("%.0f  %.0f  %.0f   поворот %.0f°", p.x, p.y, p.z, E.Selected.yaw), NYRP.Font("regular", 14), UI.S(20), UI.S(50), UI.Col.dim)
		end
	end
	local y = UI.S(80)
	local function nudge(label, vec)
		local row = vgui.Create("DPanel", side)
		row:SetPos(UI.S(20), y)
		row:SetSize(UI.S(320), UI.S(40))
		row.Paint = function(_, w, h) draw.SimpleText(label, NYRP.Font("semibold", 16), 0, h / 2, UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
		for i, step in ipairs({ -5, -1, 1, 5 }) do
			local b = vgui.Create("NYRP.Button", row)
			b:SetSize(UI.S(54), UI.S(34))
			b:SetPos(UI.S(90) + (i - 1) * UI.S(58), UI.S(3))
			b:SetLabel((step > 0 and "+" or "") .. step)
			b:SetAlign(TEXT_ALIGN_CENTER)
			b:SetFontStyle("semibold", 15)
			b.DoClick = function()
				local s = E.Selected
				if not s then return end
				if vec == "yaw" then s.yaw = (s.yaw + step * 3) % 360 else s.pos = s.pos + vec * step end
				s.ent:SetPos(s.pos)
				s.ent:SetAngles(Angle(0, s.yaw, 0))
			end
		end
		y = y + UI.S(46)
	end
	nudge("Вперёд/назад", Vector(1, 0, 0))
	nudge("Влево/вправо", Vector(0, 1, 0))
	nudge("Высота", Vector(0, 0, 1))
	nudge("Поворот ×3°", "yaw")

	local function btn(label, icon, style, fn)
		local b = vgui.Create("NYRP.Button", side)
		b:SetSize(UI.S(320), UI.S(44))
		b:SetPos(UI.S(20), y)
		b:SetLabel(label)
		b:SetIcon(icon)
		if style then b:SetStyle(style) end
		b.DoClick = fn
		y = y + UI.S(52)
	end
	y = y + UI.S(10)
	btn("Добавить место в центр кадра", "plus", nil, function()
		local tr = util.TraceLine({ start = E.Cam.pos, endpos = E.Cam.pos + E.Cam.ang:Forward() * 3000, mask = MASK_SOLID_BRUSHONLY })
		local spot = { pos = tr.HitPos, yaw = (E.Cam.pos - tr.HitPos):Angle().y }
		spot.ent = makeEnt(spot)
		E.Spots[#E.Spots + 1] = spot
		E.Selected = spot
	end)
	btn("Удалить выбранное", "trash", "ghost", function()
		local s = E.Selected
		if not s then return end
		s.ent:Remove()
		table.RemoveByValue(E.Spots, s)
		E.Selected = E.Spots[1]
	end)
	btn("Сохранить", "save", "solid", function()
		local out = {}
		for _, s in ipairs(E.Spots) do out[#out + 1] = { pos = { s.pos.x, s.pos.y, s.pos.z }, ang = { 0, s.yaw, 0 } } end
		net.Start("nyrp.points.save")
		net.WriteTable(out)
		net.SendToServer()
	end)
	btn("Закрыть", "close", "ghost", E.Close)
end
concommand.Add("nyrp_chareditor", E.Open)

hook.Add("NYRP.CalcView", "nyrp.editor", function()
	if Chars.EditorActive and E.Cam then
		return { origin = E.Cam.pos, angles = E.Cam.ang, fov = 70, drawviewer = true }
	end
end)

hook.Add("PreDrawHalos", "nyrp.editor", function()
	if Chars.EditorActive and E.Selected and IsValid(E.Selected.ent) then
		halo.Add({ E.Selected.ent }, UI.Col.accent, 2, 2, 2, true, false)
	end
end)
