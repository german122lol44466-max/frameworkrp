--[[
	3D-панели — клиент. Картинка скачивается через http.Fetch, только когда панель рядом,
	проверяется (PNG/JPG, до 6 МБ), кэшируется в data/nyrp/panels/<crc>.png|jpg и рисуется 3D2D.
	nyrp_panels 0 — не загружать картинки из интернета.
]]

NYRP.World = NYRP.World or {}
local W = NYRP.World

W.PanelList = W.PanelList or {}
local list = W.PanelList
local images = {} -- url -> { state = "loading"|"ok"|"fail", mat = IMaterial }

local cvEnabled = CreateClientConVar("nyrp_panels", "1", true, false, "Показывать 3D-панели с картинками из интернета")
local MAX_BYTES = 6 * 1024 * 1024
local SCALE = 0.1

local function readEntry()
	local d = {}
	d.id = net.ReadString()
	d.pos = net.ReadVector()
	d.ang = net.ReadAngle()
	d.url = net.ReadString()
	d.w = net.ReadUInt(11)
	d.h = net.ReadUInt(11)
	return d
end

net.Receive("nyrp.world.panel", function()
	local op = net.ReadUInt(2)
	if op == 0 then
		for k in pairs(list) do list[k] = nil end
		for _ = 1, net.ReadUInt(8) do
			local d = readEntry()
			list[d.id] = d
		end
	elseif op == 1 then
		local d = readEntry()
		list[d.id] = d
	elseif op == 2 then
		for _ = 1, net.ReadUInt(8) do list[net.ReadString()] = nil end
	end
end)

hook.Add("InitPostEntity", "nyrp.world.panel", function()
	timer.Simple(3.5, function()
		net.Start("nyrp.world.panel")
		net.SendToServer()
	end)
end)

local function useFile(img, name)
	local mat = Material("../data/nyrp/panels/" .. name, "smooth mips")
	if not mat or mat:IsError() then
		img.state = "fail"
		return
	end
	img.mat, img.state = mat, "ok"
end

local function load(url)
	local img = { state = "loading" }
	images[url] = img
	local crc = util.CRC(url)
	for _, ext in ipairs({ ".png", ".jpg" }) do
		if file.Exists("nyrp/panels/" .. crc .. ext, "DATA") then
			useFile(img, crc .. ext)
			return
		end
	end
	http.Fetch(url, function(body, size, _, code)
		if (code and code ~= 200) or not body or #body == 0 or #body > MAX_BYTES then img.state = "fail" return end
		local ext
		if string.sub(body, 1, 4) == "\137PNG" then ext = ".png"
		elseif string.sub(body, 1, 2) == "\255\216" then ext = ".jpg" end
		if not ext then img.state = "fail" return end
		file.CreateDir("nyrp")
		file.CreateDir("nyrp/panels")
		file.Write("nyrp/panels/" .. crc .. ext, body)
		useFile(img, crc .. ext)
	end, function()
		img.state = "fail"
	end)
end

hook.Add("PostDrawTranslucentRenderables", "nyrp.world.panel", function(depth, sky)
	if depth or sky or not next(list) or not cvEnabled:GetBool() then return end
	local eye = EyePos()
	local maxD = W.Config.PanelDrawDist
	local admin = LocalPlayer():IsAdmin()
	for _, d in pairs(list) do
		local dist = eye:Distance(d.pos)
		if dist < maxD and (eye - d.pos):Dot(d.ang:Up()) > 0 then
			local img = images[d.url]
			if not img then load(d.url) img = images[d.url] end
			local a = math.Clamp((maxD - dist) / (maxD * 0.3), 0, 1)
			local pw, ph = d.w / SCALE, d.h / SCALE
			cam.Start3D2D(d.pos, d.ang, SCALE)
				if img.state == "ok" then
					surface.SetDrawColor(255, 255, 255, 255 * a)
					surface.SetMaterial(img.mat)
					surface.DrawTexturedRect(-pw / 2, -ph / 2, pw, ph)
				elseif img.state == "loading" then
					surface.SetDrawColor(10, 12, 20, 180 * a)
					surface.DrawRect(-pw / 2, -ph / 2, pw, ph)
					draw.SimpleText("Загрузка изображения...", NYRP.FontRaw("medium", 40), 0, 0, Color(220, 222, 230, 200 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				elseif admin then
					surface.SetDrawColor(60, 14, 18, 160 * a)
					surface.DrawRect(-pw / 2, -ph / 2, pw, ph)
					draw.SimpleText("Не удалось загрузить картинку", NYRP.FontRaw("medium", 40), 0, 0, Color(255, 160, 160, 220 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
			cam.End3D2D()
		end
	end
end)
