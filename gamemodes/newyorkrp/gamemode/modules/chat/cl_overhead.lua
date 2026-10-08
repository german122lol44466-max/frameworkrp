--[[
	Над головой — настоящий 3D-текст в мире, всегда повёрнутый к камере
	(виден и свой, если посмотреть вверх; стены его закрывают). Снизу вверх:
	  1) ник при наведении: «НЕИЗВЕСТНЫЙ» или имя, если знакомы (иконка слева);
	  2) значок войса, если говорит в микрофон;
	  3) «Говорит... / Кричит... / Шепчет...», пока печатает;
	  4) до трёх последних сообщений: новое снизу, старые уходят вверх, четвёртое испаряется.
]]

local UI = NYRP.UI
local T = NYRP.Chat.Types
NYRP.Overhead = NYRP.Overhead or {}
local O = NYRP.Overhead

local bubbles = {}   -- [ply] = { {text, kind, born, y, dying} }
local state = {}     -- [ply] = { tag, typing, voice }
local LIFE = 9
local SCALE = 0.055  -- единиц мира на пиксель

function O.AddBubble(ply, kind, text)
	local list = bubbles[ply] or {}
	bubbles[ply] = list
	if kind == T.ME then text = "** " .. NYRP.CharName(ply) .. " " .. text end
	table.insert(list, 1, { text = text, kind = kind, born = RealTime() })
	local alive = 0
	for _, b in ipairs(list) do
		if not b.dying then
			alive = alive + 1
			if alive > 3 then b.dying = RealTime() end
		end
	end
end

local typingInfo = {
	[T.IC] = { "Говорит", "message" },
	[T.WHISPER] = { "Шепчет", "ear" },
	[T.YELL] = { "Кричит", "speaker" },
	[T.ME] = { "Выполняет действие", "hand" },
	[T.IT] = { "Описывает", "eye" },
}

local function headPos(ply)
	local bone = ply:LookupBone("ValveBiped.Bip01_Head1")
	local pos = bone and ply:GetBonePosition(bone) or (ply:GetPos() + Vector(0, 0, 64))
	return pos + Vector(0, 0, 12 * ply:GetModelScale())
end

local function size(text, font)
	surface.SetFont(font)
	return surface.GetTextSize(text)
end

