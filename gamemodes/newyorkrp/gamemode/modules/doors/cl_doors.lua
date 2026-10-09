--[[
	Табличка на двери, которая сдаётся: название, цена в день, кто арендует. Видна, когда смотришь на дверь вблизи.
]]

local UI = NYRP.UI
local alpha = {}

hook.Add("HUDPaint", "nyrp.doors", function()
	if NYRP.HUDHidden() then return end
	local ply = LocalPlayer()
	local tr = ply:GetEyeTrace()
	local look = tr.Entity
	for ent, a in pairs(alpha) do
		if not IsValid(ent) then alpha[ent] = nil end
	end
	if IsValid(look) and look:GetNW2Int("nyrp.rent", 0) > 0 and tr.HitPos:Distance(ply:EyePos()) < 160 then
		alpha[look] = alpha[look] or 0
	end
	for ent, a in pairs(alpha) do
		local want = ent == look and tr.HitPos:Distance(ply:EyePos()) < 160
		a = UI.Approach(a, want and 1 or 0, want and 8 or 6)
		alpha[ent] = a
		if a <= 0.01 and not want then alpha[ent] = nil
		else
			local sc = (want and tr.HitPos or ent:WorldSpaceCenter()):ToScreen()
			local x, y = sc.x + UI.S(30), sc.y - UI.S(40)
			local name = ent:GetNW2String("nyrp.rentName", "Помещение")
			local owner = ent:GetNW2String("nyrp.rentOwnerName", "")
			local mine = ent:GetNW2Int("nyrp.rentOwner", 0) == ply:GetNW2Int("nyrp.charID", -1)
			local w, h = UI.S(300), UI.S(78)
			UI.RoundedRect(UI.S(12), x, y, w, h, Color(10, 12, 20, 220 * a))
			UI.RoundedRect(UI.S(2), x + UI.S(12), y + UI.S(14), UI.S(4), h - UI.S(28), UI.Alpha(owner == "" and UI.Col.green or Color(247, 198, 0), 255 * a))
			UI.DrawIcon(owner == "" and "home" or "lock", x + UI.S(38), y + h / 2, UI.S(24), Color(255, 255, 255, 230 * a))
			draw.SimpleText(name, NYRP.Font("bold", 17), x + UI.S(60), y + UI.S(14), Color(240, 241, 245, 255 * a))
			local sub
			if owner == "" then sub = "Сдаётся: " .. NYRP.Money.Format(ent:GetNW2Int("nyrp.rent", 0)) .. " в день · телефон → NY Homes"
			elseif mine then sub = (ent:GetNW2Bool("nyrp.locked") and "Заперто" or "Открыто") .. " · ключи — ЛКМ, F1 — жильцы"
			else sub = "Арендовано" end
			draw.SimpleText(sub, NYRP.Font("medium", 13), x + UI.S(60), y + UI.S(42), Color(200, 204, 214, 230 * a))
		end
	end
end)

-- ------------------------------------------------------- F1: квартира и жильцы --
local function personName(ent)
	if NYRP.Recog and NYRP.Recog.NameFor then return NYRP.Recog.NameFor(ent) end
	return ent:Nick()
end

net.Receive("nyrp.door.home", function()
	local id, name, locked = net.ReadString(), net.ReadString(), net.ReadBool()
	local residents = net.ReadTable()
	local near = {}
	for i = 1, net.ReadUInt(8) do near[i] = net.ReadEntity() end
	if IsValid(NYRP.DoorWin) then NYRP.DoorWin:Remove() end
	local win, body = UI.Window(name ~= "" and name or "Квартира", "home", 460, 520, { sub = locked and "заперто" or "открыто" })
	NYRP.DoorWin = win
	local function send(add, ent, cid)
		net.Start("nyrp.door.resident")
		net.WriteString(id)
		net.WriteBool(add)
		net.WriteEntity(ent or NULL)
		net.WriteString(cid or "")
		net.SendToServer()
	end
	local scroll = vgui.Create("DScrollPanel", body)
	scroll:Dock(FILL)
	local function header(text)
		local h = scroll:Add("DPanel")
		h:Dock(TOP)
		h:SetTall(UI.S(30))
		h.Paint = function(_, w, hh) draw.SimpleText(text, NYRP.Font("bold", 14), 0, hh / 2, UI.Col.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
	end
	header("ЖИЛЬЦЫ — у них работают ваши ключи")
	if #residents == 0 then
		local e = scroll:Add("DPanel")
		e:Dock(TOP)
		e:SetTall(UI.S(34))
		e.Paint = function(_, w, hh) draw.SimpleText("Пока никого. Жильцы забирают ключи в почтовом ящике.", NYRP.Font("regular", 14), 0, hh / 2, Color(170, 172, 182), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
	end
	for _, r in ipairs(residents) do
		local b = UI.AddButton(scroll, r.name .. "   — выселить", "user", function() send(false, nil, r.id) end, { accent = UI.Col.red })
		b:SetTooltip("Выселить жильца")
	end
	header("РЯДОМ С ВАМИ — поселить")
	if #near == 0 then
		local e = scroll:Add("DPanel")
		e:Dock(TOP)
		e:SetTall(UI.S(34))
		e.Paint = function(_, w, hh) draw.SimpleText("Подведите человека поближе (до 6 м).", NYRP.Font("regular", 14), 0, hh / 2, Color(170, 172, 182), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
	end
	for _, p in ipairs(near) do
		if IsValid(p) then
			UI.AddButton(scroll, personName(p), "user_plus", function() send(true, p) end, { accent = UI.Col.green })
		end
	end
end)
