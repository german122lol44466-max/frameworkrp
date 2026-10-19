--[[
	Сюжет на клиенте: задача слева сверху, карточка главы, субтитры радиопереговоров (со звуком),
	кольцо удержания E, вспышка подрыва и финальные титры.
]]

local S = WS.Story
local C = WS.Config
local UI = WS.UI
local E = WS.Ease

local st = { running = false, ch = 1, text = "", prog = "", frac = -1, fracShown = 0 }
local objT, objText = 0, ""
local card                  -- { ch, t0 }
local sub                   -- { id, t0, dur }
local boom                  -- { t0, k }
S.Ending = nil              -- { t0, time, kills, deaths }

function S.ClientState() return st end

net.Receive("ws.story.state", function()
	st.running = net.ReadBool()
	st.ch = net.ReadUInt(6)
	local text = net.ReadString()
	st.prog = net.ReadString()
	st.frac = net.ReadFloat()
	local n = net.ReadUInt(6)
	local list = {}
	for i = 1, n do
		list[i] = { pos = net.ReadVector(), kind = net.ReadString(), label = net.ReadString(), r = net.ReadUInt(12), ent = net.ReadEntity() }
	end
	WS.Markers.Set(list)
	if text ~= st.text then
		st.text = text
		if text ~= "" then
			objT, objText = RealTime(), text
			WS.Audio.Play("whitesilence/game/objective.ogg", { volume = 0.55 })
		end
	end
	if st.frac < 0 then st.fracShown = 0 end
end)

net.Receive("ws.story.line", function()
	local id = net.ReadString()
	if not S.Lines[id] then return end
	sub = { id = id, t0 = RealTime(), dur = S.LineTime(id) }
	WS.Audio.Play("whitesilence/story/" .. id .. ".ogg", { volume = 0.95 })
end)

net.Receive("ws.story.chapter", function()
	card = { ch = net.ReadUInt(6), t0 = RealTime() }
	WS.Audio.Play("whitesilence/intro/fade_boom.ogg", { volume = 0.45 })
end)

net.Receive("ws.story.boom", function()
	local pos = net.ReadVector()
	local d = IsValid(LocalPlayer()) and LocalPlayer():GetPos():Distance(pos) or 3000
	boom = { t0 = RealTime(), k = math.Clamp(1 - d / 6000, 0.2, 1) }
end)

net.Receive("ws.story.finish", function()
	S.Ending = { t0 = RealTime(), time = net.ReadFloat(), kills = net.ReadUInt(16), deaths = net.ReadUInt(16) }
	WS.Audio.Play("whitesilence/intro/heli_interior.ogg", { volume = 0.0, fade = 0.01 }):Fade(0.6, 4)
end)

-- после возврата в меню финал закрывается
hook.Add("Think", "ws.story", function()
	if S.Ending and IsValid(LocalPlayer()) and not WS.Lobby.InGame(LocalPlayer()) then
		S.Ending = nil
		WS.Audio.StopAll(2)
	end
end)

local function hudOK()
	return WS.HUD and WS.HUD.Visible()
end

-- ---------------------------------------------------------------- задача

