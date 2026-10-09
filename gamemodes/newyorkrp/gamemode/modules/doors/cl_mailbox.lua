--[[
	Окно почтового ящика: номер ящика, ваши квартиры и кнопка «Забрать ключи».
]]

local UI = NYRP.UI

net.Receive("nyrp.mailbox", function()
	local ent, num, homes, has = net.ReadEntity(), net.ReadUInt(10), net.ReadTable(), net.ReadBool()
	if IsValid(NYRP.MailWin) then NYRP.MailWin:Remove() end
	local win, body = UI.Window("Почтовый ящик №" .. num, "mailbox", 440, 360)
	NYRP.MailWin = win
	local info = vgui.Create("DPanel", body)
	info:Dock(TOP)
	info:SetTall(UI.S(150))
	info.Paint = function(_, w, h)
		if #homes == 0 then
			draw.SimpleText("Ящик пуст.", NYRP.Font("bold", 18), 0, UI.S(10), UI.Col.text)
			local lines = UI.Wrap("Арендуйте квартиру в телефоне (NY Homes) или попросите арендатора поселить вас (F1 по его двери) — ключи придут сюда.", NYRP.Font("regular", 14), w)
			for i, l in ipairs(lines) do draw.SimpleText(l, NYRP.Font("regular", 14), 0, UI.S(40) + (i - 1) * UI.S(20), UI.Col.dim) end
			return
		end
		draw.SimpleText(has and "Ключи уже у вас." or "Внутри лежат ключи:", NYRP.Font("bold", 18), 0, UI.S(6), UI.Col.text)
		for i, hm in ipairs(homes) do
			local y = UI.S(38) + (i - 1) * UI.S(30)
			UI.DrawIcon("key", UI.S(12), y + UI.S(10), UI.S(18), UI.Col.accent)
			draw.SimpleText(hm.name, NYRP.Font("semibold", 15), UI.S(30), y, UI.Col.text)
			draw.SimpleText(hm.mine and "арендатор" or ("жилец · " .. hm.owner), NYRP.Font("regular", 12), w, y + UI.S(2), UI.Col.dim, TEXT_ALIGN_RIGHT)
		end
	end
	if #homes > 0 and not has then
		UI.AddButton(body, "Забрать ключи", "key", function()
			net.Start("nyrp.mailbox")
			net.WriteEntity(ent)
			net.SendToServer()
			win:Close()
		end, { dock = BOTTOM, style = "solid", accent = UI.Col.accent, h = 44 })
	end
end)
