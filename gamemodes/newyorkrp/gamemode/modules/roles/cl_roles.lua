--[[
	Меню городских служб (у NPC-вербовщика): карточки фракций — описание, зарплата, требования,
	сколько людей на службе, «Вступить» / «Подать заявку» / «Уйти со службы».
]]

local UI = NYRP.UI
local Roles = NYRP.Roles
local GOLD = Color(247, 198, 0)

local function statusIcon(name, x, y, s, col)
	surface.SetMaterial(UI.Mat("nyrp/status/" .. name .. ".png"))
	surface.SetDrawColor(col or color_white)
	surface.DrawTexturedRect(x - s / 2, y - s / 2, s, s)
end
Roles.DrawIcon = statusIcon

net.Receive("nyrp.fac", function()
	local list, played = net.ReadTable(), net.ReadFloat()
	if IsValid(Roles.Win) then Roles.Win:Remove() end
	local win, body = UI.Window("Городские службы", "shield", 980, 640, { sub = string.format("вы отыграли %.1f ч", played / 3600) })
	Roles.Win = win
	local mine = LocalPlayer():GetNW2String("nyrp.role", Roles.Default or "")
	local scroll = vgui.Create("DScrollPanel", body)
	scroll:Dock(FILL)
	local grid = vgui.Create("DIconLayout", scroll)
	grid:Dock(TOP)
	grid:SetSpaceX(UI.S(14))
	grid:SetSpaceY(UI.S(14))
	local cw = (UI.S(980) - UI.S(44) - UI.S(14) - UI.S(16)) / 2
	for i, e in ipairs(list) do
		local r = Roles.List[e.id]
		if r then
			local card = grid:Add("DPanel")
			card:SetSize(cw, UI.S(270))
			card.Born = RealTime() + i * 0.05
			card.Paint = function(s, w, h)
				s:SetAlpha(255 * math.Clamp((RealTime() - s.Born) / 0.25, 0, 1))
				UI.RoundedRect(UI.S(14), 0, 0, w, h, Color(255, 255, 255, 10))
				UI.RoundedRect(UI.S(3), 0, UI.S(16), UI.S(4), UI.S(54), r.Color)
				UI.Glow(UI.S(46), UI.S(44), UI.S(110), UI.S(110), Color(r.Color.r, r.Color.g, r.Color.b, 40))
				statusIcon(r.Icon or "r_citizen", UI.S(46), UI.S(44), UI.S(44), r.Color)
				draw.SimpleText(r.Name, NYRP.Font("title", 24), UI.S(84), UI.S(22), color_white)
				draw.SimpleText((e.members or 0) .. " на службе" .. ((r.MaxMembers or 0) > 0 and (" из " .. r.MaxMembers) or "")
					.. ((r.Salary or 0) > 0 and ("  ·  зарплата " .. NYRP.Money.Format(r.Salary) .. " / день") or ""), NYRP.Font("medium", 13), UI.S(84), UI.S(52), UI.Col.dim)
				local y = UI.S(84)
				for k, l in ipairs(UI.Wrap(r.Description or "", NYRP.Font("regular", 13), w - UI.S(36))) do
					if k > 3 then break end
					draw.SimpleText(l, NYRP.Font("regular", 13), UI.S(18), y, Color(210, 212, 220))
					y = y + UI.S(18)
				end
				y = y + UI.S(8)
				if not r.Default then
					draw.SimpleText("ТРЕБОВАНИЯ", NYRP.Font("bold", 11), UI.S(18), y, Color(200, 190, 255))
					y = y + UI.S(18)
					local reqs = {}
					if e.free then reqs[#reqs + 1] = "Свободный набор" end
					if e.whitelist then reqs[#reqs + 1] = "Одобрение администрации (заявка)" end
					if not e.free and (e.hours or 0) > 0 then reqs[#reqs + 1] = "Отыграно " .. e.hours .. " ч" end
					for sk, lv in pairs(not e.free and e.skills or {}) do
						for _, s2 in ipairs(NYRP.Config.Skills) do if s2.id == sk then reqs[#reqs + 1] = s2.name .. " " .. lv end end
					end
					if #reqs == 0 then reqs[1] = "Нет" end
					local bad = {}
					for _, p in ipairs(e.problems or {}) do bad[#bad + 1] = p end
					draw.SimpleText(table.concat(reqs, "  ·  "), NYRP.Font("medium", 13), UI.S(18), y, UI.Col.text)
					y = y + UI.S(20)
					if #bad > 0 and mine ~= e.id then
						draw.SimpleText("Не хватает: " .. bad[1] .. (#bad > 1 and (" и ещё " .. (#bad - 1)) or ""), NYRP.Font("medium", 12), UI.S(18), y, Color(230, 120, 100))
					end
				end
			end
			local btn
			local function act(a)
				net.Start("nyrp.fac.act") net.WriteString(a) net.WriteString(e.id) net.SendToServer()
			end
			if mine == e.id and not r.Default then
				btn = UI.AddButton(card, "Уйти со службы", "logout", function() act("leave") end, { dock = false, accent = UI.Col.red })
			elseif mine == e.id then
				btn = UI.AddButton(card, "Вы — " .. r.Name, "check", function() end, { dock = false })
			elseif r.Default then
				btn = UI.AddButton(card, "Вернуться к гражданской жизни", "user", function() act("leave") end, { dock = false })
			elseif e.applied then
				btn = UI.AddButton(card, "Заявка на рассмотрении", "hourglass", function() end, { dock = false })
			else
				local ok = #(e.problems or {}) == 0
				btn = UI.AddButton(card, e.whitelist and "Подать заявку" or "Вступить", e.whitelist and "sign" or "badge", function()
					if not ok then UI.Sound("error") return end
					act("join")
				end, { dock = false, style = ok and "solid" or "ghost", accent = ok and r.Color or nil })
			end
			btn:SetSize(cw - UI.S(36), UI.S(40))
			btn:SetPos(UI.S(18), UI.S(270) - UI.S(54))
		end
	end
end)

-- значок фракции слева от ника (для табличек над головой)
function Roles.TagIcon(ply)
	local r = Roles.Of(ply)
	if not r or r.Default or r.ShowIcon == false then return end
	return r.Icon, r.Color
end