local function drawObjective(w, h, s, a)
	if not st.running or st.text == "" then return end
	local age = RealTime() - objT
	local inA = E.OutCubic(age / 0.6)
	local x, y = 38 * s - (1 - inA) * 30 * s, 40 * s
	a = a * inA
	local ch = S.Chapters[st.ch]
	local accent = Color(226, 190, 120, 230 * a)
	draw.SimpleText(string.format("ГЛАВА %s  ·  %s", S.Roman[st.ch] or st.ch, WS.Upper(ch and ch.title or "")),
		WS.Font("menusemi", 15), x + 14 * s, y, accent)
	-- вертикальная черта, вспыхивает при новой задаче
	local flash = 1 - E.Clamp01((age - 0.3) / 1.5)
	surface.SetDrawColor(226, 190, 120, (140 + 115 * flash) * a)
	surface.DrawRect(x, y + 2 * s, 3 * s, 54 * s)
	draw.SimpleText(st.text, WS.Font("menubold", 24), x + 14 * s + 1, y + 20 * s + 1, Color(0, 0, 0, 140 * a))
	draw.SimpleText(st.text, WS.Font("menubold", 24), x + 14 * s, y + 20 * s, Color(240, 242, 246, 255 * a))
	local py = y + 50 * s
	if st.frac >= 0 then
		st.fracShown = WS.Approach(st.fracShown, st.frac, 0.6)
		local bw = 260 * s
		surface.SetDrawColor(255, 255, 255, 30 * a)
		surface.DrawRect(x + 14 * s, py + 4 * s, bw, 4 * s)
		surface.SetDrawColor(226, 190, 120, 230 * a)
		surface.DrawRect(x + 14 * s, py + 4 * s, bw * st.fracShown, 4 * s)
		py = py + 14 * s
	end
	if st.prog ~= "" then
		draw.SimpleText(st.prog, WS.Font("menulight", 17), x + 14 * s, py, Color(196, 204, 216, 220 * a))
	end
end

-- ---------------------------------------------------------------- карточка главы

