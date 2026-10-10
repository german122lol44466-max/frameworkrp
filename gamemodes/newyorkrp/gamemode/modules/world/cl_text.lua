--[[
	3D-текст — клиент: принимает надписи с сервера и рисует их в мире (3D2D),
	с плавным затуханием по дистанции и поддержкой нескольких строк. Сзади стены надпись не видна.
]]

NYRP.World = NYRP.World or {}
local W = NYRP.World

W.TextList = W.TextList or {}
local list = W.TextList

local FONT_PX, BASE_SCALE = 96, 0.08

local function readEntry()
	local d = {}
	d.id = net.ReadString()
	d.pos = net.ReadVector()
	d.ang = net.ReadAngle()
	d.text = net.ReadString()
	d.scale = net.ReadFloat()
	d.col = net.ReadColor(false)
	d.lines = string.Explode("\n", d.text)
	return d
end

net.Receive("nyrp.world.text", function()
	local op = net.ReadUInt(2)
	if op == 0 then
		for k in pairs(list) do list[k] = nil end
		for _ = 1, net.ReadUInt(10) do
			local d = readEntry()
			list[d.id] = d
		end
	elseif op == 1 then
		local d = readEntry()
		list[d.id] = d
	elseif op == 2 then
		for _ = 1, net.ReadUInt(10) do list[net.ReadString()] = nil end
	end
end)

hook.Add("InitPostEntity", "nyrp.world.text", function()
	timer.Simple(3, function()
		net.Start("nyrp.world.text")
		net.SendToServer()
	end)
end)

local shadow = Color(0, 0, 0)
local drawCol = Color(255, 255, 255)

hook.Add("PostDrawTranslucentRenderables", "nyrp.world.text", function(depth, sky)
	if depth or sky then return end
	if not next(list) then return end
	local eye = EyePos()
	local maxD = W.Config.TextDrawDist
	local font = NYRP.FontRaw("bold", FONT_PX)
	local lineH = FONT_PX * 1.05
	for _, d in pairs(list) do
		local dist = eye:Distance(d.pos)
		if dist < maxD and (eye - d.pos):Dot(d.ang:Up()) > 0 then
			local a = math.Clamp((maxD - dist) / (maxD * 0.35), 0, 1)
			if a > 0.01 then
				local n = #d.lines
				local y0 = -(n * lineH) / 2
				cam.Start3D2D(d.pos, d.ang, BASE_SCALE * (d.scale or 1))
					shadow.a = 200 * a
					drawCol.r, drawCol.g, drawCol.b, drawCol.a = d.col.r, d.col.g, d.col.b, 255 * a
					for i, line in ipairs(d.lines) do
						local y = y0 + (i - 1) * lineH
						draw.SimpleText(line, font, 3, y + 3, shadow, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
						draw.SimpleText(line, font, 0, y, drawCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
					end
				cam.End3D2D()
			end
		end
	end
end)
