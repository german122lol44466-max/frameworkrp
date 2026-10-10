--[[
	Окно ежедневного бонуса: календарь серии из 7 дней, сегодняшняя награда подсвечена, кнопка «Забрать».
]]

NYRP.Daily = NYRP.Daily or {}
local D = NYRP.Daily
local UI = NYRP.UI

local GOLD = Color(247, 198, 0)

net.Receive("nyrp.daily", function()
	D.Day = net.ReadUInt(4)
	D.Avail = net.ReadBool()
	D.Broken = net.ReadBool()
	local open = net.ReadBool()
	if D.Avail == false and IsValid(D.Win) then D.ClaimedT = RealTime() end
	if open and not IsValid(D.Win) then D.Open() end
end)

function D.Open()
	local win, body = UI.Window("Ежедневный бонус", "p_calendar", 820, 420, { sub = "Заходите каждый день — награда растёт" })
	D.Win = win
	D.ClaimedT = nil
	local n = #D.Rewards
	local gap = UI.S(10)
	local tw = (body:GetWide() - gap * (n - 1)) / n
	local th = UI.S(190)
	local grid = vgui.Create("DPanel", body)
	grid:SetPos(0, UI.S(40))
	grid:SetSize(body:GetWide(), th + UI.S(10))
	local head = vgui.Create("DPanel", body)
	head:SetPos(0, 0)
	head:SetSize(body:GetWide(), UI.S(36))
	head.Paint = function(_, w, h)
		local text
		if D.Avail then
			text = D.Broken and "Серия прервалась — начинаем заново с первого дня." or ("Сегодня — день " .. D.Day .. " из " .. n .. ". Не пропускайте: пропуск сбрасывает серию.")
		else
			text = "Награда за сегодня уже получена. Следующая — завтра (день " .. math.min((D.Day or 0) + 1, n) .. ((D.Day or 0) >= n and " → новая серия" or "") .. ")."
		end
		draw.SimpleText(text, NYRP.Font("medium", 15), 0, h / 2, D.Broken and D.Avail and UI.Col.orange or UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	grid.Paint = function(_, w, h)
		local cur = D.Day or 1
		for i = 1, n do
			local x = (i - 1) * (tw + gap)
			local claimed = i < cur or (i == cur and not D.Avail)
			local today = i == cur and D.Avail
			local big = i == n
			local bg = today and Color(60, 48, 10, 240) or (claimed and Color(20, 40, 28, 230) or Color(255, 255, 255, 10))
			UI.RoundedRect(UI.S(12), x, 0, tw, th, bg)
			if today then
				local p = (math.sin(RealTime() * 4) + 1) / 2
				UI.Glow(x + tw / 2, th / 2, tw * 1.6, th * 1.2, Color(247, 198, 0, 30 + 30 * p))
				UI.Outline(UI.S(12), x, 0, tw, th, UI.Alpha(GOLD, 150 + 100 * p), UI.S(2))
			elseif big then
				UI.Outline(UI.S(12), x, 0, tw, th, UI.Alpha(GOLD, 70), 1)
			end
			draw.SimpleText("ДЕНЬ " .. i, NYRP.Font("bold", 13), x + tw / 2, UI.S(22), today and GOLD or UI.Col.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			local icon = claimed and "check" or (big and "coins" or "cash")
			local ic = claimed and UI.Col.green or (today and GOLD or (big and GOLD or Color(170, 170, 190)))
			-- только что получено — «печать» с отскоком
			local s = 1
			if i == cur and claimed and D.ClaimedT then s = 1 + 0.4 * math.max(0, 1 - (RealTime() - D.ClaimedT) / 0.4) end
			UI.DrawIcon(icon, x + tw / 2, th / 2 - UI.S(6), UI.S(big and 46 or 38) * s, ic)
			draw.SimpleText(NYRP.Money.Format(D.Rewards[i]), NYRP.Font("title", big and 24 or 20), x + tw / 2, th - UI.S(44), claimed and UI.Col.dim or color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			draw.SimpleText(claimed and "получено" or (today and "сегодня" or (big and "главный приз" or "")), NYRP.Font("regular", 12), x + tw / 2, th - UI.S(20), claimed and UI.Col.green or UI.Col.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end
	local btn = UI.AddButton(body, "", "cash", function()
		if not D.Avail then win:Close() return end
		net.Start("nyrp.daily.claim")
		net.SendToServer()
	end, { dock = false, style = "solid", h = 50 })
	btn:SetPos(body:GetWide() / 2 - UI.S(170), body:GetTall() - UI.S(60))
	btn:SetWide(UI.S(340))
	btn:SetAlign(TEXT_ALIGN_CENTER)
	btn.Think = function(s)
		s:SetLabel(D.Avail and ("Забрать " .. NYRP.Money.Format(D.Rewards[D.Day] or 0)) or "Отлично, до завтра!")
		s:SetIcon(D.Avail and "cash" or "check")
	end
end

