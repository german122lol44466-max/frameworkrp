--[[
	Инвентарь на клиенте: данные рюкзака, быстрые слоты 4–7, подсказки «[E] подобрать», кольцо применения,
	кровотечение и микро-слоты слева снизу:
	  верхний ряд — экипировка (бронежилет, ПНВ, рация) и быстрые предметы с количеством;
	  нижний ряд — оружие, которое сейчас у бойца (модель оружия, патроны; активное подсвечено).
	Сам рюкзак (сетка, перетаскивание) — в меню Q (cl_charmenu.lua).
]]

local I = WS.Inv
local C = WS.Config
local UI = WS.UI
local E = WS.Ease

I.Mine = I.Mine or {}
local toasts = {}

net.Receive("ws.inv", function()
	local l = {}
	for k = 1, net.ReadUInt(6) do
		l[k] = { uid = net.ReadUInt(16), id = net.ReadString(), x = net.ReadUInt(4), y = net.ReadUInt(4), rot = net.ReadBool(),
			count = net.ReadUInt(10), charges = net.ReadUInt(4) }
	end
	I.Mine = l
	hook.Run("WSInventoryChanged", l)
end)

net.Receive("ws.inv.notify", function()
	toasts[#toasts + 1] = { text = net.ReadString(), t = RealTime() }
	WS.Audio.Play("whitesilence/menu/error.ogg", { volume = 0.4 })
end)

function I.Quick(key)
	local ply = LocalPlayer()
	if not ply:Alive() or not WS.Lobby.InGame(ply) then return end
	net.Start("ws.inv.quick")
	net.WriteUInt(key, 4)
	net.SendToServer()
end

function I.Use(it)
	net.Start("ws.inv.use") net.WriteUInt(it.uid, 16) net.SendToServer()
end

function I.Drop(it)
	net.Start("ws.inv.drop") net.WriteUInt(it.uid, 16) net.SendToServer()
end

function I.Move(it, x, y, rot)
	net.Start("ws.inv.move") net.WriteUInt(it.uid, 16) net.WriteUInt(x, 4) net.WriteUInt(y, 4) net.WriteBool(rot or false) net.SendToServer()
end

local function icon(n) return UI.Mat("whitesilence/icons/" .. n .. ".png", "smooth") end

-- ---------------------------------------------------------------- значок оружия (модель в окошке)

local wepModels = {}
local function weaponIcon(wep, x, y, w, h, alpha)
	local mdl = wep:GetWeaponWorldModel()
	if not mdl or mdl == "" then mdl = wep:GetModel() end
	if not mdl or mdl == "" then return end
	local e = wepModels[mdl]
	if not IsValid(e) then
		e = ClientsideModel(mdl, RENDERGROUP_OPAQUE)
		if not IsValid(e) then return end
		e:SetNoDraw(true)
		wepModels[mdl] = e
	end
	local mins, maxs = e:GetModelBounds()
	local center = (mins + maxs) * 0.5
	local size = math.max((maxs - mins):Length(), 1)
	local ang = Angle(4, -90, 0)
	cam.Start3D(center - ang:Forward() * size * 1.15, ang, 40, x, y, w, h, 1, size * 4)
		render.SuppressEngineLighting(true)
		render.SetColorModulation(alpha, alpha, alpha)
		render.ResetModelLighting(0.55, 0.57, 0.62)
		render.SetModelLighting(BOX_TOP, 1, 1, 1)
		render.SetModelLighting(BOX_FRONT, 0.8, 0.82, 0.86)
		e:DrawModel()
		render.SetColorModulation(1, 1, 1)
		render.SuppressEngineLighting(false)
	cam.End3D()
end

I.WeaponIcon = weaponIcon

-- ---------------------------------------------------------------- микро-слоты

local function slotBox(x, y, w, h, a, active, col)
	draw.RoundedBox(4, x, y, w, h, Color(8, 10, 14, (active and 200 or 150) * a))
	surface.SetDrawColor(col and col.r or 255, col and col.g or 255, col and col.b or 255, (active and 160 or 26) * a)
	surface.DrawOutlinedRect(x, y, w, h, 1)
	if active then
		surface.SetDrawColor(226, 190, 120, 230 * a)
		surface.DrawRect(x, y + h - 2, w, 2)
	end
end

local function drawSlots(ply, w, h, s, a)
	local x0 = 36 * s
	local bottom = h - 460 * s * 170 / 512 - 34 * s - 12 * s
	local cell = 50 * s
	local gap = 6 * s
	-- нижний ряд: оружие
	local wy = bottom - 62 * s
	local wx = x0
	local active = ply:GetActiveWeapon()
	for i, wep in ipairs(ply:GetWeapons()) do
		if i > 4 then break end
		local isA = wep == active
		local ww = 118 * s
		slotBox(wx, wy, ww, 62 * s, a, isA)
		weaponIcon(wep, wx + 4 * s, wy + 2 * s, ww - 8 * s, 44 * s, isA and 1 or 0.55)
		draw.SimpleText(tostring(i), WS.Font("menusemi", 13), wx + 6 * s, wy + 4 * s, Color(226, 190, 120, 220 * a))
		local clip, res = wep:Clip1(), ply:GetAmmoCount(wep:GetPrimaryAmmoType())
		local txt = clip >= 0 and string.format("%d / %d", clip, res) or ""
		draw.SimpleText(txt, WS.Font("menusemi", 13), wx + ww - 6 * s, wy + 62 * s - 6 * s,
			Color(236, 240, 246, (isA and 240 or 150) * a), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
		wx = wx + ww + gap
	end
	-- верхний ряд: экипировка и быстрые предметы
	local ey = wy - cell - gap
	local ex = x0
	local function equip(ic, value, col, frac)
		slotBox(ex, ey, cell, cell, a, false, col)
		surface.SetMaterial(icon(ic))
		surface.SetDrawColor(col.r, col.g, col.b, 230 * a)
		surface.DrawTexturedRect(ex + cell * 0.22, ey + cell * 0.14, cell * 0.56, cell * 0.56)
		if frac then
			surface.SetDrawColor(255, 255, 255, 30 * a)
			surface.DrawRect(ex + 5 * s, ey + cell - 7 * s, cell - 10 * s, 3 * s)
			surface.SetDrawColor(col.r, col.g, col.b, 230 * a)
			surface.DrawRect(ex + 5 * s, ey + cell - 7 * s, (cell - 10 * s) * math.Clamp(frac, 0, 1), 3 * s)
		elseif value then
			draw.SimpleText(value, WS.Font("menusemi", 12), ex + cell - 4 * s, ey + cell - 3 * s, Color(236, 240, 246, 220 * a), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
		end
		ex = ex + cell + gap
	end
	equip("armor", tostring(ply:Armor()), Color(150, 196, 236), ply:Armor() / 100)
	local V = WS.Vision
	equip("nvg", nil, V and V.Mode and Color(140, 230, 160) or Color(200, 206, 214), V and V.Battery / C.NVGBattery or 1)
	equip("radio", "", Color(200, 206, 214))
	ex = ex + gap * 2
	-- быстрые предметы
	for key = 4, 7 do
		local id
		for iid, d in pairs(I.Items) do if d.quick == key then id = iid end end
		local n = 0
		for _, it in ipairs(I.Mine) do
			if it.id == id then n = n + (I.Items[id].charges and (it.charges > 0 and it.charges or 1) or it.count) end
		end
		local using = ply:GetNW2Float("ws_using_until", 0) > CurTime() and ply:GetNW2String("ws_using_item", "") == id
		slotBox(ex, ey, cell, cell, a, using)
		WS.Props.DrawIcon(I.Items[id].mesh, ex + 3 * s, ey + 3 * s, cell - 6 * s, cell - 10 * s)
		if n == 0 then
			surface.SetDrawColor(8, 10, 14, 170 * a)
			surface.DrawRect(ex + 1, ey + 1, cell - 2, cell - 2)
		end
		draw.SimpleText(tostring(key), WS.Font("menusemi", 12), ex + 4 * s, ey + 2 * s, Color(226, 190, 120, 220 * a))
		draw.SimpleText("×" .. n, WS.Font("menusemi", 12), ex + cell - 4 * s, ey + cell - 3 * s,
			Color(236, 240, 246, (n > 0 and 230 or 90) * a), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
		ex = ex + cell + gap
	end
	-- состояние: кровотечение, обезболивание, перегруз
	local tags = {}
	local b = ply:GetNW2Int("ws_bleed", 0)
	if b > 0 then tags[#tags + 1] = { ({ "Кровотечение", "Сильное кровотечение", "Обильное кровотечение" })[b], Color(230, 80, 70) } end
	if ply:GetNW2Float("ws_pain_until", 0) > CurTime() then tags[#tags + 1] = { "Обезболен", Color(150, 210, 160) } end
	local wt = ply:GetNW2Float("ws_weight", 0)
	if wt > I.CarryLight then tags[#tags + 1] = { string.format("Перегруз %.1f кг", wt), Color(226, 190, 120) } end
	local ty = ey - 8 * s
	for _, t in ipairs(tags) do
		draw.SimpleText(WS.Upper(t[1]), WS.Font("menusemi", 14), x0, ty, Color(t[2].r, t[2].g, t[2].b, 230 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
		ty = ty - 18 * s
	end
end

-- ---------------------------------------------------------------- подсказки и кольцо применения

local function lookItem(ply)
	local tr = util.TraceLine({ start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * 95, filter = ply, mask = MASK_SHOT })
	local e = tr.Entity
	if IsValid(e) and (e:GetClass() == "ws_item" or e:GetClass() == "ws_crate") then return e end
	-- маленькие предметы трудно навести — ищем рядом с точкой взгляда
	for _, x in ipairs(ents.FindInSphere(tr.HitPos, 14)) do
		if x:GetClass() == "ws_item" then return x end
	end
end

local function ring(cx, cy, r, th, frac, col)
	draw.NoTexture()
	surface.SetDrawColor(col)
	local segs = 48
	for i = 0, math.floor(segs * frac) - 1 do
		local a0, a1 = math.rad(-90 + i / segs * 360), math.rad(-90 + (i + 1) / segs * 360)
		surface.DrawPoly({
			{ x = cx + math.cos(a0) * r, y = cy + math.sin(a0) * r }, { x = cx + math.cos(a1) * r, y = cy + math.sin(a1) * r },
			{ x = cx + math.cos(a1) * (r - th), y = cy + math.sin(a1) * (r - th) }, { x = cx + math.cos(a0) * (r - th), y = cy + math.sin(a0) * (r - th) },
		})
	end
end

local bleedPulse = 0
hook.Add("HUDPaint", "ws.inv", function()
	local ply = LocalPlayer()
	if not IsValid(ply) or not (WS.HUD and WS.HUD.Visible()) then return end
	local w, h = ScrW(), ScrH()
	local s = h / 1080
	local a = WS.HUD.Alpha or 1

	-- кровотечение: тёмно-красные края, пульсом
	local b = ply:GetNW2Int("ws_bleed", 0)
	if b > 0 then
		bleedPulse = bleedPulse + FrameTime() * (1.5 + b)
		local k = (0.5 + 0.5 * math.sin(bleedPulse)) * (0.25 + b * 0.18)
		surface.SetMaterial(UI.Mat(WS.Intro.Path .. "vignette.png", "smooth"))
		surface.SetDrawColor(120, 0, 0, 255 * k * a)
		surface.DrawTexturedRect(0, 0, w, h)
	end

	drawSlots(ply, w, h, s, a)

	-- применение предмета
	local untilT = ply:GetNW2Float("ws_using_until", 0)
	if untilT > CurTime() then
		local dur = math.max(ply:GetNW2Float("ws_using_dur", 1), 0.1)
		local f = 1 - (untilT - CurTime()) / dur
		ring(w / 2, h / 2, 34 * s, 3 * s, 1, Color(255, 255, 255, 40))
		ring(w / 2, h / 2, 34 * s, 3 * s, f, Color(140, 210, 160, 240))
		local d = I.Items[ply:GetNW2String("ws_using_item", "")]
		draw.SimpleText(WS.Upper(d and d.name or ""), WS.Font("menusemi", 17), w / 2, h / 2 + 46 * s, Color(240, 242, 246, 230), TEXT_ALIGN_CENTER)
	else
		-- подсказка подобрать
		local e = lookItem(ply)
		if e and ply:GetNW2Float("ws_use", 0) <= 0 then
			local text
			if e:GetClass() == "ws_crate" then
				text = e:GetOpened() and "Ящик пуст" or "[E] удерживать — открыть ящик"
			else
				local d = I.Items[e:GetItemId()]
				if d then
					text = "[E]  " .. d.name .. ((e:GetCount() > 1) and ("  ×" .. e:GetCount()) or "")
				end
			end
			if text then
				draw.SimpleTextOutlined(text, WS.Font("menusemi", 18), w / 2, h / 2 + 40 * s, Color(240, 242, 246, 235), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 160))
			end
		end
	end

	-- уведомления («Нет места», «Слишком тяжело»)
	local ty = h * 0.62
	for i = #toasts, 1, -1 do
		local t = toasts[i]
		local age = RealTime() - t.t
		if age > 2.5 then table.remove(toasts, i)
		else
			local k = E.Window(age, 0, 0.2, 2, 2.5)
			draw.SimpleTextOutlined(t.text, WS.Font("menusemi", 20), w / 2, ty, Color(230, 120, 100, 255 * k), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 160 * k))
			ty = ty + 26 * s
		end
	end
end)
