--[[
	Иммерсивная камера:
	- от первого лица камера стоит в глазах модели и видно всё тело (голова скрыта только у себя);
	  ходьба/бег/прыжки дают естественное покачивание, приземление — «присед» камеры;
	- третье лицо с настройками и затемнением экрана при переключении;
	- модули могут перехватить вид через hook "NYRP.CalcView" (меню, смерть, сумка).
]]

local UI = NYRP.UI
NYRP.Camera = NYRP.Camera or {}
local Cam = NYRP.Camera

local smoothOffset
local landKick, landVel = 0, 0
local roll = 0
local headHidden = false
local eyeLocal = {}   -- [model] = {pos, ang} смещение глаз относительно головы

local function headBone(ply)
	return ply:LookupBone("ValveBiped.Bip01_Head1")
end

function Cam.IsThirdPerson()
	return GetConVar("nyrp_thirdperson"):GetBool()
end

-- Тело от первого лица видно всегда (без настройки).
function Cam.BodyEnabled()
	return true
end

-- Головокружение (ранение, сотрясение): медленное «плавание» взгляда, сила — Cam.Dizzy (0..1).
function Cam.DizzyAngle()
	local t, d = RealTime(), Cam.Dizzy or 0
	return Angle(math.sin(t * 0.73) * 1.8 * d + math.sin(t * 1.9) * 0.4 * d, math.sin(t * 0.51) * 1.4 * d,
		math.sin(t * 0.87 + 1) * 3.2 * d)
end

local function setHeadHidden(ply, hidden)
	local bone = headBone(ply)
	if not bone then return end
	ply:ManipulateBoneScale(bone, hidden and Vector(0.001, 0.001, 0.001) or Vector(1, 1, 1))
	headHidden = hidden
end

-- Смещение глаз от кости головы считаем один раз на модель при нормальном масштабе головы.
local function eyeOffset(ply)
	local mdl = ply:GetModel()
	if eyeLocal[mdl] then return eyeLocal[mdl] end
	local bone = headBone(ply)
	local att = ply:LookupAttachment("eyes")
	if not bone or att <= 0 then return nil end
	local wasHidden = headHidden
	if wasHidden then setHeadHidden(ply, false) end
	ply:SetupBones()
	local hp, ha = ply:GetBonePosition(bone)
	local a = ply:GetAttachment(att)
	if wasHidden then setHeadHidden(ply, true) end
	if not hp or not a then return nil end
	local lp, la = WorldToLocal(a.Pos, a.Ang, hp, ha)
	eyeLocal[mdl] = { lp, la }
	return eyeLocal[mdl]
end

function Cam.EyePos(ply)
	local bone = headBone(ply)
	local off = eyeOffset(ply)
	if not bone or not off then return ply:EyePos() end
	local hp, ha = ply:GetBonePosition(bone)
	if not hp then return ply:EyePos() end
	return (LocalToWorld(off[1], off[2], hp, ha))
end

