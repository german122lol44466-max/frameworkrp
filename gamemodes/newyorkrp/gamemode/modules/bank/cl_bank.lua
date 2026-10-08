--[[
	Банковская карта в инвентаре: «Посмотреть» — карта крупно (лицевая сторона: банк, чип, номер, держатель,
	срок; клик — перевернуть: магнитная полоса, подпись, CVV). Рядом — конверт с PIN-кодом.
]]

local UI = NYRP.UI
local B = NYRP.Bank

local function chip(x, y, w, h)
	draw.RoundedBox(UI.S(6), x, y, w, h, Color(214, 172, 70))
	surface.SetDrawColor(160, 120, 40)
	surface.DrawRect(x, y + h * 0.33, w, 1)
	surface.DrawRect(x, y + h * 0.66, w, 1)
	surface.DrawRect(x + w * 0.5, y, 1, h)
end

function B.ShowCard(d)
	if IsValid(B.CardPanel) then B.CardPanel:Remove() end
	d = d or {}
	local bank = B.Banks[d.bank] or B.Banks.liberty
	local bg = vgui.Create("EditablePanel")
	B.CardPanel = bg
	bg:SetSize(ScrW(), ScrH())
	bg:MakePopup()
	bg.Born = RealTime()
	bg.Flip, bg.FlipT = false, 0
	bg.Paint = function(s, w, h)
		local t = UI.Ease((RealTime() - s.Born) / 0.3)
		UI.BlurPanel(s, 5 * t)
		surface.SetDrawColor(4, 5, 10, 170 * t)
		surface.DrawRect(0, 0, w, h)
		draw.SimpleText("Клик по карте — перевернуть  ·  клик мимо или Esc — закрыть", NYRP.Font("regular", 14), w / 2, h / 2 + UI.S(250), Color(255, 255, 255, 90 * t), TEXT_ALIGN_CENTER)
	end
	bg.OnMousePressed = function(s) UI.Sound("close") s:Remove() end
	bg.OnKeyCodePressed = function(s, key) if key == KEY_ESCAPE or key == KEY_E or key == KEY_Q then s:Remove() end end

	local W, H = UI.S(560), UI.S(353)
	local card = vgui.Create("DPanel", bg)
	card:SetSize(W, H)
	card:SetPos(ScrW() / 2 - W / 2 - UI.S(110), ScrH() / 2 - H / 2)
	card:SetCursor("hand")
	card.OnMousePressed = function() bg.Flip = not bg.Flip UI.Sound("swipe") end
	card.Paint = function(s, w, h)
		bg.FlipT = UI.Approach(bg.FlipT, bg.Flip and 1 or 0, 5)
		local f = UI.EaseInOut(bg.FlipT)
		local sx = math.abs(math.cos(f * math.pi))     -- «поворот» карты: сжимаем по ширине
		local back = f > 0.5
		local cw = w * math.max(sx, 0.02)
		local x0 = (w - cw) / 2
		local m = Matrix()
		-- матрица применяется поверх смещения панели — переводим только внутри неё
		m:Translate(Vector(x0, 0, 0))
		m:Scale(Vector(math.max(sx, 0.02), 1, 1))
		render.PushFilterMag(TEXFILTER.ANISOTROPIC)
		render.PushFilterMin(TEXFILTER.ANISOTROPIC)
		cam.PushModelMatrix(m, true)
		-- тень и фон карты с градиентом цвета банка
		draw.RoundedBox(UI.S(22), UI.S(6), UI.S(8), w, h, Color(0, 0, 0, 120))
		draw.RoundedBox(UI.S(22), 0, 0, w, h, bank.dark)
		surface.SetMaterial(UI.Mat("vgui/gradient-r"))
		surface.SetDrawColor(bank.color.r, bank.color.g, bank.color.b, 200)
		surface.DrawTexturedRect(UI.S(10), 0, w - UI.S(20), h)
		-- волнистый узор
		for i = 0, 10 do
			surface.SetDrawColor(255, 255, 255, 10)
			local yy = h * 0.2 + i * UI.S(18)
			surface.DrawLine(0, yy + math.sin(i) * 10, w, yy - UI.S(40) + math.cos(i) * 10)
		end
		if not back then
			draw.SimpleText(bank.name, NYRP.Font("title", 30), UI.S(30), UI.S(26), color_white)
			draw.SimpleText("DEBIT", NYRP.Font("bold", 14), w - UI.S(30), UI.S(36), Color(255, 255, 255, 180), TEXT_ALIGN_RIGHT)
			chip(UI.S(36), UI.S(110), UI.S(64), UI.S(48))
			-- бесконтактный значок
			for k = 1, 3 do
				surface.SetDrawColor(255, 255, 255, 160)
				local r = UI.S(6) + k * UI.S(6)
				for a = -50, 50, 10 do
					local a1, a2 = math.rad(a), math.rad(a + 10)
					surface.DrawLine(UI.S(130) + math.cos(a1) * r, UI.S(134) + math.sin(a1) * r, UI.S(130) + math.cos(a2) * r, UI.S(134) + math.sin(a2) * r)
				end
			end
			draw.SimpleText(B.FormatCard(d.number), NYRP.Font("titlemed", 34), UI.S(34), UI.S(196), Color(240, 242, 250))
			draw.SimpleText("VALID THRU", NYRP.Font("bold", 9), UI.S(210), UI.S(250), Color(255, 255, 255, 160))
			draw.SimpleText(d.exp or "--/--", NYRP.Font("titlemed", 20), UI.S(210), UI.S(262), color_white)
			draw.SimpleText(d.holder or "", NYRP.Font("titlemed", 22), UI.S(34), h - UI.S(46), color_white)
			draw.SimpleText("VISA", NYRP.Font("title", 40), w - UI.S(30), h - UI.S(30), color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
		else
			surface.SetDrawColor(10, 10, 12)
			surface.DrawRect(0, UI.S(34), w, UI.S(58))
			draw.RoundedBox(UI.S(4), UI.S(30), UI.S(122), w * 0.6, UI.S(44), Color(236, 232, 220))
			for k = 0, 8 do
				surface.SetDrawColor(200, 190, 170)
				surface.DrawRect(UI.S(30), UI.S(126) + k * UI.S(4.5), w * 0.6, 1)
			end
			draw.SimpleText(d.holder or "", NYRP.Font("titlelight", 18), UI.S(40), UI.S(134), Color(40, 50, 90))
			draw.RoundedBox(UI.S(4), UI.S(30) + w * 0.6 + UI.S(10), UI.S(122), UI.S(70), UI.S(44), color_white)
			draw.SimpleText(d.cvv or "---", NYRP.Font("bold", 20), UI.S(30) + w * 0.6 + UI.S(45), UI.S(144), Color(20, 20, 30), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			draw.SimpleText("CVV", NYRP.Font("bold", 10), UI.S(30) + w * 0.6 + UI.S(45), UI.S(176), Color(255, 255, 255, 170), TEXT_ALIGN_CENTER)
			draw.SimpleText(bank.tag, NYRP.Font("regular", 13), UI.S(30), UI.S(200), Color(255, 255, 255, 170))
			draw.SimpleText("Карта является собственностью банка " .. bank.name .. ".", NYRP.Font("regular", 11), UI.S(30), h - UI.S(60), Color(255, 255, 255, 120))
			draw.SimpleText("Нашедшего просим вернуть в любое отделение.", NYRP.Font("regular", 11), UI.S(30), h - UI.S(44), Color(255, 255, 255, 120))
		end
		cam.PopModelMatrix()
		render.PopFilterMin()
		render.PopFilterMag()
	end

	-- конверт с PIN-кодом
	local env = vgui.Create("DPanel", bg)
	env:SetSize(UI.S(190), UI.S(240))
	env:SetPos(ScrW() / 2 + W / 2 - UI.S(80), ScrH() / 2 - UI.S(120))
	env.Paint = function(s, w, h)
		draw.RoundedBox(UI.S(6), UI.S(4), UI.S(6), w, h, Color(0, 0, 0, 100))
		draw.RoundedBox(UI.S(6), 0, 0, w, h, Color(240, 236, 226))
		surface.SetDrawColor(220, 214, 200)
		surface.DrawRect(0, UI.S(70), w, 1)
		draw.SimpleText(bank.name, NYRP.Font("title", 18), w / 2, UI.S(26), bank.color, TEXT_ALIGN_CENTER)
		draw.SimpleText("PIN-КОД", NYRP.Font("bold", 12), w / 2, UI.S(92), Color(110, 104, 92), TEXT_ALIGN_CENTER)
		draw.RoundedBox(UI.S(6), UI.S(20), UI.S(116), w - UI.S(40), UI.S(54), Color(40, 40, 48))
		draw.SimpleText(d.pin or "----", NYRP.Font("title", 34), w / 2, UI.S(143), color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		draw.SimpleText("Никому не сообщайте", NYRP.Font("regular", 11), w / 2, UI.S(186), Color(150, 60, 50), TEXT_ALIGN_CENTER)
		draw.SimpleText("•••• " .. string.sub(d.number or "", -4), NYRP.Font("semibold", 12), w / 2, UI.S(208), Color(120, 114, 100), TEXT_ALIGN_CENTER)
	end
end

hook.Add("NYRP.ItemView", "nyrp.bank", function(kind, key, it)
	if it.id ~= "bankcard" then return end
	B.ShowCard(it.data)
	UI.Sound("open")
	return true
end)
