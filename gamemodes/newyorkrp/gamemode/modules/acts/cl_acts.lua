--[[
	Позы на клиенте: корпус развёрнут как при входе в позу (голова следит за взглядом),
	подсказка «Пробел или движение — выйти», окно /acts со всеми позами (клик — принять, ещё клик — выйти).
	Консоль: nyrp_acts — открыть окно (можно забиндить: bind <клавиша> nyrp_acts).
]]

local A = NYRP.Acts
local UI = NYRP.UI

hook.Add("PrePlayerDraw", "nyrp.acts", function(ply)
	if not A.Current(ply) or (NYRP.Sit and NYRP.Sit.Sitting(ply)) then return end
	local yaw = ply:GetNW2Float("nyrp.actYaw", ply:EyeAngles().y)
	ply.nyrpActOldAng = ply:GetRenderAngles()
	ply:SetRenderAngles(Angle(0, yaw, 0))
	-- голова поворачивается за взглядом в разумных пределах, корпус — нет
	local diff = math.NormalizeAngle(ply:EyeAngles().y - yaw)
	ply:SetPoseParameter("aim_yaw", 0)
	ply:SetPoseParameter("aim_pitch", 0)
	ply:SetPoseParameter("head_yaw", math.Clamp(diff, -60, 60))
	ply:SetPoseParameter("head_pitch", math.Clamp(ply:EyeAngles().p, -30, 30))
	ply:InvalidateBoneCache()
	ply.nyrpActDrawn = true
end)

hook.Add("PostPlayerDraw", "nyrp.acts", function(ply)
	if not ply.nyrpActDrawn then return end
	ply.nyrpActDrawn = nil
	-- у игрока SetRenderAngles без аргумента нельзя — возвращаем прежний угол
	if ply.nyrpActOldAng then ply:SetRenderAngles(ply.nyrpActOldAng) end
	ply.nyrpActOldAng = nil
end)

hook.Add("HUDPaint", "nyrp.acts", function()
	local ply = LocalPlayer()
	if not IsValid(ply) or not ply:Alive() or NYRP.HUDHidden() then return end
	local a = A.Current(ply)
	if not a then return end
	local text = "Поза: " .. string.gsub(a.name, "_", " ") .. "  ·  Пробел или движение — выйти"
	local font = NYRP.Font("semibold", 15)
	local w = UI.TextSize(text, font) + UI.S(28)
	local y = ScrH() - UI.S(210)
	UI.RoundedRect(UI.S(10), ScrW() / 2 - w / 2, y, w, UI.S(32), Color(10, 12, 20, 200))
	draw.SimpleText(text, font, ScrW() / 2, y + UI.S(16), color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)

-- ------------------------------------------------------------- окно поз --
local function send(i)
	net.Start("nyrp.acts.do")
	net.WriteUInt(i, 8)
	net.SendToServer()
end

function A.OpenMenu()
	if IsValid(A.Win) then A.Win:Close() end
	local win, body = UI.Window("Позы", "user", 640, 560, { sub = "/act <поза>" })
	A.Win = win
	local grid = vgui.Create("NYRP.Scroll", body)
	grid:Dock(FILL)
	local layout = vgui.Create("DIconLayout", grid)
	layout:Dock(TOP)
	layout:SetSpaceX(UI.S(8))
	layout:SetSpaceY(UI.S(8))
	local cw = math.floor((body:GetWide() - UI.S(8) * 2 - UI.S(8)) / 3)
	for _, a in ipairs(A.List) do
		local b = layout:Add("DButton")
		b:SetText("")
		b:SetSize(cw, UI.S(96))
		b.Hover = 0
		b.Paint = function(s, w, h)
			local cur = A.Current(LocalPlayer()) == a
			s.Hover = UI.Approach(s.Hover, s:IsHovered() and 1 or 0, 12)
			UI.RoundedRect(UI.S(10), 0, 0, w, h, cur and UI.Alpha(UI.Col.accent, 40) or Color(255, 255, 255, 8 + 10 * s.Hover))
			UI.Outline(UI.S(10), 0, 0, w, h, cur and UI.Col.accent or Color(255, 255, 255, 14 + 30 * s.Hover), 1)
			UI.DrawIcon(a.icon or "user", w / 2, UI.S(28), UI.S(26) * (1 + 0.1 * s.Hover), cur and UI.Col.accent or UI.LerpColor(s.Hover, UI.Col.dim, UI.Col.accent))
			local nm = string.gsub(a.name, "_", " ")
			draw.SimpleText(nm, NYRP.Font("semibold", 14), w / 2, UI.S(56), UI.Col.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			draw.SimpleText(cur and "нажмите — выйти" or (a.wall == "back" and "спиной к стене" or a.desc), NYRP.Font("regular", 11), w / 2, UI.S(76), UI.Col.faint, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			return true
		end
		b.OnCursorEntered = function() UI.Sound("hover") end
		b.DoClick = function()
			UI.Sound("click")
			if A.Current(LocalPlayer()) == a then send(0) else send(a.index) end
			win:Close()
		end
	end
	UI.AddButton(body, "Выйти из позы", "close", function() send(0) win:Close() end, { dock = BOTTOM, h = 40 })
end

net.Receive("nyrp.acts.menu", function() A.OpenMenu() end)
concommand.Add("nyrp_acts", function() A.OpenMenu() end)