local function bodyView(ply, origin, angles, fov)
	-- Основа — точка обзора движка (присед, прыжок, лестницы — без задержек).
	-- Сверху — покачивание головы из анимации: ограничено, сглажено и гаснет,
	-- когда смотрим сильно вниз/вверх (там анимация прицеливания дёргает голову).
	local base = ply:EyePos()
	local off = Cam.EyePos(ply) - base
	local len = off:Length()
	if len > 32 then off = off * (32 / len) end
	-- камера всегда идёт за головой (с оружием поза наклоняет корпус вперёд — раньше камера
	-- оставалась позади шеи); дрожание позы прицеливания гасим сильнее сглаживанием
	local wep = ply:GetActiveWeapon()
	local armed = IsValid(wep) and wep:GetClass() ~= "nyrp_hands"
	local rate = (armed and angles.p > 40) and 14 or 30
	smoothOffset = smoothOffset and LerpVector(1 - math.exp(-rate * FrameTime()), smoothOffset, off) or off

	-- камеру чуть вперёд по горизонтали, сильнее при взгляде вниз — чтобы не видеть грудь изнутри
	local flat = Angle(0, angles.y, 0):Forward()
	local pos = base + smoothOffset + flat * (2 + math.max(angles.p, 0) / 89 * 5)

	-- не заглядываем сквозь стены
	local tr = util.TraceHull({ start = base, endpos = pos, mins = Vector(-2, -2, -2), maxs = Vector(2, 2, 2), filter = ply, mask = MASK_SOLID })
	pos = tr.HitPos

	-- приземление
	landVel = landVel + (-landKick * 60 - landVel * 12) * FrameTime()
	landKick = landKick + landVel * FrameTime()
	landKick = UI.Approach(landKick, 0, 6)
	pos.z = pos.z - landKick * 6

	-- лёгкий крен при стрейфе
	local side = ply:GetVelocity():Dot(angles:Right())
	roll = UI.Approach(roll, math.Clamp(side / 220, -1, 1) * 1.6, 6)

	local ang = Angle(angles.p, angles.y, angles.r + roll)
	if Cam.ExtraAngle then ang = ang + Cam.ExtraAngle end
	if (Cam.Dizzy or 0) > 0 then ang = ang + Cam.DizzyAngle() end
	if Cam.LookBlend and Cam.LookBlend > 0 then
		ang.p = Lerp(Cam.LookBlend, ang.p, Cam.LookPitch or 60)
		ang.y = ang.y + (Cam.LookYaw or 0) * Cam.LookBlend
	end
	return { origin = pos, angles = ang, fov = fov, znear = 1.2, drawviewer = true }
end

-- Третье лицо
local tpPos
local function thirdView(ply, origin, angles, fov)
	local dist = GetConVar("nyrp_tp_dist"):GetFloat()
	local right = GetConVar("nyrp_tp_right"):GetFloat()
	local up = GetConVar("nyrp_tp_up"):GetFloat()
	local smooth = GetConVar("nyrp_tp_smooth"):GetFloat()
	local start = ply:EyePos()
	local target = start - angles:Forward() * dist + angles:Right() * right + angles:Up() * up
	local tr = util.TraceHull({ start = start, endpos = target, mins = Vector(-5, -5, -5), maxs = Vector(5, 5, 5), filter = ply, mask = MASK_SOLID })
	local want = tr.HitPos - ply:GetPos()
	tpPos = tpPos and LerpVector(1 - math.exp(-smooth * FrameTime()), tpPos, want) or want
	local ang = Angle(angles.p, angles.y, angles.r)
	if Cam.ExtraAngle then ang = ang + Cam.ExtraAngle end
	if (Cam.Dizzy or 0) > 0 then ang = ang + Cam.DizzyAngle() end
	return { origin = ply:GetPos() + tpPos, angles = ang, fov = fov, drawviewer = true }
end

hook.Add("OnPlayerHitGround", "nyrp.camera", function(ply, inWater, onFloater, speed)
	if ply ~= LocalPlayer() or not IsFirstTimePredicted() then return end
	landVel = landVel + math.Clamp((speed - 150) / 500, 0, 1) * 18
end)

function GM:CalcView(ply, origin, angles, fov, znear, zfar)
	local custom = hook.Run("NYRP.CalcView", ply, origin, angles, fov)
	if custom then return custom end

	if not ply:Alive() or ply:InVehicle() or ply:GetViewEntity() ~= ply then
		return self.BaseClass.CalcView(self, ply, origin, angles, fov, znear, zfar)
	end
	local wep = ply:GetActiveWeapon()
	if IsValid(wep) and wep:GetClass() == "gmod_camera" then
		return self.BaseClass.CalcView(self, ply, origin, angles, fov, znear, zfar)
	end

	if Cam.IsThirdPerson() then
		smoothOffset = nil
		return thirdView(ply, origin, angles, fov)
	end
	tpPos = nil
	if Cam.BodyEnabled() then
		return bodyView(ply, origin, angles, fov)
	end
	return self.BaseClass.CalcView(self, ply, origin, angles, fov, znear, zfar)
end

function GM:ShouldDrawLocalPlayer(ply)
	if hook.Run("NYRP.ShouldDrawLocalPlayer", ply) == false then return false end
	if not ply:Alive() or ply:InVehicle() then return end
	return Cam.IsThirdPerson() or Cam.BodyEnabled()
