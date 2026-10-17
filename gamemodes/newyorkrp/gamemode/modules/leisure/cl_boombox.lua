--[[
	Бумбокс на клиенте: проигрывание интернет-радио объёмным звуком рядом с каждым бумбоксом
	(sound.PlayURL "3d"), затухание по расстоянию, остановка вдали, при выключении и удалении.
	Если поток станции не открылся — пробуется запасной адрес, затем сообщение.
	Личные настройки: nyrp_boombox_volume (0–1) — громкость всех бумбоксов, nyrp_boombox_mute 1 — не слышать чужие.
	Меню по E: владельцу — станции, громкость, «Выключить», «Забрать»; остальным — что играет и свои настройки.
]]

NYRP.Leisure = NYRP.Leisure or {}
local LS = NYRP.Leisure
LS.Boombox = LS.Boombox or {}
local BB = LS.Boombox
local UI = NYRP.UI

local cvVolume = CreateClientConVar("nyrp_boombox_volume", "0.8", true, false, "Громкость бумбоксов (0–1)", 0, 1)
local cvMute = CreateClientConVar("nyrp_boombox_mute", "0", true, false, "1 — не слышать чужие бумбоксы", 0, 1)

local FULL = 500          -- до этого расстояния — полная громкость (дальше — плавное затухание)
BB.Ch = BB.Ch or {}       -- [ent] = { station, idx, ch, token, failed }

local function stop(st)
	if st and st.ch and IsValid(st.ch) then st.ch:Stop() end
	if st then st.ch = nil st.token = nil end
end

function BB.StopEnt(ent)
	local st = BB.Ch[ent]
	if st then
		stop(st)
		BB.Ch[ent] = nil
	end
end

local function load(ent, st)
	local def = BB.Stations[st.station]
	local url = def and def.urls[st.idx]
	if not url then
		st.failed = true
		local own = IsValid(ent) and ent:GetBoxOwner() == LocalPlayer()
		if own or (IsValid(ent) and ent:GetPos():DistToSqr(LocalPlayer():GetPos()) < 400 * 400) then
			NYRP.Notify("Бумбокс: поток «" .. (def and def.name or "?") .. "» не открылся. Попробуйте другую станцию.", "warning", 5)
		end
		return
	end
	local token = {}
	st.token = token
	sound.PlayURL(url, "3d noblock", function(ch)
		-- пока грузилось, станцию сменили / бумбокс убрали / ушли далеко
		if BB.Ch[ent] ~= st or st.token ~= token or not IsValid(ent) then
			if IsValid(ch) then ch:Stop() end
			return
		end
		if not IsValid(ch) then
			st.idx = st.idx + 1
			load(ent, st)
			return
		end
		st.ch = ch
		ch:SetPos(ent:GetPos())
		ch:Set3DFadeDistance(FULL, 100000)
		ch:SetVolume(0)
		ch:Play()
	end)
end

local function wanted(ent, ply)
	if ent:IsDormant() then return false end
	local station = ent:GetBoxStation()
	if station < 1 or not BB.Stations[station] then return false end
	if ent:GetBoxOwner() ~= ply and cvMute:GetBool() then return false end
	return true
end

-- раз в 0.25 с: какие потоки включить/выключить
local nextScan = 0
local function scan()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local eye = ply:EyePos()
	for ent, st in pairs(BB.Ch) do
		if not IsValid(ent) then
			stop(st)
			BB.Ch[ent] = nil
		end
	end
	for _, ent in ipairs(ents.FindByClass("nyrp_boombox")) do
		local st = BB.Ch[ent]
		local dist = ent:GetPos():Distance(eye)
		local want = wanted(ent, ply)
		if want then
			if st then
				want = dist < BB.Range + 200
			else
				want = dist < BB.Range
			end
		end
		local station = ent:GetBoxStation()
		if want then
			if not st or st.station ~= station then
				if st then stop(st) end
				st = { station = station, idx = 1 }
				BB.Ch[ent] = st
				load(ent, st)
			end
		elseif st then
			stop(st)
			-- помним неудачу, чтобы не открывать сломанный поток снова и снова
			if st.failed and station == st.station then
				st.ch = nil
			else
				BB.Ch[ent] = nil
			end
		end
	end
end

hook.Add("Think", "nyrp.boombox", function()
	local now = RealTime()
	if now >= nextScan then
		nextScan = now + 0.25
		scan()
	end
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local eye = ply:EyePos()
	local my = math.Clamp(cvVolume:GetFloat(), 0, 1)
	for ent, st in pairs(BB.Ch) do
		local ch = st.ch
		if ch and IsValid(ch) and IsValid(ent) then
			local pos = ent:GetPos()
			ch:SetPos(pos)
			local dist = pos:Distance(eye)
			local fade = 1 - math.Clamp((dist - FULL) / math.max(BB.Range - FULL, 1), 0, 1)
			ch:SetVolume(math.Clamp(ent:GetBoxVolume() / 100, 0, 1) * my * fade)
		end
	end
end)

-- ------------------------------------------------------------------ меню --
local function act(ent, name, val)
	net.Start("nyrp.bb.act")
	net.WriteEntity(ent)
	net.WriteString(name)
	net.WriteUInt(math.Clamp(math.floor(val or 0), 0, 255), 8)
	net.SendToServer()
end

