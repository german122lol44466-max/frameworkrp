--[[
	Записки и письма на клиенте: бумажное окно письма (блокнот, конверт), чтение записки/письма,
	пункт «Передать человеку» в меню предмета, кнопка «Письма» в окне почтового ящика (modules/doors).
]]

local W = NYRP.Writing
local UI = NYRP.UI

local PAPER = Color(242, 234, 212)
local PAPER2 = Color(232, 222, 196)
local INK = Color(34, 38, 58)
local INK_DIM = Color(110, 104, 92)
local LINE = Color(120, 150, 200, 55)
local MARGIN = Color(210, 90, 80, 90)

-- ---------------------------------------------------------- общий фон --
local function backdrop(onClose)
	if IsValid(W.Panel) then W.Panel:Remove() end
	local bg = vgui.Create("EditablePanel")
	W.Panel = bg
	bg:SetSize(ScrW(), ScrH())
	bg:MakePopup()
	bg.Born = RealTime()
	bg.Paint = function(s, w, h)
		local t = UI.Ease((RealTime() - s.Born) / 0.25)
		if s.Closing then t = t * (1 - UI.Ease((RealTime() - s.Closing) / 0.2)) end
		s:SetAlpha(255 * t)
		UI.BlurPanel(s, 5)
		surface.SetDrawColor(4, 5, 10, 170)
		surface.DrawRect(0, 0, w, h)
	end
	function bg:Close()
		if self.Closing then return end
		self.Closing = RealTime()
		self:SetMouseInputEnabled(false)
		self:SetKeyboardInputEnabled(false)
		UI.Sound("close")
		if onClose then onClose() end
		timer.Simple(0.2, function() if IsValid(self) then self:Remove() end end)
	end
	bg.OnMousePressed = function(s) s:Close() end
	bg.OnKeyCodePressed = function(s, k) if k == KEY_ESCAPE then s:Close() end end
	bg.Think = function(s)
		if gui.IsGameUIVisible() and not s.Closing then gui.HideGameUI() s:Close() end
		if not LocalPlayer():Alive() and not s.Closing then s:Close() end
	end
	surface.PlaySound("physics/cardboard/cardboard_box_impact_soft" .. math.random(1, 7) .. ".wav")
	return bg
end

-- лист бумаги: линейки, поле, лёгкая тень
local function paintPaper(x, y, w, h, lineTop, lineH)
	UI.RoundedRect(UI.S(6), x + UI.S(6), y + UI.S(8), w, h, Color(0, 0, 0, 90))
	UI.RoundedRect(UI.S(6), x, y, w, h, PAPER)
	surface.SetMaterial(UI.Mat("vgui/gradient-u"))
	surface.SetDrawColor(PAPER2)
	surface.DrawTexturedRect(x, y + h * 0.5, w, h * 0.5)
	if lineH then
		surface.SetDrawColor(LINE)
		for ly = y + lineTop, y + h - UI.S(20), lineH do surface.DrawRect(x + UI.S(16), ly, w - UI.S(32), 1) end
	end
	surface.SetDrawColor(MARGIN)
	surface.DrawRect(x + UI.S(54), y, 1, h)
end

-- поле ввода «чернилами по бумаге»
local function inkEntry(parent, font, multiline, placeholder)
	local e = vgui.Create("DTextEntry", parent)
	e:SetFont(font)
	e:SetMultiline(multiline)
	e:SetPaintBackground(false)
	e:SetDrawLanguageID(false)
	e:SetPlaceholderText(placeholder)
	e.Paint = function(s, w, h)
		if s:GetText() == "" and placeholder then
			draw.SimpleText(placeholder, font, UI.S(3), multiline and UI.S(2) or h / 2, Color(INK_DIM.r, INK_DIM.g, INK_DIM.b, 140),
				TEXT_ALIGN_LEFT, multiline and TEXT_ALIGN_TOP or TEXT_ALIGN_CENTER)
		end
		s:DrawTextEntryText(INK, Color(120, 150, 220, 120), INK)
		return true
	end
	return e