end

-- Голова скрыта только когда мы смотрим из своих глаз.
hook.Add("Think", "nyrp.camera.head", function()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local want = ply:Alive() and Cam.BodyEnabled() and not Cam.IsThirdPerson() and NYRP.State == "playing"
		and not hook.Run("NYRP.ShowHead")
	if ply.nyrpHeadModel ~= ply:GetModel() then
		ply.nyrpHeadModel = ply:GetModel()
		headHidden = not want
	end
	if want ~= headHidden then setHeadHidden(ply, want) end
end)

-- Вьюмодель рук не рисуем (руки видно у тела).
function GM:PreDrawViewModel(vm, ply, wep)
	if IsValid(wep) and wep:GetClass() == "nyrp_hands" then return true end
	return self.BaseClass.PreDrawViewModel and self.BaseClass.PreDrawViewModel(self, vm, ply, wep)
end

-- Переключение третьего лица с затемнением.
function Cam.ToggleThirdPerson()
	if Cam.Switching then return end
	Cam.Switching = true
	UI.Fade(0.12, 0.06, 0.16, function()
		RunConsoleCommand("nyrp_thirdperson", Cam.IsThirdPerson() and "0" or "1")
		timer.Simple(0.05, function() Cam.Switching = false end)
	end)
end
concommand.Add("nyrp_toggle_thirdperson", Cam.ToggleThirdPerson)

-- Меню настройки третьего лица.
function Cam.OpenMenu()
	if IsValid(Cam.Menu) then Cam.Menu:Remove() return end
	local f = vgui.Create("DPanel")
	Cam.Menu = f
	f:SetSize(UI.S(380), UI.S(390))
	f:SetPos(UI.S(30), ScrH() / 2 - UI.S(195))
	f:MakePopup()
	f:SetKeyboardInputEnabled(false)
	f.Born = RealTime()
	f.Paint = function(s, w, h)
		local t = UI.Ease((RealTime() - s.Born) / 0.25)
		s:SetAlpha(255 * t)
		UI.RoundedBlurPanel(s, UI.S(14), 5)
		UI.RoundedRect(UI.S(14), 0, 0, w, h, Color(12, 14, 22, 228))
		UI.Outline(UI.S(14), 0, 0, w, h, UI.Col.stroke, 1)
		UI.DrawIcon("camera", UI.S(34), UI.S(36), UI.S(22), UI.Col.accent)
		draw.SimpleText("ТРЕТЬЕ ЛИЦО", NYRP.Font("title", 24), UI.S(54), UI.S(36), UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	local close = vgui.Create("NYRP.IconButton", f)
	close:SetSize(UI.S(30), UI.S(30))
	close:SetPos(f:GetWide() - UI.S(44), UI.S(21))
	close.DoClick = function() f:Remove() end

	local body = vgui.Create("DPanel", f)
	body:SetPos(UI.S(22), UI.S(70))
	body:SetSize(f:GetWide() - UI.S(44), f:GetTall() - UI.S(86))
	body.Paint = function() end
	local tog = vgui.Create("NYRP.Toggle", body)
	tog:Dock(TOP)
	tog:SetLabel("Включено")
	tog:SetChecked(Cam.IsThirdPerson())
	tog.OnChange = function(s, on)
		if on ~= Cam.IsThirdPerson() then Cam.ToggleThirdPerson() end
	end
	for _, def in ipairs({
		{ "nyrp_tp_dist", "Дистанция", 30, 160, 0 },
		{ "nyrp_tp_right", "Смещение вправо", -40, 40, 0 },
		{ "nyrp_tp_up", "Высота", -20, 30, 0 },
		{ "nyrp_tp_smooth", "Плавность", 2, 30, 0 },
	}) do
		local s = vgui.Create("NYRP.Slider", body)
		s:Dock(TOP)
		s:DockMargin(0, UI.S(6), 0, 0)
		s:SetLabel(def[2])
		s:SetMinMax(def[3], def[4])
		s:SetDecimals(def[5])
		s:SetConVar(def[1])
	end
end
concommand.Add("nyrp_thirdperson_menu", Cam.OpenMenu)
