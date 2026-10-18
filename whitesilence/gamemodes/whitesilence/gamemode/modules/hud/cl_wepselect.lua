--[[
	Выбор оружия по мотивам плагина «Weapon Select» (Chessnut, Helix): список оружия дугой справа от центра,
	выбранное — цветом Фонда, остальные мельче и прозрачнее по мере удаления; под списком — инструкция оружия.
	Колесо / цифры — листать, ЛКМ — взять. Переписано без зависимостей от Helix.
]]

local WSel = { index = 1, deltaIndex = 1, infoAlpha = 0, alpha = 0, alphaDelta = 0, fadeTime = 0 }
WS.WepSelect = WSel

local matrixScale = Vector(1, 1, 0)
local accent = Color(226, 190, 120)

local fontsReady
local function fonts()
	if fontsReady then return end
	fontsReady = true
	surface.CreateFont("ws.wepsel", { font = "Exo 2", size = math.Round(ScreenScale(16)), weight = 700, extended = true })
	surface.CreateFont("ws.wepsel.bold", { font = "Exo 2", size = math.Round(ScreenScale(7)), weight = 700, extended = true })
	surface.CreateFont("ws.wepsel.desc", { font = "Exo 2", size = math.Round(ScreenScale(6.5)), weight = 400, extended = true })
end
hook.Add("OnScreenSizeChanged", "ws.wepsel", function() fontsReady = nil end)

local function shadowText(text, x, y, col, ax, ay, font)
	draw.SimpleText(text, font, x + 1, y + 2, Color(0, 0, 0, col.a * 0.7), ax, ay)
	draw.SimpleText(text, font, x, y, col, ax, ay)
end

hook.Add("HUDPaint", "ws.wepsel", function()
	local frameTime = FrameTime()
	WSel.alphaDelta = Lerp(frameTime * 10, WSel.alphaDelta, WSel.alpha)
	local fraction = WSel.alphaDelta
	if fraction <= 0.01 then return end
	fonts()

	local x, y = ScrW() * 0.5, ScrH() * 0.5
	local spacing = math.pi * 0.85
	local radius = 240 * fraction
	local shiftX = ScrW() * 0.02
	WSel.deltaIndex = Lerp(frameTime * 12, WSel.deltaIndex, WSel.index)

	local weapons = LocalPlayer():GetWeapons()
	local index = WSel.deltaIndex
	if not weapons[WSel.index] then WSel.index = #weapons end

	for i = 1, #weapons do
		local theta = (i - index) * 0.1
		local base = i == WSel.index and accent or color_white
		local color = Color(base.r, base.g, base.b, math.Clamp((255 - math.abs(theta * 3) * 255) * fraction, 0, 255))
		local lastY = 0

		if WSel.markup and (i < WSel.index or i == 1) then
			if WSel.index ~= 1 then
				local _, h = WSel.markup:Size()
				lastY = h * fraction
			end
			if i == 1 or i == WSel.index - 1 then
				WSel.infoAlpha = Lerp(frameTime * 3, WSel.infoAlpha, 255)
				WSel.markup:Draw(x + 6 + shiftX, y + 30, 0, 0, WSel.infoAlpha * fraction)
			end
		end

		surface.SetFont("ws.wepsel")
		local name = WS.Upper(weapons[i]:GetPrintName())
		local _, ty = surface.GetTextSize(name)
		local scale = 1 - math.abs(theta * 2)

		local matrix = Matrix()
		matrix:Translate(Vector(
			shiftX + x + math.cos(theta * spacing + math.pi) * radius + radius,
			y + lastY + math.sin(theta * spacing + math.pi) * radius - ty / 2,
			1))
		matrix:Scale(matrixScale * scale)
		cam.PushModelMatrix(matrix)
			shadowText(name, 2, ty / 2, color, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, "ws.wepsel")
		cam.PopModelMatrix()
	end

	if WSel.fadeTime < CurTime() and WSel.alpha > 0 then WSel.alpha = 0 end
end)

function WSel.OnIndexChanged(weapon)
	WSel.alpha = 1
	WSel.fadeTime = CurTime() + 5
	WSel.markup = nil
	if not IsValid(weapon) then return end
	fonts()
	local instructions = weapon.Instructions
	if isstring(instructions) and instructions:find("%S") then
		WSel.markup = markup.Parse(string.format("<font=ws.wepsel.bold><color=%d,%d,%d>Инструкция</color></font>\n<font=ws.wepsel.desc>%s</font>\n",
			accent.r, accent.g, accent.b, instructions), ScrW() * 0.3)
		WSel.infoAlpha = 0
	end
	WS.Audio.Play("whitesilence/game/tick.ogg", { volume = 0.5 })
end

hook.Add("PlayerBindPress", "ws.wepsel", function(client, bind, pressed)
	bind = bind:lower()
	if not pressed or (not bind:find("invprev") and not bind:find("invnext") and not bind:find("slot") and not bind:find("attack")) then
		return
	end
	if not WS.Lobby.InGame(client) then return end
	local current = client:GetActiveWeapon()
	local valid = IsValid(current)
	if client:InVehicle() or (valid and current:GetClass() == "weapon_physgun" and client:KeyDown(IN_ATTACK)) then return end
	local tool
	if valid and current:GetClass() == "gmod_tool" then
		local t = client:GetTool()
		tool = t and t.Scroll ~= nil
	end
	local weapons = client:GetWeapons()

	if bind:find("invprev") and not tool then
		local old = WSel.index
		WSel.index = math.min(WSel.index + 1, #weapons)
		if WSel.alpha == 0 or old ~= WSel.index then WSel.OnIndexChanged(weapons[WSel.index]) end
		return true
	elseif bind:find("invnext") and not tool then
		local old = WSel.index
		WSel.index = math.max(WSel.index - 1, 1)
		if WSel.alpha == 0 or old ~= WSel.index then WSel.OnIndexChanged(weapons[WSel.index]) end
		return true
	elseif bind:find("slot") then
		WSel.index = math.Clamp(tonumber(bind:match("slot(%d)")) or 1, 1, math.max(#weapons, 1))
		WSel.OnIndexChanged(weapons[WSel.index])
		return true
	elseif bind:find("attack") and WSel.alpha > 0 then
		local weapon = weapons[WSel.index]
		if IsValid(weapon) then
			WS.Audio.Play("whitesilence/game/select.ogg", { volume = 0.6 })
			input.SelectWeapon(weapon)
			WSel.alpha = 0
		end
		return true
	end
end)

hook.Add("Think", "ws.wepsel", function()
	local client = LocalPlayer()
	if not IsValid(client) or not client:Alive() then WSel.alpha = 0 end
end)

hook.Add("ScoreboardShow", "ws.wepsel", function() WSel.alpha = 0 end)
