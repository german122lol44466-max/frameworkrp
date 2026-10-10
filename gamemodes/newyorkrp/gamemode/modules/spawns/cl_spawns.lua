--[[
	Маркеры точек появления у админа (/spawns): силуэт-коробка размером с игрока, стрелка взгляда
	и подпись с ролью (цвет роли; общие — жёлтые). Сами скрываются через 10 минут.
]]

NYRP.Spawns = NYRP.Spawns or {}
local S = NYRP.Spawns

S.Markers = S.Markers or {}
local hideAt = 0

local MINS, MAXS = Vector(-16, -16, 0), Vector(16, 16, 72)
local colAll = Color(247, 198, 0)

local function roleInfo(id)
	if id == "*" then return "Общая точка", colAll end
	local r = NYRP.Roles and NYRP.Roles.List and NYRP.Roles.List[id]
	return r and r.Name or id, r and r.Color or Color(200, 200, 200)
end

net.Receive("nyrp.spawns.show", function()
	local show = net.ReadBool()
	S.Markers = {}
	if not show then return end
	for i = 1, net.ReadUInt(10) do
		local role, pos, yaw = net.ReadString(), net.ReadVector(), net.ReadFloat()
		local name, col = roleInfo(role)
		S.Markers[i] = { pos = pos, yaw = yaw, name = name, col = col }
	end
	hideAt = CurTime() + 600
end)

hook.Add("PostDrawTranslucentRenderables", "nyrp.spawns", function(depth, sky)
	if depth or sky or #S.Markers == 0 then return end
	if CurTime() > hideAt then S.Markers = {} return end
	local eye = EyePos()
	local font = NYRP.FontRaw("bold", 48)
	local small = NYRP.FontRaw("medium", 30)
	for i, m in ipairs(S.Markers) do
		if eye:DistToSqr(m.pos) < 3000 * 3000 then
			local ang = Angle(0, m.yaw, 0)
			render.DrawWireframeBox(m.pos, ang, MINS, MAXS, m.col, true)
			local head = m.pos + Vector(0, 0, 60)
			render.DrawLine(head, head + ang:Forward() * 28, m.col, true)
			local lab = m.pos + Vector(0, 0, 82)
			local face = (eye - lab):Angle()
			local a = Angle(0, face.y + 90, 90)
			cam.Start3D2D(lab, a, 0.12)
				draw.SimpleText(m.name, font, 0, 0, m.col, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
				draw.SimpleText("#" .. i, small, 0, 4, Color(230, 232, 240), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
			cam.End3D2D()
		end
	end
end)

hook.Add("HUDPaint", "nyrp.spawns", function()
	if #S.Markers == 0 then return end
	local UI = NYRP.UI
	local text = "Точки появления: " .. #S.Markers .. " · /spawnadd [роль], /spawnremove [радиус], скрыть — /spawns"
	local f = NYRP.Font("medium", 14)
	local w = UI.TextSize(text, f) + UI.S(52)
	local x, y, h = ScrW() / 2 - w / 2, UI.S(18), UI.S(36)
	UI.RoundedRect(UI.S(10), x, y, w, h, Color(10, 12, 20, 215))
	UI.DrawIcon("map_pin", x + UI.S(22), y + h / 2, UI.S(18), colAll)
	draw.SimpleText(text, f, x + UI.S(40), y + h / 2, Color(235, 237, 242), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end)
