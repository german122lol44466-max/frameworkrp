--[[
	Достижения на клиенте: всплывающая карточка при получении и экран «Достижения» в главном меню
	(карточки с прогрессом и наградой, выбор звания).
]]

local A = WS.Ach
local UI = WS.UI
local E = WS.Ease

A.Got, A.Prog = A.Got or {}, A.Prog or {}
local toasts = {}

net.Receive("ws.ach.state", function()
	for i = 1, net.ReadUInt(8) do
		local a = A.List[i]
		local got, prog = net.ReadBool(), net.ReadUInt(16)
		if a then A.Got[a.id], A.Prog[a.id] = got, prog end
	end
end)

net.Receive("ws.ach.unlock", function()
	local id = net.ReadString()
	A.Got[id] = true
	toasts[#toasts + 1] = { id = id, t = RealTime() }
	WS.Audio.Play("whitesilence/menu/join.ogg", { volume = 0.7 })
	WS.Audio.Play("whitesilence/intro/banner_hit.ogg", { volume = 0.35 })
end)

function A.Count()
	local n = 0
	for _, a in ipairs(A.List) do if A.Got[a.id] then n = n + 1 end end
	return n
end

local function icon(n) return UI.Mat("whitesilence/icons/" .. n .. ".png", "smooth") end

-- ---------------------------------------------------------------- карточка «получено»

local function drawToasts()
	if #toasts == 0 then return end
	WS.Intro.FX.Ensure()
	local w, h = ScrW(), ScrH()
	local s = h / 1080
	local y = 120 * s
	for i = #toasts, 1, -1 do
		local t = toasts[i]
		local age = RealTime() - t.t
		local a = A.ById[t.id]
		if age > 6 or not a then table.remove(toasts, i)
		else
			local k = E.Window(age, 0, 0.45, 5.2, 6)
			local slide = (1 - E.OutCubic(age / 0.45)) * 40 * s
			local cw, ch = 460 * s, 92 * s
			local x = w / 2 - cw / 2
			draw.RoundedBox(6, x, y - slide, cw, ch, Color(8, 10, 14, 235 * k))
			surface.SetDrawColor(226, 190, 120, 200 * k)
			surface.DrawRect(x, y - slide, cw, 3 * s)
			WS.Intro.FX.Glow(x + 46 * s, y - slide + ch / 2, 60 * s, Color(226, 190, 120), 0.18 * k)
			surface.SetMaterial(icon(a.icon))
			surface.SetDrawColor(226, 190, 120, 255 * k)
			surface.DrawTexturedRect(x + 22 * s, y - slide + 22 * s, 48 * s, 48 * s)
			draw.SimpleText("ДОСТИЖЕНИЕ", WS.Font("menusemi", 13), x + 90 * s, y - slide + 14 * s, Color(226, 190, 120, 255 * k))
			draw.SimpleText(a.name, WS.Font("menubold", 24), x + 90 * s, y - slide + 30 * s, Color(238, 240, 244, 255 * k))
			draw.SimpleText(A.RewardText(a), WS.Font("menulight", 14), x + 90 * s, y - slide + 62 * s, Color(180, 188, 200, 230 * k))
			y = y + ch + 10 * s
		end
	end
end

hook.Add("HUDPaint", "ws.ach", drawToasts)
hook.Add("PostRenderVGUI", "ws.ach", function()
	-- поверх меню тоже
	if WS.Menu and WS.Menu.IsOpen() and #toasts > 0 then drawToasts() end
end)

-- ---------------------------------------------------------------- экран достижений (в меню)

function A.OpenPanel(parent)
	net.Start("ws.ach.request") net.SendToServer()
	local s = ScrH() / 1080
	if IsValid(A.Panel) then A.Panel:Remove() end
	local p = vgui.Create("DPanel", parent)
	A.Panel = p
	p:SetSize(ScrW(), ScrH())
	p:SetPos(0, 0)
	local born = RealTime()
	p.Paint = function(self, w, h)
		local a = E.Smooth((RealTime() - born) / 0.3)
		surface.SetDrawColor(4, 6, 9, 225 * a)
		surface.DrawRect(0, 0, w, h)
		draw.SimpleText("ДОСТИЖЕНИЯ", WS.Font("menubold", 44), 120 * s, 80 * s, Color(238, 240, 244, 255 * a))
		draw.SimpleText(string.format("Получено %d из %d · награды действуют в каждой операции", A.Count(), #A.List),
			WS.Font("menulight", 18), 122 * s, 134 * s, Color(180, 188, 200, 230 * a))
		surface.SetDrawColor(196, 38, 38, 220 * a)
		surface.DrawRect(122 * s, 166 * s, 80 * s, 2 * s)
		local title = A.TitleOf(LocalPlayer())
		draw.SimpleText("Звание: " .. (title and ("«" .. title .. "»") or "не выбрано") .. " — нажмите на открытую карточку со званием",
			WS.Font("menusemi", 16), w - 120 * s, 134 * s, Color(226, 190, 120, 230 * a), TEXT_ALIGN_RIGHT)
	end
	local cols = 3
	local cw, ch, gap = 520 * s, 112 * s, 18 * s
	local x0 = (ScrW() - (cw * cols + gap * (cols - 1))) / 2
	local y0 = 200 * s
	for i, a in ipairs(A.List) do
		local c = vgui.Create("DButton", p)
		c:SetText("")
		c:SetSize(cw, ch)
		c:SetPos(x0 + ((i - 1) % cols) * (cw + gap), y0 + math.floor((i - 1) / cols) * (ch + gap))
		local delay = born + i * 0.03
		c.Paint = function(self, w, h)
			local k = E.Smooth((RealTime() - delay) / 0.3)
			local got = A.Got[a.id]
			local hov = self:IsHovered()
			local isTitle = a.reward and a.reward.title and A.TitleOf(LocalPlayer()) == a.reward.title
			draw.RoundedBox(5, 0, 0, w, h, Color(10, 12, 16, (got and 225 or 170) * k))
			surface.SetDrawColor(got and 226 or 255, got and 190 or 255, got and 120 or 255, (isTitle and 200 or (hov and 60 or 20)) * k)
			surface.DrawOutlinedRect(0, 0, w, h, isTitle and 2 or 1)
			surface.SetMaterial(icon(a.icon))
			local ic = got and Color(226, 190, 120) or Color(110, 116, 126)
			surface.SetDrawColor(ic.r, ic.g, ic.b, 255 * k)
			surface.DrawTexturedRect(18 * s, h / 2 - 26 * s, 52 * s, 52 * s)
			draw.SimpleText(a.name, WS.Font("menubold", 21), 88 * s, 14 * s, got and Color(238, 240, 244, 255 * k) or Color(160, 166, 176, 255 * k))
			draw.SimpleText(a.desc, WS.Font("menulight", 15), 88 * s, 42 * s, Color(176, 184, 196, 230 * k))
			draw.SimpleText(A.RewardText(a), WS.Font("menusemi", 13), 88 * s, h - 22 * s,
				got and Color(150, 210, 160, 230 * k) or Color(140, 146, 156, 200 * k))
			if a.goal and not got then
				local pr = math.Clamp((A.Prog[a.id] or 0) / a.goal, 0, 1)
				surface.SetDrawColor(255, 255, 255, 25 * k)
				surface.DrawRect(88 * s, 66 * s, w - 110 * s, 4 * s)
				surface.SetDrawColor(226, 190, 120, 220 * k)
				surface.DrawRect(88 * s, 66 * s, (w - 110 * s) * pr, 4 * s)
				draw.SimpleText((A.Prog[a.id] or 0) .. " / " .. a.goal, WS.Font("menulight", 13), w - 20 * s, 72 * s,
					Color(170, 178, 190, 220 * k), TEXT_ALIGN_RIGHT)
			end
			if got then draw.SimpleText("ПОЛУЧЕНО", WS.Font("menusemi", 12), w - 16 * s, 14 * s, Color(150, 210, 160, 255 * k), TEXT_ALIGN_RIGHT) end
			return true
		end
		c.DoClick = function()
			if not (A.Got[a.id] and a.reward and a.reward.title) then return end
			local cur = A.TitleOf(LocalPlayer())
			net.Start("ws.ach.title")
			net.WriteString(cur == a.reward.title and "" or a.reward.title)
			net.SendToServer()
			surface.PlaySound("ui/buttonclick.wav")
		end
	end
	local back = WS.Menu.Button(p, "НАЗАД", 26, function() p:Remove() end)
	back:SetSize(260 * s, 46 * s)
	back:SetPos(ScrW() / 2 - 130 * s, ScrH() - 110 * s)
	return p
end
