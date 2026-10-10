--[[
	Лотерея (общая часть).
	  «Лотерейный автомат» (энтити nyrp_lottery): E — меню: моментальная лотерея $5 и билет «NY Lotto» $10.
	  Моментальная лотерея — предмет «Скретч-карта»: ПКМ в сумке → «Стереть» — окно, где мышью стирается
	  защитный слой. Под ним 6 символов; три одинаковых — выигрыш ($10…$1000). Результат решает сервер
	  в момент покупки (клиент только показывает), выигрыш зачисляется наличными, когда слой стёрт.
	  «NY Lotto» — розыгрыш джекпота раз в 2 часа реального времени, объявление в чате и в газете.
	Сохранение: data/nyrp/lottery.json (джекпот, билеты, время розыгрыша, невыплаченные выигрыши),
	            автоматы — data/nyrp/lottery_<карта>.json.
	Админ: /lotterymachine — поставить автомат, /lotteryremove — убрать тот, на который смотрите,
	       /lottodraw — провести розыгрыш NY Lotto сейчас.
]]

NYRP.Lottery = NYRP.Lottery or {}
local L = NYRP.Lottery

L.ScratchPrice = 5
L.LottoPrice = 10
L.DrawEvery = 2 * 3600   -- секунды реального времени между розыгрышами NY Lotto
L.BaseJackpot = 500      -- стартовый джекпот
L.JackpotShare = 0.7     -- доля продаж билетов, идущая в джекпот
L.MaxLotto = 20          -- билетов NY Lotto на одного персонажа в розыгрыш

-- Символы скретч-карты. prize > 0 — три таких символа дают выигрыш (шанс chance на билет).
-- Ожидаемая отдача: 10·0.12 + 20·0.05 + 50·0.015 + 100·0.006 + 1000·0.0008 = $4.35 с билета за $5 (< 1).
L.Symbols = {
	{ id = "sun", icon = "sun", name = "Солнце", prize = 10, chance = 0.12, color = Color(255, 196, 60) },
	{ id = "heart", icon = "heart", name = "Сердце", prize = 20, chance = 0.05, color = Color(240, 80, 110) },
	{ id = "bell", icon = "bell", name = "Колокол", prize = 50, chance = 0.015, color = Color(120, 200, 255) },
	{ id = "key", icon = "key", name = "Ключ", prize = 100, chance = 0.006, color = Color(170, 120, 255) },
	{ id = "dollar", icon = "dollar", name = "Доллар", prize = 1000, chance = 0.0008, color = Color(80, 220, 120) },
	-- пустые
	{ id = "moon", icon = "moon", name = "Луна", prize = 0, color = Color(150, 160, 190) },
	{ id = "flame", icon = "flame", name = "Огонь", prize = 0, color = Color(255, 120, 60) },
	{ id = "music", icon = "music", name = "Нота", prize = 0, color = Color(200, 200, 120) },
}
L.SymbolById = {}
for _, s in ipairs(L.Symbols) do L.SymbolById[s.id] = s end

NYRP.Items.Register("scratch_ticket", {
	name = "Скретч-карта «Liberty Luck»",
	desc = "Моментальная лотерея. Сотрите защитный слой: три одинаковых символа — выигрыш до $1000.",
	model = "models/props_c17/paper01.mdl", category = "misc", stack = 1, useText = "Стереть",
	buffs = { { "Выигрыш до $1000", true }, { "Три одинаковых символа", true } },
	icon = { ang = Angle(90, 0, 0), zoom = 0.9 },
	use = function(ply, it)
		if SERVER and L.OpenScratch then L.OpenScratch(ply, it) end
		return false   -- карта тратится только после того, как слой стёрт (см. sv_lottery)
	end,
})

if SERVER then
	util.AddNetworkString("nyrp.lottery.menu")     -- сервер -> клиент: меню автомата
	util.AddNetworkString("nyrp.lottery.buy")      -- клиент -> сервер: купить (scratch | lotto)
	util.AddNetworkString("nyrp.lottery.scratch")  -- сервер -> клиент: открыть окно стирания
	util.AddNetworkString("nyrp.lottery.claim")    -- клиент -> сервер: слой стёрт — забрать выигрыш
end
