--[[
	Банки, банковская карта, банкоматы (общая часть).
	Счета персонажа: c.flags.bank[банк] = сумма, история c.flags.bankLog[банк] (общие с банковскими приложениями
	телефона), штрафы c.flags.fines = {{id, amount, reason, day}}.
	Карта (предмет bankcard): data = { bank, number (16 цифр), holder, exp "MM/YY", cvv, pin }.
]]

NYRP.Bank = NYRP.Bank or {}
local B = NYRP.Bank
local Items = NYRP.Items

B.Banks = {
	liberty = { name = "Liberty Bank", short = "LIBERTY", color = Color(32, 92, 200), dark = Color(10, 28, 70), tag = "Банк статуи Свободы" },
	hudson = { name = "Hudson Trust", short = "HUDSON", color = Color(18, 140, 110), dark = Color(6, 46, 38), tag = "Надёжно, как берега Гудзона" },
	empire = { name = "Empire Pay", short = "EMPIRE", color = Color(150, 60, 200), dark = Color(46, 16, 66), tag = "Платежи на высоте Эмпайр-стейт" },
}
B.Order = { "liberty", "hudson", "empire" }
B.ForeignFee = 2          -- комиссия за снятие в банкомате чужого банка
B.StartBalance = 250      -- на счёт новой карты

Items.Register("bankcard", {
	name = "Банковская карта", desc = "Именная дебетовая карта VISA. Нужна для банкомата и оплаты аренды через телефон.",
	model = "models/nyrp/atm/w_bankcard.mdl", category = "document", stack = 1, clientView = true, useText = "Посмотреть",
	buffs = { { "Доступ к счёту в банкомате", true } },
	icon = { ang = Angle(90, 180, 0), zoom = 0.6 },
})

-- «4000 1234 5678 9010»
function B.FormatCard(num)
	num = tostring(num or "")
	return (num:gsub("(%d%d%d%d)", "%1 "):gsub("%s+$", ""))
end

function B.MaskCard(num)
	num = tostring(num or "")
	return "•••• " .. num:sub(-4)
end

-- Геометрия банкомата в игре (модель в 1.5 раза больше чертежа build_atm.py; лицом в +X).
local K = 1.5
B.ATM = {
	K = K,
	-- экран: x = 9.55·K, y ∈ [-7, 7]·K, z ∈ [38, 52]·K; 3D2D чуть впереди поверхности (иначе мерцает)
	screenX = 9.55 * K + 0.12, screenY = 7 * K, screenTop = 52 * K, screenSize = 14 * K,
	-- вывеска: передняя грань x = 7·K, ширина 25·K, верх 72·K
	topperX = 7 * K + 0.15, topperY = 12.5 * K, topperTop = 72 * K,
	-- камера ввода PIN — под неё сделана анимация рук v_atm (tools/models/viewmodel/anims.py, ATM_CAM)
	camPin = { pos = Vector(31.4, 1.5, 60.8), pitch = 27 },
	-- камера меню: весь экран целиком
	camMenu = { pos = Vector(41.5, 0, 67.5), pitch = 0 },
	fov = 62,
	-- клавиатура (чертёж): центр, полуразмеры, наклон к пользователю
	kp = { center = Vector(12, -1.2, 31.6), hx = 2.6, hy = 3.7, tilt = 18 },
}

-- Клавиши на текстуре клавиатуры: имя, центр (fx — слева направо, fy — от дальнего края), размер.
B.Keys = {}
do
	local kw, gap, x0 = 0.19, 0.035, 0.06
	for i, k in ipairs({ "1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#" }) do
		local c, r = (i - 1) % 3, math.floor((i - 1) / 3)
		B.Keys[#B.Keys + 1] = { key = k, fx = x0 + c * (kw + gap) + kw / 2, fy = x0 + r * (kw + gap) + kw / 2, w = kw, h = kw }
	end
	local fx = (x0 + 3 * (kw + gap) + gap + 0.94) / 2
	for j, k in ipairs({ "cancel", "clear", "enter" }) do
		B.Keys[#B.Keys + 1] = { key = k, fx = fx, fy = x0 + (j - 1) * (kw * 1.33 + gap) + kw * 1.33 / 2, w = 0.94 - (x0 + 3 * (kw + gap) + gap), h = kw * 1.33 }
	end
end

local function kpRot(x, y, z, inv)
	local t = math.rad(B.ATM.kp.tilt) * (inv and -1 or 1)
	return x * math.cos(t) + z * math.sin(t), y, -x * math.sin(t) + z * math.cos(t)
end

-- точка клавиатуры по долям текстуры -> локальные координаты банкомата (игровые)
function B.KeypadPoint(fx, fy, h)
	local kp = B.ATM.kp
	local x, y, z = kpRot((fy * 2 - 1) * kp.hx, (fx * 2 - 1) * kp.hy, 0.15 + (h or 0))
	return (kp.center + Vector(x, y, z)) * K
end

function B.KeypadNormal()
	local x, y, z = kpRot(0, 0, 1)
	return Vector(x, y, z)
end

-- локальная точка банкомата (игровая) -> доли текстуры клавиатуры
function B.KeypadUV(localPos)
	local kp = B.ATM.kp
	local d = localPos / K - kp.center
	local x, y = kpRot(d.x, d.y, d.z, true)
	return (y / kp.hy + 1) / 2, (x / kp.hx + 1) / 2
end

function B.KeyAt(fx, fy)
	for i, k in ipairs(B.Keys) do
		if math.abs(fx - k.fx) <= k.w / 2 and math.abs(fy - k.fy) <= k.h / 2 then return k, i end
	end
end

function B.CamWorld(ent, cam)
	local pos = ent:LocalToWorld(cam.pos)
	local ang = ent:LocalToWorldAngles(Angle(cam.pitch, 180, 0))
	return pos, ang
end
