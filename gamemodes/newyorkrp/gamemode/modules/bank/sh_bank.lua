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

-- Геометрия банкомата (как в tools/models/build_atm.py; лицом в +X).
B.ATM = {
	screenX = 9.56, screenY = 7, screenTop = 52, screenSize = 14,  -- экран: x, y ∈ [-7, 7], z ∈ [38, 52]
	-- камера ввода PIN (под неё сделана анимация рук v_atm): точка и наклон вниз, взгляд в -X
	camPin = { pos = Vector(26.2, 1.5, 44.0), pitch = 25 },
	-- камера меню: весь экран целиком
	camMenu = { pos = Vector(28.6, 0, 46.0), pitch = 3 },
	fov = 62,
}

function B.CamWorld(ent, cam)
	local pos = ent:LocalToWorld(cam.pos)
	local ang = ent:LocalToWorldAngles(Angle(cam.pitch, 180, 0))
	return pos, ang
end