-- «Таблетка» с иконкой; низ таблетки — y. Возвращает высоту.
local function pill(y, text, font, icon, col, a, iconCol)
	local tw, th = size(text, font)
	local isz = icon and th * 0.95 or 0
	local padX = 16
	local w = tw + padX * 2 + (icon and isz + 10 or 0)
	local h = th + 14
	local x = -w / 2
	UI.RoundedRect(h / 2, x, y - h, w, h, Color(8, 10, 16, 200 * a))
	local tx = x + padX
	if icon then
		local ic = iconCol or col
		UI.DrawIcon(icon, tx + isz / 2, y - h / 2, isz, Color(ic.r, ic.g, ic.b, 255 * a))
		tx = tx + isz + 10
	end
	draw.SimpleText(text, font, tx, y - h / 2, Color(col.r, col.g, col.b, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	return h
end

-- Что у игрока в руках -> иконка (materials/nyrp/status/w_*.png).
local holdIcons = {
	pistol = "w_pistol", revolver = "w_pistol", duel = "w_pistol", smg = "w_smg", ar2 = "w_rifle", rpg = "w_rifle",
	crossbow = "w_rifle", shotgun = "w_shotgun", melee = "w_melee", melee2 = "w_melee", knife = "w_melee",
	grenade = "w_grenade", slam = "w_grenade", camera = "w_tool", physgun = "w_tool",
}
local function weaponIcon(ply)
	local wep = ply:GetActiveWeapon()
	if not IsValid(wep) or wep:GetClass() == "nyrp_hands" or wep:GetNoDraw() then return end
	local ht = wep.GetHoldType and wep:GetHoldType() or ""
	if ht == "" or ht == "normal" or ht == "fist" then return end
	return holdIcons[ht] or "w_pistol"
end

-- Ник над головой (как в референсе): крупный светлый текст с тенью, слева — оружие в руках.
local NAME_COL = Color(214, 216, 222)
local function nameTag(ply, y, a)
	local known = NYRP.Recog and NYRP.Recog.Knows(ply)
	local text = known and NYRP.CharName(ply) or "НЕИЗВЕСТНЫЙ"
	local font = known and NYRP.FontRaw("medium", 46) or NYRP.FontRaw("title", 46)
	local tw, th = size(text, font)
	local icon = weaponIcon(ply)
	local isz = th * 0.95
	local w = tw + (icon and isz + 22 or 0)
	local x = -w / 2
	local by = y - th + (1 - a) * 12
	local col = known and NAME_COL or Color(232, 232, 236)
	if icon then
		local mat = UI.Mat("nyrp/status/" .. icon .. ".png")
		surface.SetMaterial(mat)
		surface.SetDrawColor(0, 0, 0, 120 * a)
		surface.DrawTexturedRect(x + 2, by + (th - isz) / 2 + 3, isz, isz)
		surface.SetDrawColor(col.r, col.g, col.b, 235 * a)
		surface.DrawTexturedRect(x, by + (th - isz) / 2, isz, isz)
		x = x + isz + 22
	end
	draw.SimpleText(text, font, x + 2, by + 3, Color(0, 0, 0, 130 * a))
	draw.SimpleText(text, font, x, by, Color(col.r, col.g, col.b, 255 * a))
	return th
end

local function drawPlayer(ply, me, eye, look, now)
	local dist = eye:Distance(ply:GetPos())
	local st = state[ply] or { tag = 0, typing = 0, voice = 0, typeKind = T.IC }
	state[ply] = st

	local hovered = ply ~= me and look == ply and dist < NYRP.Config.Ranges.NameTag
	st.tag = UI.Approach(st.tag, hovered and 1 or 0, hovered and 12 or 5)
	local tk = ply:GetNW2Int("nyrp.typing", 0)
	if tk > 0 then st.typeKind = tk end
	st.typing = UI.Approach(st.typing, (tk > 0 and typingInfo[tk]) and 1 or 0, 10)
	st.voice = UI.Approach(st.voice, ply:IsSpeaking() and 1 or 0, 10)
	local list = bubbles[ply]
	if st.tag < 0.01 and st.typing < 0.01 and st.voice < 0.01 and not (list and #list > 0) then return end

	-- плоскость текста смотрит прямо в камеру
	local pos = headPos(ply)
	local ang = EyeAngles()
	ang:RotateAroundAxis(ang:Up(), -90)
	ang:RotateAroundAxis(ang:Forward(), 90)
	local fade = math.Clamp((900 - dist) / 150, 0, 1)
	if fade <= 0 then return end

	cam.Start3D2D(pos, ang, SCALE * math.Clamp(dist / 260, 0.85, 1.6))
	surface.SetAlphaMultiplier(fade)
	local y, gap = 0, 10

	if st.tag > 0.01 then
		y = y - nameTag(ply, y, UI.Ease(st.tag)) - gap * st.tag
	end
	if st.voice > 0.01 then
		local vol = math.Clamp(ply:VoiceVolume() * 3, 0, 1)
		local r = 22 * (1 + vol * 0.35)
		UI.Circle(0, y - 26, r, Color(255, 255, 255, 235 * st.voice))
		UI.DrawIcon("mic", 0, y - 26, r * 1.15, Color(10, 12, 18, 255 * st.voice))
		y = y - (54 + gap) * st.voice
	end
	if st.typing > 0.01 then
		local info = typingInfo[st.typeKind] or typingInfo[T.IC]
		local dots = string.rep(".", math.floor(now * 3) % 4)
		local h = pill(y, info[1] .. dots, NYRP.FontRaw("medium", 26), info[2], UI.Col.dim, st.typing, UI.Col.accent)
		y = y - (h + gap) * st.typing
	end
	if list then
		local font = NYRP.FontRaw("medium", 26)
		local maxW = 520
		for i = #list, 1, -1 do
			local b = list[i]
			if now - b.born > LIFE + 0.6 or (b.dying and now - b.dying > 0.6) then table.remove(list, i) end
		end
		local cy = y
		for _, b in ipairs(list) do
			local age = now - b.born
			local a = UI.Ease(age / 0.25)
			if age > LIFE then a = a * (1 - (age - LIFE) / 0.6) end
			local rise = 0
			if b.dying then
				local d = (now - b.dying) / 0.6
				a = a * (1 - d)
				rise = UI.Ease(d) * 40
			end
			b.lines = b.lines or UI.Wrap(b.text, font, maxW)
			local lh = 32
			local h = #b.lines * lh + 18
			local w = 0
			for _, l in ipairs(b.lines) do w = math.max(w, (size(l, font))) end
			w = w + 34
			b.y = b.y and UI.Approach(b.y, cy, 12) or cy
			local by = b.y - rise
			local col = b.kind == T.WHISPER and Color(175, 185, 205) or (b.kind == T.YELL and Color(255, 236, 200) or (b.kind == T.ME and Color(196, 160, 255) or UI.Col.text))
			if b.kind == T.YELL then UI.RoundedRect(16, -w / 2 - 3, by - h - 3, w + 6, h + 6, Color(255, 138, 36, 110 * a)) end
			UI.RoundedRect(14, -w / 2, by - h, w, h, Color(10, 12, 20, 210 * a))
			for li, l in ipairs(b.lines) do
				draw.SimpleText(l, font, 0, by - h + 9 + (li - 1) * lh, Color(col.r, col.g, col.b, 255 * a), TEXT_ALIGN_CENTER)
			end
			if not b.dying then cy = cy - (h + gap) * math.min(a * 1.5, 1) end
		end
	end
	surface.SetAlphaMultiplier(1)
	cam.End3D2D()
end

hook.Add("PostDrawTranslucentRenderables", "nyrp.overhead", function(depth, skybox)
	if skybox or NYRP.HUDHidden() then return end
	local me = LocalPlayer()
	local eye = EyePos()
	local look = me:GetEyeTrace().Entity
	local now = RealTime()
	for _, ply in ipairs(player.GetAll()) do
		-- свой текст тоже рисуем: его видно, если посмотреть вверх (и в третьем лице)
		if IsValid(ply) and ply:Alive() and not ply:GetNoDraw() and eye:DistToSqr(ply:GetPos()) < 900 * 900 then
			drawPlayer(ply, me, eye, look, now)
		end
	end
end)

hook.Add("EntityRemoved", "nyrp.overhead", function(ent)
	bubbles[ent] = nil
	state[ent] = nil
end)