end

local function ulen(s) return utf8.len(s or "") or #(s or "") end

-- подпись: своё имя / свой текст / без подписи
local function signRow(parent, x, y, w)
	local row = vgui.Create("DPanel", parent)
	row:SetPos(x, y)
	row:SetSize(w, UI.S(34))
	row.Paint = function() end
	row.Mode = 1
	local custom = inkEntry(row, NYRP.Font("semibold", 15), false, "ваша подпись")
	custom:SetVisible(false)
	local opts = { { 1, "Своё имя" }, { 2, "Подпись..." }, { 0, "Без подписи" } }
	local bx = 0
	for _, o in ipairs(opts) do
		local b = vgui.Create("DButton", row)
		b:SetText("")
		local tw = UI.TextSize(o[2], NYRP.Font("semibold", 12)) + UI.S(20)
		b:SetPos(bx, UI.S(4))
		b:SetSize(tw, UI.S(26))
		bx = bx + tw + UI.S(6)
		b.Paint = function(s, bw, bh)
			local on = row.Mode == o[1]
			UI.RoundedRect(bh / 2, 0, 0, bw, bh, on and Color(34, 38, 58, 230) or Color(34, 38, 58, s:IsHovered() and 40 or 18))
			draw.SimpleText(o[2], NYRP.Font("semibold", 12), bw / 2, bh / 2, on and PAPER or INK, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			return true
		end
		b.DoClick = function()
			UI.Sound("click")
			row.Mode = o[1]
			custom:SetVisible(o[1] == 2)
			if o[1] == 2 then custom:RequestFocus() end
		end
	end
	custom:SetPos(bx + UI.S(6), 0)
	custom:SetSize(w - bx - UI.S(6), UI.S(34))
	custom.OnChange = function(s)
		if ulen(s:GetText()) > W.MaxSign then s:SetText(string.sub(s:GetText(), 1, utf8.offset(s:GetText(), W.MaxSign + 1) - 1)) s:SetCaretPos(#s:GetText()) end
	end
	row.Custom = custom
	return row
end

-- ---------------------------------------------------- окно письма --
-- opts: { title = "Записка", notebook = slot | envelope = slot, pages = n }
local function openWrite(opts)
	local bg = backdrop()
	local addrW = opts.envelope and UI.S(280) or 0
	local W0, H0 = UI.S(620), UI.S(720)
	local total = W0 + (addrW > 0 and addrW + UI.S(20) or 0)
	local box = vgui.Create("EditablePanel", bg)
	box:SetSize(total, H0 + UI.S(64))
	box:Center()
	box.OnMousePressed = function() end
	local px = addrW > 0 and addrW + UI.S(20) or 0
	local selected
	box.Paint = function(s, w, h)
		paintPaper(px, 0, W0, H0, UI.S(150), UI.S(26))
		draw.SimpleText(opts.envelope and "ПИСЬМО" or "ЗАПИСКА", NYRP.Font("title", 26), px + UI.S(70), UI.S(26), INK)
		draw.SimpleText(os.date("%d.%m.%Y"), NYRP.Font("medium", 14), px + W0 - UI.S(26), UI.S(34), INK_DIM, TEXT_ALIGN_RIGHT)
		if opts.pages then
			draw.SimpleText("листов в блокноте: " .. opts.pages, NYRP.Font("regular", 12), px + W0 - UI.S(26), UI.S(54), INK_DIM, TEXT_ALIGN_RIGHT)
		end
		if opts.envelope then
			draw.SimpleText("Кому: " .. (selected and selected.name or "выберите адрес слева"), NYRP.Font("semibold", 15), px + UI.S(70), UI.S(70),
				selected and INK or Color(170, 70, 60))
		end
		draw.SimpleText(ulen(s.Body and s.Body:GetText() or "") .. " / " .. W.MaxText, NYRP.Font("medium", 12), px + W0 - UI.S(26), H0 - UI.S(70), INK_DIM, TEXT_ALIGN_RIGHT)
		if addrW > 0 then
			UI.RoundedRect(UI.S(12), 0, 0, addrW, H0, Color(12, 14, 22, 240))
			UI.Outline(UI.S(12), 0, 0, addrW, H0, Color(255, 255, 255, 18), 1)
			draw.SimpleText("АДРЕС", NYRP.Font("title", 20), UI.S(18), UI.S(18), UI.Col.text)
			draw.SimpleText(s.Near and "вы у почтовых ящиков" or "подойдите к почтовым ящикам", NYRP.Font("regular", 12), UI.S(18), UI.S(48),
				s.Near and UI.Col.green or UI.Col.orange)
		end
	end

	local title
	if not opts.envelope then
		title = inkEntry(box, NYRP.Font("bold", 19), false, "Заголовок (необязательно)")
		title:SetPos(px + UI.S(70), UI.S(78))
		title:SetSize(W0 - UI.S(100), UI.S(36))
		title.OnChange = function(s)
			if ulen(s:GetText()) > W.MaxTitle then s:SetText(string.sub(s:GetText(), 1, utf8.offset(s:GetText(), W.MaxTitle + 1) - 1)) s:SetCaretPos(#s:GetText()) end
		end
	end
	local body = inkEntry(box, NYRP.Font("medium", 17), true, "Пишите здесь...")
	body:SetPos(px + UI.S(64), UI.S(126))
	body:SetSize(W0 - UI.S(90), H0 - UI.S(126) - UI.S(120))
	body:SetVerticalScrollbarEnabled(true)
	body.OnChange = function(s)
		if ulen(s:GetText()) > W.MaxText then
			s:SetText(string.sub(s:GetText(), 1, utf8.offset(s:GetText(), W.MaxText + 1) - 1))
			s:SetCaretPos(#s:GetText())
		end
	end
	box.Body = body
	local sign = signRow(box, px + UI.S(64), H0 - UI.S(108), W0 - UI.S(90))
	timer.Simple(0.05, function() if IsValid(body) then body:RequestFocus() end end)

	-- кнопки под листом
	local function btn(text, icon, style, x, fn)
		local b = vgui.Create("NYRP.Button", box)
		b:SetSize(UI.S(200), UI.S(46))
		b:SetPos(x, H0 + UI.S(16))
		b:SetLabel(text)
		b:SetIcon(icon)
		b:SetStyle(style)
		b:SetAlign(TEXT_ALIGN_CENTER)
		b.DoClick = fn
		return b
	end
	btn(opts.envelope and "Отправить" or "Написать", opts.envelope and "mailbox" or "check", "solid", px + W0 - UI.S(200), function()
		local text = string.Trim(body:GetText())
		if text == "" then NYRP.Notify("Сначала напишите текст", "warning") return end
		if opts.envelope then
			if not selected then NYRP.Notify("Выберите адрес", "warning") return end
			net.Start("nyrp.writing.send")
			net.WriteUInt(opts.envelope, 8)
			net.WriteString(selected.id)
			net.WriteString(text)
			net.WriteUInt(sign.Mode, 2)
			net.WriteString(sign.Custom:GetText())
			net.SendToServer()
		else
			net.Start("nyrp.writing.write")
			net.WriteUInt(opts.notebook, 8)
			net.WriteString(title and title:GetText() or "")
			net.WriteString(text)
			net.WriteUInt(sign.Mode, 2)
			net.WriteString(sign.Custom:GetText())
			net.SendToServer()
		end
		bg:Close()
	end)
	btn("Отмена", "close", "ghost", px + W0 - UI.S(410), function() bg:Close() end)

	-- адреса (конверт)
	if opts.envelope then
		local search = vgui.Create("NYRP.TextEntry", box)
		search:SetPos(UI.S(14), UI.S(74))
		search:SetSize(addrW - UI.S(28), UI.S(38))
		search:SetPlaceholderText("Поиск адреса...")
		search:SetUpdateOnType(true)
		local list = vgui.Create("NYRP.Scroll", box)
		list:SetPos(UI.S(10), UI.S(122))
		list:SetSize(addrW - UI.S(20), H0 - UI.S(132))
		local function fill()
			list:Clear()
			local q = NYRP.Help and NYRP.Help.Lower and NYRP.Help.Lower(search:GetValue() or "") or string.lower(search:GetValue() or "")
			local n = 0
			for _, a in ipairs(W.Addresses or {}) do
				local low = NYRP.Help and NYRP.Help.Lower and NYRP.Help.Lower(a.name) or string.lower(a.name)
				if q == "" or string.find(low, q, 1, true) then
					n = n + 1
					local b = list:Add("DButton")
					b:Dock(TOP)
					b:SetTall(UI.S(40))
					b:DockMargin(0, 0, UI.S(4), UI.S(4))
					b:SetText("")
					b.Paint = function(s, bw, bh)
						local on = selected == a
						UI.RoundedRect(UI.S(8), 0, 0, bw, bh, on and UI.Alpha(UI.Col.accent, 50) or Color(255, 255, 255, s:IsHovered() and 16 or 6))
						UI.DrawIcon(a.biz and "store" or "home", UI.S(20), bh / 2, UI.S(16), on and UI.Col.accent or UI.Col.dim)
						draw.SimpleText(a.name, NYRP.Font("semibold", 14), UI.S(38), bh / 2, UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
						return true
					end
					b.DoClick = function() UI.Sound("click") selected = a end
				end
			end
			if n == 0 then
				local e = list:Add("DPanel")
				e:Dock(TOP)
				e:SetTall(UI.S(80))
				e.Paint = function(_, ew, eh)
					local lines = UI.Wrap(W.Addresses and "Ничего не найдено" or "Загрузка адресов...", NYRP.Font("regular", 13), ew - UI.S(10))
					for i, l in ipairs(lines) do draw.SimpleText(l, NYRP.Font("regular", 13), UI.S(6), UI.S(10) + (i - 1) * UI.S(18), UI.Col.dim) end
				end
			end
		end
		search.OnValueChange = fill
		W.AddrList = { fill = fill, box = box }
		W.Addresses = nil
		fill()
		net.Start("nyrp.writing.addr")
		net.SendToServer()
	end
	return bg
end

net.Receive("nyrp.writing.addr", function()
	W.Addresses = net.ReadTable()
	local near = net.ReadBool()
	local al = W.AddrList
	if al and IsValid(al.box) then
		al.box.Near = near
		al.fill()
	end
end)

-- ---------------------------------------------------------- чтение --
function W.Read(it)
	local d = it.data or {}
	local bg = backdrop()
	local isLetter = it.id == "letter"
	local W0 = UI.S(600)
	local font = NYRP.Font("medium", 17)
	local lines = {}
	for para in string.gmatch((d.text or "") .. "\n", "(.-)\n") do
		local wl = UI.Wrap(para, font, W0 - UI.S(100))
		if #wl == 0 then lines[#lines + 1] = "" end
		for _, l in ipairs(wl) do lines[#lines + 1] = l end
	end
	local lineH = UI.S(26)
	local top = UI.S(isLetter and 130 or ((d.title and d.title ~= "") and 110 or 80))
	local H0 = math.Clamp(top + #lines * lineH + UI.S(110), UI.S(320), ScrH() - UI.S(120))
	local card = vgui.Create("DPanel", bg)
	card:SetSize(W0, H0)
	card:Center()
	card.Born = RealTime()
	card.OnMousePressed = function() bg:Close() end
	-- длинный текст — прокрутка колесом
	card.Scroll = 0
	local maxScroll = math.max(0, top + #lines * lineH + UI.S(110) - H0)
	card.OnMouseWheeled = function(s, dlt) s.Scroll = math.Clamp(s.Scroll - dlt * lineH * 2, 0, maxScroll) end
	card.Paint = function(s, w, h)
		local t = UI.Ease((RealTime() - s.Born) / 0.35)
		local oy = (1 - t) * UI.S(30)
		paintPaper(0, oy, w, h, top - UI.S(4) - s.Scroll % lineH, lineH)
		local sx, sy = s:LocalToScreen(0, 0)
		render.SetScissorRect(sx, sy + UI.S(14), sx + w, sy + h - UI.S(14), true)
		local y = UI.S(26) + oy - s.Scroll
		if isLetter then
			draw.SimpleText("ПИСЬМО", NYRP.Font("title", 24), UI.S(70), y, INK)
			draw.SimpleText("Кому: " .. (d.to or "?"), NYRP.Font("semibold", 14), UI.S(70), y + UI.S(38), INK_DIM)
			draw.SimpleText("От: " .. ((d.author and d.author ~= "") and d.author or "без подписи"), NYRP.Font("semibold", 14), UI.S(70), y + UI.S(60), INK_DIM)
		elseif d.title and d.title ~= "" then
			draw.SimpleText(d.title, NYRP.Font("bold", 22), UI.S(70), y, INK)
		end
		draw.SimpleText(d.date or "", NYRP.Font("medium", 13), w - UI.S(26), UI.S(30) + oy - s.Scroll, INK_DIM, TEXT_ALIGN_RIGHT)
		for i, l in ipairs(lines) do
			draw.SimpleText(l, font, UI.S(66), oy + top + (i - 1) * lineH - lineH + UI.S(4) - s.Scroll, INK)
		end
		local sy = oy + top + #lines * lineH + UI.S(14) - s.Scroll
		if d.author and d.author ~= "" then
			draw.SimpleText("— " .. d.author, NYRP.Font("semibold", 18), w - UI.S(40), sy, INK, TEXT_ALIGN_RIGHT)
		end
		render.SetScissorRect(0, 0, 0, 0, false)
	end
	local hint = vgui.Create("DPanel", bg)
	hint:SetSize(W0, UI.S(30))
	hint:SetPos(ScrW() / 2 - W0 / 2, ScrH() / 2 + H0 / 2 + UI.S(12))
	hint.Paint = function(_, w, h)
		draw.SimpleText(maxScroll > 0 and "Колесо мыши — прокрутка · клик — закрыть" or "Нажмите в любом месте, чтобы закрыть",
			NYRP.Font("regular", 13), w / 2, h / 2, Color(255, 255, 255, 110), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	return bg
end

-- ------------------------------------------------ меню предмета --
hook.Add("NYRP.ItemView", "nyrp.writing", function(kind, key, it)
	if kind ~= "inv" then
		if it.id == "note" or it.id == "letter" then W.Read(it) return true end
		return
	end
	local slot = tonumber(key)
	if it.id == "note" or it.id == "letter" then
		W.Read(it)
		return true
	elseif it.id == "notebook" then
		openWrite({ notebook = slot, pages = tonumber(it.data and it.data.pages) or W.Pages })
		if NYRP.Inventory and NYRP.Inventory.Close then NYRP.Inventory.Close() end
		return true
	elseif it.id == "envelope" then
		openWrite({ envelope = slot })
		if NYRP.Inventory and NYRP.Inventory.Close then NYRP.Inventory.Close() end
		return true
	end
end)

local GIVE = { note = true, letter = true, notebook = true, envelope = true }
hook.Add("NYRP.ItemContext", "nyrp.writing", function(kind, key, it, opts)
	if kind ~= "inv" or not GIVE[it.id] then return end
	opts[#opts + 1] = { text = "Передать человеку", icon = "g_give", func = function()
		net.Start("nyrp.writing.give")
		net.WriteUInt(tonumber(key), 8)
		net.SendToServer()
	end }
end)

-- ----------------------------------------- письма в почтовом ящике --
-- Окно ящика строит modules/doors/cl_mailbox.lua; после него спрашиваем письма и добавляем кнопку.
local function wrapMailbox()
	local cur = net.Receivers and net.Receivers["nyrp.mailbox"]
	if not cur or cur == W.MailWrapper then return end
	local orig = cur
	W.MailWrapper = function(len, ply)
		orig(len, ply)
		net.Start("nyrp.writing.box")
		net.SendToServer()
	end
	net.Receivers["nyrp.mailbox"] = W.MailWrapper
end
wrapMailbox()
hook.Add("InitPostEntity", "nyrp.writing", function(...) wrapMailbox(...) end)

function W.OpenLetters(list)
	local win, body = UI.Window("Письма", "mailbox", 460, 480, { sub = #list > 0 and (#list .. " в ящике") or "ящик пуст" })
	W.LettersWin = win
	local scroll = vgui.Create("NYRP.Scroll", body)
	scroll:Dock(FILL)
	if #list == 0 then
		local e = scroll:Add("DPanel")
		e:Dock(TOP)
		e:SetTall(UI.S(120))
		e.Paint = function(_, w, h)
			UI.DrawIcon("mailbox", w / 2, h / 2 - UI.S(16), UI.S(36), UI.Col.faint)
			draw.SimpleText("Писем нет", NYRP.Font("semibold", 16), w / 2, h / 2 + UI.S(22), UI.Col.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end
	for _, l in ipairs(list) do
		local row = scroll:Add("DPanel")
		row:Dock(TOP)
		row:SetTall(UI.S(64))
		row:DockMargin(0, 0, UI.S(4), UI.S(6))
		row.Paint = function(_, w, h)
			UI.RoundedRect(UI.S(10), 0, 0, w, h, Color(255, 255, 255, 8))
			UI.DrawIcon("mailbox", UI.S(26), h / 2, UI.S(22), UI.Col.accent)
			draw.SimpleText("От: " .. l.from, NYRP.Font("semibold", 15), UI.S(50), UI.S(12), UI.Col.text)
			draw.SimpleText(l.to .. " · " .. l.date, NYRP.Font("regular", 12), UI.S(50), UI.S(36), UI.Col.dim)
		end
		local b = UI.AddButton(row, "Забрать", "arrow_left", function()
			net.Start("nyrp.writing.take")
			net.WriteUInt(l.id, 32)
			net.SendToServer()
			win:Close()
		end, { dock = RIGHT, style = "solid", h = 40 })
		b:SetWide(UI.S(120))
		b:DockMargin(0, UI.S(12), UI.S(12), UI.S(12))
	end
end

net.Receive("nyrp.writing.box", function()
	local list = net.ReadTable()
	W.Box = list
	if IsValid(W.LettersWin) and not W.LettersWin.Closing then
		W.LettersWin:Remove()
		if #list > 0 then W.OpenLetters(list) end
		return
	end
	local win = NYRP.MailWin
	if not IsValid(win) or win.nyrpLettersBtn then return end
	-- тело окна — последний дочерний элемент карточки (UI.Window)
	local box = win:GetChildren()[1]
	local kids = IsValid(box) and box:GetChildren() or {}
	local body = kids[#kids]   -- UI.Window создаёт тело последним
	if not IsValid(body) then return end
	win.nyrpLettersBtn = true
	UI.AddButton(body, #list > 0 and ("Письма: " .. #list) or "Писем нет", "message", function()
		win:Close()
		W.OpenLetters(W.Box or {})
	end, { dock = BOTTOM, style = #list > 0 and "solid" or "ghost", accent = #list > 0 and UI.Col.orange or nil, h = 40 })
end)
