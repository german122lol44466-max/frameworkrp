--[[
	Удостоверение личности штата Нью-Йорк: красивая карточка со всеми данными персонажа.
	NYRP.ShowPassport(data, fromPly) — data из предмета idcard.
]]

local UI = NYRP.UI

local function field(label, value, x, y, w, valueFont, valueCol)
	draw.SimpleText(label, NYRP.Font("semibold", 11), x, y, Color(90, 100, 125))
	draw.SimpleText(value, valueFont or NYRP.Font("bold", 18), x, y + UI.S(14), valueCol or Color(20, 26, 44))
end

function NYRP.ShowPassport(d, from)
	if IsValid(NYRP.PassportPanel) then NYRP.PassportPanel:Remove() end
	d = d or {}
	local bg = vgui.Create("EditablePanel")
	NYRP.PassportPanel = bg
	bg:SetSize(ScrW(), ScrH())
	bg:MakePopup()
	bg.Born = RealTime()
	bg.Paint = function(s, w, h)
		local t = UI.Ease((RealTime() - s.Born) / 0.3)
		UI.BlurPanel(s, 5 * t)
		surface.SetDrawColor(4, 5, 10, 170 * t)
		surface.DrawRect(0, 0, w, h)
		if IsValid(from) then
			draw.SimpleText("Вам показывают удостоверение", NYRP.Font("title", 26), w / 2, h / 2 - UI.S(270), Color(255, 255, 255, 220 * t), TEXT_ALIGN_CENTER)
		end
		draw.SimpleText("Нажмите в любом месте, чтобы закрыть", NYRP.Font("regular", 14), w / 2, h / 2 + UI.S(260), Color(255, 255, 255, 90 * t), TEXT_ALIGN_CENTER)
	end
	bg.OnMousePressed = function(s) UI.Sound("close") s:Remove() end
	bg.OnKeyCodePressed = function(s, key)
		if key == KEY_ESCAPE or key == KEY_E or key == KEY_Q then s:Remove() end
	end

	local W, H = UI.S(720), UI.S(454)
	local card = vgui.Create("DPanel", bg)
	card:SetSize(W, H)
	card:Center()
	card.Born = RealTime()
	card.OnMousePressed = function() bg:Remove() end
	local surname, given = string.match(d.name or "", "^(%S+)%s+(.+)$")
	given = given or ""
	surname = surname or (d.name or "")
	card.Paint = function(s, w, h)
		local t = UI.Ease((RealTime() - s.Born) / 0.45)
		local r = UI.S(20)
		UI.Masked(r, 0, 0, w, h, function()
			surface.SetDrawColor(236, 239, 244)
			surface.DrawRect(0, 0, w, h)
			-- гильош: тонкие волны
			for i = 0, 26 do
				local yy = UI.S(110) + i * UI.S(13)
				local prevx, prevy
				for x = 0, w, UI.S(12) do
					local y = yy + math.sin(x / UI.S(40) + i * 0.7) * UI.S(6)
					if prevx then
						surface.SetDrawColor(120, 150, 210, 26)
						surface.DrawLine(prevx, prevy, x, y)
					end
					prevx, prevy = x, y
				end
			end
			-- шапка
			surface.SetDrawColor(18, 30, 68)
			surface.DrawRect(0, 0, w, UI.S(86))
			surface.SetDrawColor(247, 198, 0)
			surface.DrawRect(0, UI.S(86), w, UI.S(7))
			draw.SimpleText("STATE OF NEW YORK", NYRP.Font("title", 30), UI.S(30), UI.S(16), color_white)
			draw.SimpleText("ШТАТ НЬЮ-ЙОРК · УДОСТОВЕРЕНИЕ ЛИЧНОСТИ", NYRP.Font("semibold", 13), UI.S(32), UI.S(56), Color(190, 200, 230))
			draw.SimpleText("IDENTIFICATION CARD", NYRP.Font("titlemed", 18), w - UI.S(30), UI.S(28), Color(247, 198, 0), TEXT_ALIGN_RIGHT)
			draw.SimpleText("NOT A DRIVER LICENSE", NYRP.Font("semibold", 11), w - UI.S(30), UI.S(56), Color(150, 160, 200), TEXT_ALIGN_RIGHT)
			-- печать
			UI.Circle(w - UI.S(78), h - UI.S(84), UI.S(46), Color(247, 198, 0, 60))
			UI.Ring(w - UI.S(78), h - UI.S(84), UI.S(46), Color(200, 150, 0, 120))
			draw.SimpleText("NY", NYRP.Font("title", 34), w - UI.S(78), h - UI.S(84), Color(160, 115, 0, 160), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			-- голограмма: бегущий блик
			local sx = ((RealTime() * 260) % (w * 2)) - w * 0.5
			surface.SetMaterial(UI.Mat("vgui/gradient-r"))
			surface.SetDrawColor(255, 255, 255, 60)
			surface.DrawTexturedRect(sx, 0, UI.S(120), h)
			surface.SetMaterial(UI.Mat("vgui/gradient-l"))
			surface.DrawTexturedRect(sx + UI.S(120), 0, UI.S(120), h)
			-- машиночитаемая строка
			surface.SetDrawColor(18, 30, 68, 20)
			surface.DrawRect(0, h - UI.S(46), w, UI.S(46))
			local mrz = "IDUSA<NY<" .. string.upper(string.gsub(d.number or "", "-", "<")) .. "<<<<<<<<<<<<<<<<<<"
			draw.SimpleText(string.sub(mrz, 1, 44), NYRP.Font("semibold", 17), UI.S(30), h - UI.S(23), Color(40, 50, 80, 180), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end)
		-- фото
		local px, py, pw, ph = UI.S(30), UI.S(112), UI.S(178), UI.S(222)
		UI.RoundedRect(UI.S(8), px, py, pw, ph, Color(160, 178, 205))
		-- поля
		local fx = UI.S(234)
		field("ФАМИЛИЯ / SURNAME", surname, fx, UI.S(112), w)
		field("ИМЯ / GIVEN NAME", given ~= "" and given or "—", fx, UI.S(160), w)
		field("ПОЛ / SEX", d.gender == "female" and "Ж / F" or "М / M", fx, UI.S(208), w)
		field("РОСТ / HGT", (d.height or "?") .. " см", fx + UI.S(130), UI.S(208), w)
		field("ВЫДАНО / ISS", d.issued or "—", fx + UI.S(260), UI.S(208), w)
		field("НОМЕР / ID NO.", d.number or "—", fx, UI.S(256), w, NYRP.Font("bold", 20), Color(176, 30, 40))
		draw.SimpleText("ПРИМЕТЫ / DESCRIPTION", NYRP.Font("semibold", 11), fx, UI.S(306), Color(90, 100, 125))
		local lines = UI.Wrap(d.desc or "", NYRP.Font("medium", 13), w - fx - UI.S(150))
		for i = 1, math.min(#lines, 3) do
			draw.SimpleText(lines[i], NYRP.Font("medium", 13), fx, UI.S(322) + (i - 1) * UI.S(16), Color(40, 48, 70))
		end
		-- подпись
		draw.SimpleText(d.name or "", NYRP.Font("titlelight", 22), px + UI.S(4), py + ph + UI.S(6), Color(30, 40, 90, 200))
		s:SetAlpha(255 * t)
	end

	-- фото: лицо модели персонажа
	if d.model then
		local photo = vgui.Create("DModelPanel", card)
		photo:SetPos(UI.S(30), UI.S(112))
		photo:SetSize(UI.S(178), UI.S(222))
		photo:SetModel(d.model)
		photo:SetFOV(18)
		photo:SetMouseInputEnabled(false)
		local ent = photo:GetEntity()
		local head
		if IsValid(ent) then
			local seq = ent:LookupSequence("idle_all_01")
			if seq >= 0 then ent:ResetSequence(seq) end
			local bone = ent:LookupBone("ValveBiped.Bip01_Head1")
			ent:SetupBones()
			head = bone and ent:GetBonePosition(bone) or Vector(0, 0, 62)
		end
		head = head or Vector(0, 0, 62)
		photo:SetLookAt(head + Vector(0, 0, 1))
		photo:SetCamPos(head + Vector(70, 0, 4))
		photo.LayoutEntity = function(_, e) e:SetAngles(Angle(0, 0, 0)) end
		photo:SetAmbientLight(Color(120, 120, 130))
		photo:SetDirectionalLight(BOX_FRONT, Color(255, 250, 240))
	end
	UI.Sound("open")
end

net.Receive("nyrp.inv.view", function()
	local from = net.ReadEntity()
	local data = net.ReadTable()
	NYRP.ShowPassport(data, from)
end)
