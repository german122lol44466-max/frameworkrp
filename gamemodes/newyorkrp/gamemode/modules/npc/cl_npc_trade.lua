--[[
	Торговля с NPC (окно с курсором), трекер заданий слева сверху, таблички над NPC, свойства C-меню.
]]

local UI = NYRP.UI
local N = NYRP.NPC
local Items = NYRP.Items

-- ------------------------------------------------------------ торговля --
local function priceText(o)
	local parts = {}
	if o.money and o.money > 0 then parts[#parts + 1] = NYRP.Money.Format(o.money) end
	if o.costItem then
		local def = Items.Get(o.costItem)
		parts[#parts + 1] = (def and def.name or o.costItem) .. " ×" .. (o.costN or 1)
	end
	return #parts > 0 and table.concat(parts, " + ") or "бесплатно"
end

function N.OpenTrade(ent, offers)
	if IsValid(N.TradePanel) then N.TradePanel:Remove() end
	local f = vgui.Create("EditablePanel")
	N.TradePanel = f
	local rowH = UI.S(74)
	local w = UI.S(560)
	local h = math.min(UI.S(150) + #offers * (rowH + UI.S(8)), ScrH() * 0.8)
	f:SetSize(w, h)
	f:Center()
	f:MakePopup()
	f.Born = RealTime()
	local name = IsValid(ent) and ent:GetNW2String("nyrp.npcName", "Торговец") or "Торговец"
	f.Paint = function(s, pw, ph)
		s:SetAlpha(255 * UI.Ease((RealTime() - s.Born) / 0.25))
		UI.RoundedBlurPanel(s, UI.S(14), 4)
		UI.RoundedRect(UI.S(14), 0, 0, pw, ph, Color(14, 16, 26, 240))
		UI.Masked(UI.S(14), 0, 0, pw, ph, function()
			surface.SetDrawColor(8, 9, 14, 250)
			surface.DrawRect(0, 0, pw, UI.S(58))
			local cs = UI.S(6)
			for i = 0, math.ceil(pw / cs) do
				for r = 0, 1 do
					if (i + r) % 2 == 0 then surface.SetDrawColor(247, 198, 0) else surface.SetDrawColor(10, 10, 12) end
					surface.DrawRect(i * cs, UI.S(58) - cs * 2 + r * cs, cs, cs)
				end
			end
		end)
		draw.SimpleText(name, NYRP.Font("tag", 24), UI.S(20), UI.S(24), Color(240, 241, 245), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText("ТОРГОВЛЯ", NYRP.Font("title", 15), pw - UI.S(64), UI.S(24), Color(247, 198, 0), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		draw.SimpleText("У вас: " .. NYRP.Money.Format(NYRP.Money.Get(LocalPlayer())), NYRP.Font("semibold", 15), UI.S(20), UI.S(80), Color(247, 198, 0))
		surface.SetDrawColor(247, 198, 0, 230)
		surface.DrawRect(0, ph - UI.S(3), pw, UI.S(3))
		if not IsValid(ent) or ent:GetPos():Distance(LocalPlayer():GetPos()) > 200 then s:Remove() end
	end
	f.OnKeyCodePressed = function(s, key) if key == KEY_ESCAPE or key == KEY_E then s:Remove() end end
	local close = vgui.Create("NYRP.IconButton", f)
	close:SetSize(UI.S(30), UI.S(30))
	close:SetPos(w - UI.S(46), UI.S(14))
	close.DoClick = function() f:Remove() end

	local scroll = vgui.Create("NYRP.Scroll", f)
	scroll:SetPos(UI.S(16), UI.S(110))
	scroll:SetSize(w - UI.S(32), h - UI.S(126))
	for i, o in ipairs(offers) do
		local def = Items.Get(o.item)
		local row = scroll:Add("DPanel")
		row:Dock(TOP)
		row:SetTall(rowH)
		row:DockMargin(0, 0, UI.S(6), UI.S(8))
		row.Paint = function(s, pw, ph)
			UI.RoundedRect(UI.S(10), 0, 0, pw, ph, s:IsChildHovered() and Color(255, 255, 255, 14) or Color(0, 0, 0, 80))
			UI.RoundedRect(UI.S(8), UI.S(8), UI.S(8), ph - UI.S(16), ph - UI.S(16), Color(0, 0, 0, 90))
			NYRP.DrawItemIcon(o.item, UI.S(10), UI.S(10), ph - UI.S(20), ph - UI.S(20))
			draw.SimpleText((def and def.name or o.item) .. (o.n > 1 and (" ×" .. o.n) or ""), NYRP.Font("semibold", 17), ph + UI.S(6), UI.S(24), UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText(priceText(o), NYRP.Font("bold", 15), ph + UI.S(6), UI.S(50), Color(247, 198, 0), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		local buy = vgui.Create("NYRP.Button", row)
		buy:Dock(RIGHT)
		buy:DockMargin(0, UI.S(18), UI.S(14), UI.S(18))
		buy:SetWide(UI.S(120))
		buy:SetLabel("КУПИТЬ")
		buy:SetStyle("solid")
		buy:SetAccent(Color(247, 198, 0))
		buy:SetAlign(TEXT_ALIGN_CENTER)
		buy:SetFontStyle("title", 16)
		buy.DoClick = function()
			UI.Sound("click")
			net.Start("nyrp.npc.buy")
			net.WriteEntity(ent)
			net.WriteUInt(i, 8)
			net.SendToServer()
		end
	end
end

net.Receive("nyrp.npc.trade", function()
	local ent, offers = net.ReadEntity(), net.ReadTable()
	N.OpenTrade(ent, offers)
end)

-- ------------------------------------------------------ трекер заданий --
N.Quests = N.Quests or {}
net.Receive("nyrp.quest.sync", function() N.Quests = net.ReadTable() end)

hook.Add("HUDPaint", "nyrp.quests", function()
	if NYRP.HUDHidden() or #N.Quests == 0 then return end
	local x, y = UI.S(24), UI.S(24)
	local mat = UI.Mat("nyrp/status/quest.png")
	surface.SetMaterial(mat)
	surface.SetDrawColor(247, 198, 0)
	surface.DrawTexturedRect(x, y, UI.S(18), UI.S(18))
	draw.SimpleText("ЗАДАНИЯ", NYRP.Font("title", 15), x + UI.S(26), y + UI.S(9), Color(230, 232, 238), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	y = y + UI.S(28)
	for _, q in ipairs(N.Quests) do
		local col = q.ready and UI.Col.green or Color(236, 237, 242)
		draw.SimpleText(q.name, NYRP.Font("semibold", 15), x + 1, y + 1, Color(0, 0, 0, 160))
		draw.SimpleText(q.name, NYRP.Font("semibold", 15), x, y, col)
		draw.SimpleText(q.goal .. (q.npc and (" · " .. q.npc) or ""), NYRP.Font("regular", 13), x, y + UI.S(18), UI.Col.dim)
		y = y + UI.S(42)
		-- метка точки «дойти до»
		if q.point then
			local p = Vector(q.point.x, q.point.y, q.point.z)
			local sc = (p + Vector(0, 0, 40)):ToScreen()
			if sc.visible then
				local d = math.Round(LocalPlayer():GetPos():Distance(p) / 52)
				surface.SetMaterial(UI.Mat("nyrp/status/quest_point.png"))
				surface.SetDrawColor(247, 198, 0, 230)
				surface.DrawTexturedRect(sc.x - UI.S(12), sc.y - UI.S(12), UI.S(24), UI.S(24))
				draw.SimpleText(d .. " м", NYRP.Font("bold", 13), sc.x, sc.y + UI.S(20), color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		end
	end
end)

-- ------------------------------------------------------- таблички NPC --
local tagA = {}
hook.Add("PostDrawTranslucentRenderables", "nyrp.npc.tags", function(depth, sky)
	if sky or NYRP.HUDHidden() or not NYRP.Overhead.DrawTag then return end
	local eye = EyePos()
	local look = LocalPlayer():GetEyeTrace().Entity
	for _, ent in ipairs(ents.FindByClass("nyrp_npc")) do
		local dist = eye:Distance(ent:GetPos())
		local want = (look == ent and dist < 400) or dist < 180
		tagA[ent] = UI.Approach(tagA[ent] or 0, want and 1 or 0, want and 10 or 5)
		local a = tagA[ent]
		if a > 0.01 and not (N.InDialog() and dist < 200) then
			local b = ent:LookupBone("ValveBiped.Bip01_Head1")
			local pos = (b and ent:GetBonePosition(b) or ent:GetPos() + Vector(0, 0, 64)) + Vector(0, 0, 14)
			local ang = EyeAngles()
			ang:RotateAroundAxis(ang:Up(), -90)
			ang:RotateAroundAxis(ang:Forward(), 90)
			cam.Start3D2D(pos, ang, 0.055 * math.Clamp(dist / 260, 0.85, 1.6))
			local icon = ent:GetNW2String("nyrp.npcKind") == "trader" and "npc_trader" or "npc_talk"
			NYRP.Overhead.DrawTag(0, UI.Ease(a), ent:GetNW2String("nyrp.npcName", "NPC"), false, icon, ent:GetNW2String("nyrp.npcDesc", ""))
			cam.End3D2D()
		end
	end
end)

-- ---------------------------------------------------- свойства C-меню --
properties.Add("nyrp_npc_edit", {
	MenuLabel = "Настроить NPC", Order = 1, MenuIcon = "icon16/user_edit.png",
	Filter = function(self, ent, ply) return IsValid(ent) and ent:GetClass() == "nyrp_npc" and ply:IsAdmin() end,
	Action = function(self, ent) net.Start("nyrp.npc.edit") net.WriteEntity(ent) net.SendToServer() end,
})
properties.Add("nyrp_npc_remove", {
	MenuLabel = "Удалить NPC", Order = 2, MenuIcon = "icon16/user_delete.png",
	Filter = function(self, ent, ply) return IsValid(ent) and ent:GetClass() == "nyrp_npc" and ply:IsAdmin() end,
	Action = function(self, ent) net.Start("nyrp.npc.remove") net.WriteEntity(ent) net.SendToServer() end,
})
