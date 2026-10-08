--[[
	Над головой игрока (снизу вверх, без наложений):
	  1) ник при наведении: «НЕИЗВЕСТНЫЙ» или имя, если знакомы (иконка слева);
	  2) иконка войса, если говорит в микрофон;
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

function O.AddBubble(ply, kind, text)
	local list = bubbles[ply] or {}
	bubbles[ply] = list
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
	[T.ME] = { "Действует", "hand" },
}

local function headPos(ply)
	local bone = ply:LookupBone("ValveBiped.Bip01_Head1")
	local pos = bone and ply:GetBonePosition(bone) or (ply:GetPos() + Vector(0, 0, 64))
	return pos + Vector(0, 0, 11 * ply:GetModelScale())
end

local function pill(x, y, text, font, icon, col, a, iconCol)
	local tw, th = UI.TextSize(text, font)
	local isz = icon and th * 0.95 or 0
	local padX = UI.S(10)
	local w = tw + padX * 2 + (icon and isz + UI.S(6) or 0)
	local h = th + UI.S(8)
	local px = x - w / 2
	UI.RoundedRect(h / 2, px, y - h, w, h, Color(8, 10, 16, 190 * a))
	local tx = px + padX
	if icon then
		UI.DrawIcon(icon, tx + isz / 2, y - h / 2, isz, Color((iconCol or col).r, (iconCol or col).g, (iconCol or col).b, 255 * a))
		tx = tx + isz + UI.S(6)
	end
	draw.SimpleText(text, font, tx, y - h / 2, Color(col.r, col.g, col.b, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	return h
end

hook.Add("HUDPaint", "nyrp.overhead", function()
	if NYRP.HUDHidden() then return end
	local me = LocalPlayer()
	local eye = EyePos()
	local look = me:GetEyeTrace().Entity
	local now = RealTime()
	local showSelf = NYRP.Camera.IsThirdPerson()

	for _, ply in ipairs(player.GetAll()) do
		if not IsValid(ply) or not ply:Alive() or ply:GetNoDraw() or (ply == me and not showSelf) then continue end
		local dist = eye:Distance(ply:GetPos())
		if dist > 900 then continue end
		local st = state[ply] or { tag = 0, typing = 0, voice = 0, typeKind = T.IC }
		state[ply] = st

		local hovered = ply ~= me and look == ply and dist < NYRP.Config.Ranges.NameTag
		st.tag = UI.Approach(st.tag, hovered and 1 or 0, hovered and 12 or 5)
		local tk = ply:GetNW2Int("nyrp.typing", 0)
		if tk > 0 then st.typeKind = tk end
		st.typing = UI.Approach(st.typing, (tk > 0 and typingInfo[tk]) and 1 or 0, 10)
		st.voice = UI.Approach(st.voice, ply:IsSpeaking() and 1 or 0, 10)

		local list = bubbles[ply]
		if st.tag < 0.01 and st.typing < 0.01 and st.voice < 0.01 and not (list and #list > 0) then continue end

		local sc = headPos(ply):ToScreen()
		if not sc.visible then continue end
		local k = math.Clamp(1.15 - dist / 700, 0.6, 1)
		local x, y = sc.x, sc.y
		local gap = UI.S(6)

		-- 1) ник
		if st.tag > 0.01 then
			local a = UI.Ease(st.tag)
			local known = NYRP.Recog and NYRP.Recog.Knows(ply)
			local masked = ply:GetNW2Bool("nyrp.masked")
			local text = known and NYRP.CharName(ply) or "НЕИЗВЕСТНЫЙ"
			local font = known and NYRP.Font("semibold", math.Round(17 * k)) or NYRP.Font("title", math.Round(17 * k))
			local icon = known and "user" or (masked and "mask" or "question")
			local h = pill(x, y - (1 - a) * UI.S(6), text, font, icon, known and UI.Col.nameGreen or UI.Col.text, a, known and UI.Col.nameGreen or UI.Col.accent)
			y = y - (h + gap) * a
		end
		-- 2) войс
		if st.voice > 0.01 then
			local vol = math.Clamp(ply:VoiceVolume() * 3, 0, 1)
			local r = UI.S(13) * k * (1 + vol * 0.35)
			UI.Circle(x, y - UI.S(16) * k, r, Color(255, 255, 255, 235 * st.voice))
			UI.DrawIcon("mic", x, y - UI.S(16) * k, r * 1.15, Color(10, 12, 18, 255 * st.voice))
			y = y - (UI.S(32) * k + gap) * st.voice
		end
		-- 3) печатает
		if st.typing > 0.01 then
			local info = typingInfo[st.typeKind] or typingInfo[T.IC]
			local dots = string.rep(".", math.floor(now * 3) % 4)
			local h = pill(x, y, info[1] .. dots, NYRP.Font("medium", math.Round(15 * k)), info[2], UI.Col.dim, st.typing, UI.Col.accent)
			y = y - (h + gap) * st.typing
		end
		-- 4) сообщения
		if list then
			local font = NYRP.Font("medium", math.Round(15 * k))
			local maxW = UI.S(300) * k
			local cy = y
			for i = #list, 1, -1 do
				local b = list[i]
				local age = now - b.born
				if age > LIFE + 0.6 or (b.dying and now - b.dying > 0.6) then table.remove(list, i) end
			end
			for i, b in ipairs(list) do
				local age = now - b.born
				local a = UI.Ease(age / 0.25)
				if age > LIFE then a = a * (1 - (age - LIFE) / 0.6) end
				local rise = 0
				if b.dying then
					local d = (now - b.dying) / 0.6
					a = a * (1 - d)
					rise = UI.Ease(d) * UI.S(26)
				end
				b.lines = b.lines or UI.Wrap(b.text, font, maxW)
				local lh = UI.S(19) * k
				local h = #b.lines * lh + UI.S(12)
				local w = 0
				for _, l in ipairs(b.lines) do w = math.max(w, UI.TextSize(l, font)) end
				w = w + UI.S(22)
				b.y = b.y and UI.Approach(b.y, cy, 12) or cy
				local by = b.y - rise
				local col = b.kind == T.WHISPER and Color(175, 185, 205) or (b.kind == T.YELL and Color(255, 236, 200) or (b.kind == T.ME and Color(196, 160, 255) or UI.Col.text))
				UI.RoundedRect(UI.S(10), x - w / 2, by - h, w, h, Color(10, 12, 20, 200 * a))
				if b.kind == T.YELL then UI.Outline(UI.S(10), x - w / 2, by - h, w, h, Color(255, 138, 36, 120 * a), 1) end
				for li, l in ipairs(b.lines) do
					draw.SimpleText(l, font, x, by - h + UI.S(6) + (li - 1) * lh, Color(col.r, col.g, col.b, 255 * a), TEXT_ALIGN_CENTER)
				end
				if not b.dying then cy = cy - (h + gap) * math.min(a * 1.5, 1) end
			end
		end
	end
end)

hook.Add("EntityRemoved", "nyrp.overhead", function(ent)
	bubbles[ent] = nil
	state[ent] = nil
end)
