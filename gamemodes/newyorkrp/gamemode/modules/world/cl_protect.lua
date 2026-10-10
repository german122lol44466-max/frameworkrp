--[[
	Защита пропов — клиент.
	  • С физганом или тулганом в руках при наведении на объект — плашка у прицела: чей он
	    (свой / имя владельца / постоянный / часть карты). Админ дополнительно видит ник Steam.
	  • Игроки с флагами строительства (e / n / v) открывают на Q спавн-меню (инвентарь у них — на O).
]]

NYRP.World = NYRP.World or {}
local W = NYRP.World

local hint = { a = 0, ent = nil, title = "", sub = "", col = color_white, icon = "user" }

local function info(ent, me)
	if ent:GetNW2Bool("nyrp.persist") then
		return "Постоянный объект", "сохраняется для карты", Color(120, 190, 255), "save"
	end
	local sid = ent:GetNW2String("nyrp.ownerSID", "")
	if sid == "" then
		if ent:IsPlayer() then return nil end
		return "Часть карты", "без владельца", Color(170, 175, 190), "world"
	end
	local name = ent:GetNW2String("nyrp.ownerName", "?")
	local mine = sid == W.SID(me)
	local online = IsValid(ent:GetNW2Entity("nyrp.owner"))
	local sub = mine and "можно двигать и удалять" or (online and "чужое — трогать нельзя" or "владелец вышел")
	if me:IsAdmin() and not mine then
		local nick = ent:GetNW2String("nyrp.ownerNick", "")
		if nick ~= "" then sub = nick .. " · " .. sub end
	end
	return mine and "Ваше" or name, sub, mine and Color(110, 210, 140) or Color(247, 198, 0), mine and "check" or "user"
end

hook.Add("HUDPaint", "nyrp.pp.hint", function()
	if NYRP.HUDHidden and NYRP.HUDHidden() then return end
	local UI = NYRP.UI
	local me = LocalPlayer()
	if not IsValid(me) or not me:Alive() then return end
	local wep = me:GetActiveWeapon()
	local cls = IsValid(wep) and wep:GetClass() or ""
	local want = false
	if cls == "weapon_physgun" or cls == "gmod_tool" then
		local tr = me:GetEyeTrace()
		local ent = tr.Entity
		if IsValid(ent) and not ent:IsWorld() and tr.HitPos:DistToSqr(me:EyePos()) < 4000 * 4000 then
			local title, sub, col, icon = info(ent, me)
			if title then
				want = true
				hint.ent, hint.title, hint.sub, hint.col, hint.icon = ent, title, sub, col, icon
			end
		end
	end
	hint.a = UI.Approach(hint.a, want and 1 or 0, want and 10 or 6)
	if hint.a <= 0.01 then return end
	local a = hint.a
	local fT, fS = NYRP.Font("bold", 15), NYRP.Font("medium", 12)
	local tw = UI.TextSize(hint.title, fT)
	local sw = UI.TextSize(hint.sub, fS)
	local w = math.max(tw, sw) + UI.S(62)
	local h = UI.S(48)
	local x, y = ScrW() / 2 + UI.S(26), ScrH() / 2 + UI.S(18)
	UI.RoundedRect(UI.S(10), x, y, w, h, Color(10, 12, 20, 215 * a))
	UI.RoundedRect(UI.S(2), x + UI.S(8), y + UI.S(10), UI.S(3), h - UI.S(20), UI.Alpha(hint.col, 255 * a))
	UI.DrawIcon(hint.icon, x + UI.S(30), y + h / 2, UI.S(20), Color(255, 255, 255, 230 * a))
	draw.SimpleText(hint.title, fT, x + UI.S(48), y + UI.S(7), Color(240, 241, 245, 255 * a))
	draw.SimpleText(hint.sub, fS, x + UI.S(48), y + UI.S(27), Color(195, 200, 212, 220 * a))
end)

-- --------------------------------------------- спавн-меню для строителей --
local function wrapSpawnMenu()
	local GMT = GAMEMODE or GM
	if not GMT or GMT.nyrpWorldMenuWrapped then return end
	GMT.nyrpWorldMenuWrapped = true
	local origOpen, origClose = GMT.OnSpawnMenuOpen, GMT.OnSpawnMenuClose
	local opened = false
	GMT.OnSpawnMenuOpen = function(self)
		local me = LocalPlayer()
		if IsValid(me) and not me:IsAdmin() and NYRP.HasCharacter(me) and W.CanBuild(me) and self.BaseClass and self.BaseClass.OnSpawnMenuOpen then
			opened = true
			if not W.toldInv then
				W.toldInv = true
				NYRP.Notify("У вас права строителя: Q — меню спавна, инвентарь — на O", "info", 7)
			end
			return self.BaseClass.OnSpawnMenuOpen(self)
		end
		if origOpen then return origOpen(self) end
	end
	GMT.OnSpawnMenuClose = function(self)
		if opened then
			opened = false
			if self.BaseClass and self.BaseClass.OnSpawnMenuClose then return self.BaseClass.OnSpawnMenuClose(self) end
			return
		end
		if origClose then return origClose(self) end
	end
end
hook.Add("Initialize", "nyrp.pp.menu", function(...) wrapSpawnMenu(...) end)
hook.Add("InitPostEntity", "nyrp.pp.menu", function(...) wrapSpawnMenu(...) end)