local function drawCard(w, h, s)
	if not card then return end
	local t = RealTime() - card.t0
	if t > 5.5 then card = nil return end
	local a = E.Window(t, 0, 0.9, 4.2, 5.5)
	local ch = S.Chapters[card.ch]
	if not ch then return end
	local cy = h * 0.34
	draw.SimpleText(S.Roman[card.ch] or tostring(card.ch), WS.Font("title", 92), w / 2, cy, Color(236, 238, 242, 230 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	local lw = 140 * s * E.OutCubic((t - 0.2) / 1.0)
	surface.SetDrawColor(196, 38, 38, 220 * a)
	surface.DrawRect(w / 2 - lw, cy + 56 * s, lw * 2, 2 * s)
	draw.SimpleText(WS.Upper(ch.title), WS.Font("sub", 34), w / 2, cy + 86 * s, Color(226, 190, 120, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- ---------------------------------------------------------------- субтитры

local function drawSub(w, h, s)
	if not sub then return end
	local t = RealTime() - sub.t0
	if t > sub.dur + 0.8 then sub = nil return end
	local line = S.Lines[sub.id]
	local sp = S.Speakers[line.who] or { name = "?", color = color_white }
	local a = E.Window(t, 0, 0.25, sub.dur, sub.dur + 0.8)
	local by = h * 0.86
	-- мягкая подложка
	surface.SetMaterial(UI.Mat(WS.Intro.Path .. "flake.png", "smooth"))
	surface.SetDrawColor(0, 0, 0, 150 * a)
	surface.DrawTexturedRect(w * 0.2, by - 90 * s, w * 0.6, 150 * s)
	draw.SimpleText(WS.Upper(sp.name), WS.Font("submed", 22), w / 2, by - 44 * s,
		Color(sp.color.r, sp.color.g, sp.color.b, 240 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
	UI.Reveal(line.text, { font = WS.Font("sub", 30), x = w / 2, y = by - 38 * s, maxW = w * 0.56, t = t, cps = 45,
		fade = 0.3, alpha = a, color = Color(232, 236, 242), rise = 3, shadow = 0.8 })
end

-- ---------------------------------------------------------------- удержание E

local function arc(cx, cy, r, th, frac, col)
	local segs = 64
	surface.SetDrawColor(col)
	for i = 0, math.floor(segs * frac) - 1 do
		local a0 = math.rad(-90 + i / segs * 360)
		local a1 = math.rad(-90 + (i + 1) / segs * 360)
		local c0, s0, c1, s1 = math.cos(a0), math.sin(a0), math.cos(a1), math.sin(a1)
		surface.DrawPoly({
			{ x = cx + c0 * r, y = cy + s0 * r }, { x = cx + c1 * r, y = cy + s1 * r },
			{ x = cx + c1 * (r - th), y = cy + s1 * (r - th) }, { x = cx + c0 * (r - th), y = cy + s0 * (r - th) },
		})
	end
end

local function drawUse(w, h, s)
	local ply = LocalPlayer()
	local f = ply:GetNW2Float("ws_use", 0)
	if f <= 0 then return end
	local cx, cy = w / 2, h / 2
	draw.NoTexture()
	arc(cx, cy, 30 * s, 3 * s, 1, Color(255, 255, 255, 40))
	arc(cx, cy, 30 * s, 3 * s, f, Color(226, 190, 120, 240))
	local label = ply:GetNW2String("ws_use_label", "")
	draw.SimpleText(WS.Upper(label ~= "" and label or "Действие"), WS.Font("menusemi", 17), cx, cy + 44 * s,
		Color(240, 242, 246, 230), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
end

-- подсказка [E] рядом с объектом, когда на него смотришь
local function drawUseHint(w, h, s)
	local ply = LocalPlayer()
	if ply:GetNW2Float("ws_use", 0) > 0 then return end
	local eye = ply:EyePos()
	for _, m in ipairs(WS.Markers.List) do
		if m.kind ~= "goto" and m.r == 0 and m.label ~= "" then
			local to = m.pos - eye
			if to:Length() < C.StoryUseDist + 60 and ply:GetAimVector():Dot(to:GetNormalized()) > 0.8 then
				draw.SimpleText("[E]  " .. WS.Upper(m.label), WS.Font("menusemi", 18), w / 2, h / 2 + 40 * s,
					Color(240, 242, 246, 230), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
				return
			end
		end
	end
end

-- ---------------------------------------------------------------- финал

local function drawEnding(w, h, s)
	local en = S.Ending
	local t = RealTime() - en.t0
	surface.SetDrawColor(0, 0, 0, 255 * E.Smooth(t / 2.5))
	surface.DrawRect(0, 0, w, h)
	local y = h * 0.3
	for i, line in ipairs(S.EndingText) do
		local lt = t - 2.5 - (i - 1) * 3.2
		if lt > 0 then
			y = y + UI.Reveal(line, { font = WS.Font("storyi", 34), x = w / 2, y = y, maxW = w * 0.6, t = lt, cps = 32,
				fade = 0.5, color = Color(220, 226, 234), hl = Color(214, 92, 84), rise = 5 }) + 26 * s
		end
	end
	local st2 = t - 2.5 - #S.EndingText * 3.2
	if st2 > 0 then
		local a = E.Smooth(st2 / 1.2)
		draw.SimpleText("ОПЕРАЦИЯ ЗАВЕРШЕНА", WS.Font("menubold", 30), w / 2, h * 0.72, Color(226, 190, 120, 255 * a), TEXT_ALIGN_CENTER)
		local mins = math.floor(en.time / 60)
		draw.SimpleText(string.format("Время: %d:%02d   ·   Уничтожено: %d   ·   Потери: %d", mins, math.floor(en.time % 60), en.kills, en.deaths),
			WS.Font("menulight", 20), w / 2, h * 0.72 + 44 * s, Color(196, 204, 216, 230 * a), TEXT_ALIGN_CENTER)
		local left = math.max(0, math.ceil(C.StoryEndTime - t))
		draw.SimpleText("Возвращение в меню через " .. left .. " с", WS.Font("menulight", 16), w / 2, h * 0.72 + 80 * s,
			Color(150, 160, 172, 200 * a), TEXT_ALIGN_CENTER)
	end
end

hook.Add("HUDPaint", "ws.story", function()
	local w, h = ScrW(), ScrH()
	local s = h / 1080
	if S.Ending then drawEnding(w, h, s) return end
	if boom then
		local t = RealTime() - boom.t0
		if t > 3 then boom = nil
		else
			surface.SetDrawColor(255, 248, 235, 255 * boom.k * (1 - E.Clamp01(t / 2.5)) ^ 2)
			surface.DrawRect(0, 0, w, h)
		end
	end
	if not hudOK() then return end
	local a = WS.HUD.Alpha or 1
	drawObjective(w, h, s, a)
	drawCard(w, h, s)
	drawSub(w, h, s)
	drawUse(w, h, s)
	drawUseHint(w, h, s)
end)
