--[[
	Шляпа для чаевых (клиент): окно «Дать чаевые» — сумма и быстрые кнопки.
]]

NYRP.StreetFun = NYRP.StreetFun or {}
local SF = NYRP.StreetFun
local UI = NYRP.UI

net.Receive("nyrp.tip.open", function()
	local e = net.ReadEntity()
	if not IsValid(e) then return end
	if IsValid(SF.TipWin) then SF.TipWin:Close() end
	local win, body = UI.Window("Дать чаевые", "music", 400, 300, { keyboard = true, sub = "У вас: " .. NYRP.Money.Format(NYRP.Money.Get(LocalPlayer())) })
	SF.TipWin = win
	local entry = vgui.Create("NYRP.TextEntry", body)
	entry:Dock(TOP)
	entry:SetTall(UI.S(44))
	entry:DockMargin(0, 0, 0, UI.S(10))
	if entry.SetNumeric then entry:SetNumeric(true) end
	if entry.SetPlaceholderText then entry:SetPlaceholderText("Сумма, $") end
	entry:RequestFocus()
	local row = vgui.Create("EditablePanel", body)
	row:Dock(TOP)
	row:SetTall(UI.S(36))
	row:DockMargin(0, 0, 0, UI.S(12))
	for _, v in ipairs({ 1, 5, 10, 20, 50 }) do
		local b = UI.AddButton(row, "$" .. v, nil, function() entry:SetText(tostring(v)) UI.Sound("click") end, { dock = LEFT, h = 36 })
		b:SetWide(UI.S(64))
		b:DockMargin(0, 0, UI.S(8), 0)
	end
	local function give()
		local n = math.floor(tonumber(entry:GetText()) or 0)
		if n < 1 or n > 1000 then UI.Sound("error") NYRP.Notify("От $1 до $1000", "warning", 2) return end
		net.Start("nyrp.tip.give")
		net.WriteEntity(e)
		net.WriteUInt(n, 16)
		net.SendToServer()
		win:Close()
	end
	entry.OnEnter = give
	UI.AddButton(body, "Положить в шляпу", "cash", give, { style = "solid", h = 44 })
	local baseThink = win.Think
	win.Think = function(s)
		if baseThink then baseThink(s) end
		if not s.Closing and (not IsValid(e) or e:GetPos():Distance(LocalPlayer():GetPos()) > 170) then s:Close() end
	end
end)