local function personal(parent)
	local head = vgui.Create("DPanel", parent)
	head:Dock(TOP)
	head:SetTall(UI.S(30))
	head:DockMargin(0, UI.S(6), 0, 0)
	head.Paint = function(_, w, h)
		draw.SimpleText("МОИ НАСТРОЙКИ ЗВУКА", NYRP.Font("title", 15), 0, h - UI.S(4), UI.Col.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
		surface.SetDrawColor(255, 255, 255, 14)
		surface.DrawRect(0, h - 1, w, 1)
	end
	local sl = vgui.Create("NYRP.Slider", parent)
	sl:Dock(TOP)
	sl:DockMargin(0, UI.S(6), 0, 0)
	sl:SetLabel("Громкость всех бумбоксов (для меня)")
	sl:SetMinMax(0, 1)
	sl:SetPercent(true)
	sl:SetConVar("nyrp_boombox_volume")
	local tg = vgui.Create("NYRP.Toggle", parent)
	tg:Dock(TOP)
	tg:DockMargin(0, UI.S(6), 0, 0)
	tg:SetLabel("Не слышать чужие бумбоксы")
	tg:SetDescription("Свой бумбокс вы слышите всегда")
	tg:SetConVar("nyrp_boombox_mute")
end

local function nowPlaying(parent, ent)
	local p = vgui.Create("DPanel", parent)
	p:Dock(TOP)
	p:SetTall(UI.S(70))
	p:DockMargin(0, 0, 0, UI.S(10))
	p.Paint = function(_, w, h)
		UI.RoundedRect(UI.S(10), 0, 0, w, h, Color(255, 255, 255, 8))
		if not IsValid(ent) then return end
		local s = BB.Stations[ent:GetBoxStation()]
		local st = BB.Ch[ent]
		local col = s and s.color or UI.Col.faint
		UI.DrawIcon(s and "music" or "volume", UI.S(36), h / 2, UI.S(30), col)
		local title = s and s.name or "Выключен"
		local sub = s and s.genre or "Ничего не играет"
		if s then
			if st and st.failed then
				sub = "поток не открылся"
			elseif st and not st.ch then
				sub = "подключение…"
			elseif cvMute:GetBool() and ent:GetBoxOwner() ~= LocalPlayer() then
				sub = sub .. " · у вас выключены чужие бумбоксы"
			end
		end
		draw.SimpleText(title, NYRP.Font("title", 22), UI.S(64), h / 2 - UI.S(10), color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText(sub, NYRP.Font("regular", 14), UI.S(64), h / 2 + UI.S(14), UI.Col.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		if s then
			-- «эквалайзер»
			for i = 1, 5 do
				local bh = UI.S(6) + math.abs(math.sin(RealTime() * (3 + i) + i)) * UI.S(26)
				surface.SetDrawColor(col.r, col.g, col.b, 200)
				surface.DrawRect(w - UI.S(90) + i * UI.S(12), h / 2 + UI.S(16) - bh, UI.S(8), bh)
			end
		end
	end
end

net.Receive("nyrp.bb.open", function()
	local ent = net.ReadEntity()
	local owner = net.ReadBool()
	if not IsValid(ent) then return end
	if IsValid(BB.Win) then BB.Win:Close() end
	local win, body = UI.Window("Бумбокс", "music", 560, owner and 640 or 400, { sub = owner and "Ваш бумбокс" or "Играет рядом" })
	BB.Win = win
	nowPlaying(body, ent)
	if owner then
		local grid = vgui.Create("DPanel", body)
		grid:Dock(TOP)
		grid.Paint = function() end
		local per, bh, gap = 2, 46, 8
		local rows = math.ceil(#BB.Stations / per)
		grid:SetTall(rows * UI.S(bh + gap))
		local gw = body:GetWide()
		local cw = (gw - UI.S(gap)) / per
		for i, s in ipairs(BB.Stations) do
			local b = UI.AddButton(grid, s.name, "music", function() act(ent, "station", i) end, { dock = false, style = "ghost", accent = s.color, h = bh })
			b:SetPos(((i - 1) % per) * (cw + UI.S(gap)), math.floor((i - 1) / per) * UI.S(bh + gap))
			b:SetWide(cw)
			local base = b.Paint
			b.Paint = function(pb, w, h)
				pb.Style = (IsValid(ent) and ent:GetBoxStation() == i) and "solid" or "ghost"
				return base(pb, w, h)
			end
		end
		local vol = vgui.Create("NYRP.Slider", body)
		vol:Dock(TOP)
		vol:DockMargin(0, UI.S(6), 0, 0)
		vol:SetLabel("Громкость бумбокса (для всех)")
		vol:SetMinMax(0, 100)
		vol:SetDecimals(0)
		vol:SetSuffix("%")
		vol:SetValue(ent:GetBoxVolume(), true)
		local sent, lastSend = ent:GetBoxVolume(), 0
		vol.Think = function(s)
			if s.Dragging then s:UpdateFromMouse() end
			local v = math.floor(s.Value or 0)
			if v ~= sent and RealTime() - lastSend > 0.35 then
				sent, lastSend = v, RealTime()
				act(ent, "volume", v)
			end
		end
		local row = vgui.Create("EditablePanel", body)
		row:Dock(TOP)
		row:SetTall(UI.S(44))
		row:DockMargin(0, UI.S(10), 0, 0)
		local off = UI.AddButton(row, "Выключить", "volume", function() act(ent, "off") end, { dock = LEFT, style = "ghost", h = 44 })
		off:SetWide((body:GetWide() - UI.S(10)) / 2)
		off:DockMargin(0, 0, UI.S(10), 0)
		UI.AddButton(row, "Забрать", "backpack", function()
			act(ent, "take")
			win:Close()
		end, { dock = FILL, style = "solid", h = 44 })
	end
	personal(body)
	local baseThink = win.Think
	win.Think = function(s)
		if baseThink then baseThink(s) end
		if not s.Closing and (not IsValid(ent) or ent:GetPos():Distance(LocalPlayer():GetPos()) > 240) then s:Close() end
	end
end)
