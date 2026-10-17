--[[
	Развлечения для всех горожан (общая часть):
	  Блэкджек — стол nyrp_blackjack: E — сесть (до 4 игроков, у каждого своя игра против дилера),
	    ставка $5–$500 наличными, «Ещё / Хватит / Удвоить», дилер добирает до 17, блэкджек платит 3:2.
	  Аркада — автомат nyrp_arcade: E — «Змейка» или «Реакция» за $1. Денег не выигрывают — только рекорды
	    (топ-10 каждой игры, data/nyrp/arcade.json), лучший результат — на экране над автоматом.
	  Бумбокс — предмет «Бумбокс»: ПКМ «Поставить». Владелец по E выбирает интернет-радио, громкость,
	    выключает или забирает бумбокс. Звук объёмный, слышно вокруг. У каждого — своя громкость
	    (nyrp_boombox_volume) и выключатель чужих бумбоксов (nyrp_boombox_mute).
	Все исходы (карты, оплата, рекорды) решает сервер, клиент только показывает.
	Админ: /blackjack, /blackjackremove, /arcade, /arcaderemove (или спавн-меню) — столы и автоматы
	       сохраняются для карты: data/nyrp/leisure_<карта>.json.
]]

NYRP.Leisure = NYRP.Leisure or {}
local LS = NYRP.Leisure

if SERVER then
	util.AddNetworkString("nyrp.bj.state")   -- сервер -> клиент: состояние раздачи (и открыть окно)
	util.AddNetworkString("nyrp.bj.close")   -- сервер -> клиент: вы встали из-за стола
	util.AddNetworkString("nyrp.bj.act")     -- клиент -> сервер: bet | hit | stand | double | leave
	util.AddNetworkString("nyrp.arc.open")   -- сервер -> клиент: меню автомата и рекорды
	util.AddNetworkString("nyrp.arc.start")  -- клиент -> сервер: заплатить $1 и начать игру
	util.AddNetworkString("nyrp.arc.go")     -- сервер -> клиент: игра оплачена (параметры)
	util.AddNetworkString("nyrp.arc.finish") -- клиент -> сервер: результат игры
	util.AddNetworkString("nyrp.arc.result") -- сервер -> клиент: итог, место в таблице, рекорды
	util.AddNetworkString("nyrp.bb.open")    -- сервер -> клиент: меню бумбокса
	util.AddNetworkString("nyrp.bb.act")     -- клиент -> сервер: station | volume | off | take
end

-- ------------------------------------------------------------- блэкджек --
LS.BJ = LS.BJ or {}
local BJ = LS.BJ
BJ.MinBet = 5
BJ.MaxBet = 500
BJ.Seats = 4
BJ.Decks = 4          -- колод в «башмаке» (новый башмак на каждую раздачу)
BJ.Range = 200        -- дальше от стола — встали (незавершённая ставка сгорает)

BJ.Ranks = { "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A" }
BJ.SuitNames = { "пик", "червей", "бубен", "треф" }
BJ.SuitRed = { false, true, true, false }

-- карта 1..52 -> ранг 1..13 (2..A), масть 1..4
function BJ.Parts(n)
	n = math.Clamp(math.floor(tonumber(n) or 1), 1, 52) - 1
	return n % 13 + 1, math.floor(n / 13) + 1
end

-- сумма очков руки (0 — скрытая карта, не считается); второе значение — «мягкая» (туз за 11)
function BJ.Value(cards)
	local total, aces = 0, 0
	for _, c in ipairs(cards or {}) do
		if c and c > 0 then
			local r = BJ.Parts(c)
			if r == 13 then
				aces = aces + 1
				total = total + 11
			elseif r >= 9 then
				total = total + 10
			else
				total = total + r + 1
			end
		end
	end
	while total > 21 and aces > 0 do
		total = total - 10
		aces = aces - 1
	end
	return total, aces > 0
end

function BJ.IsBlackjack(cards)
	return #cards == 2 and BJ.Value(cards) == 21
end

-- ----------------------------------------------------------------- аркада --
LS.Arcade = LS.Arcade or {}
local AR = LS.Arcade
AR.Price = 1
AR.Top = 10
AR.Games = {
	snake = { name = "Змейка", icon = "p_game", desc = "Стрелки или WASD. Ешьте яблоки, не врезайтесь в стены и в себя.", higher = true, unit = "яблок" },
	reaction = { name = "Реакция", icon = "bolt", desc = "5 попыток: жмите ЛКМ или ПРОБЕЛ, как только экран станет зелёным.", higher = false, unit = "мс" },
}
AR.Order = { "snake", "reaction" }
AR.ReactRounds = 5
AR.SnakeW, AR.SnakeH = 24, 16

function AR.Format(game, score)
	score = math.floor(tonumber(score) or 0)
	if game == "reaction" then return score .. " мс" end
	return score .. " " .. (AR.Games.snake.unit)
end

-- ----------------------------------------------------------------- бумбокс --
LS.Boombox = LS.Boombox or {}
local BB = LS.Boombox
BB.Range = 1400       -- дальше — не слышно (поток не качается)
BB.FarOwner = 1500    -- владелец дальше этого 5 минут — бумбокс возвращается к нему
BB.FarTime = 300
-- станции: несколько адресов — если первый не открылся, клиент пробует следующий
BB.Stations = {
	{ name = "Lo-Fi Chill", genre = "lo-fi, chillhop", color = Color(170, 130, 255), urls = {
		"https://streams.ilovemusic.de/iloveradio17.mp3",
		"https://ice1.somafm.com/fluid-128-mp3",
	} },
	{ name = "Smooth Jazz", genre = "джаз", color = Color(255, 176, 80), urls = {
		"https://jazz-wr04.ice.infomaniak.ch/jazz-wr04-128.mp3",
		"https://ice1.somafm.com/sonicuniverse-128-mp3",
	} },
	{ name = "Rock Radio", genre = "рок", color = Color(230, 70, 60), urls = {
		"https://stream.rockantenne.de/rockantenne/stream/mp3",
		"https://stream.radioparadise.com/rock-128",
	} },
	{ name = "Pop Hits", genre = "поп, хиты", color = Color(255, 110, 180), urls = {
		"https://streams.ilovemusic.de/iloveradio1.mp3",
		"https://stream.radioparadise.com/mp3-128",
	} },
	{ name = "Hip-Hop", genre = "хип-хоп, R&B", color = Color(90, 200, 120), urls = {
		"https://streams.ilovemusic.de/iloveradio3.mp3",
		"https://ice1.somafm.com/fluid-128-mp3",
	} },
	{ name = "Classic FM", genre = "классика", color = Color(110, 170, 240), urls = {
		"https://stream.srg-ssr.ch/m/rsc_de/mp3_128",
		"https://stream.radioparadise.com/mellow-128",
	} },
}

-- ------------------------------------------------------- достижения (если модуль есть) --
LS.AchList = {
	{ id = "bj_natural", name = "Двадцать одно", desc = "Соберите блэкджек с двух карт", icon = "coins", stat = "bjNatural", goal = 1, reward = 25 },
	{ id = "arcade_snake", name = "Удав", desc = "Наберите 20 яблок в «Змейке» на аркаде", icon = "p_game", stat = "arcadeSnake", goal = 20, reward = 20 },
	{ id = "arcade_reflex", name = "Молниеносный", desc = "Средняя реакция на аркаде — 250 мс или быстрее", icon = "bolt", stat = "arcadeReflex", goal = 1, reward = 20 },
}

function LS.RegisterAchievements()
	local A = NYRP.Ach
	if not A or not istable(A.List) or not istable(A.ById) then return end
	for _, a in ipairs(LS.AchList) do
		if not A.ById[a.id] then
			A.List[#A.List + 1] = a
			a.idx = #A.List
			A.ById[a.id] = a
		end
	end
end
LS.RegisterAchievements()
hook.Add("Initialize", "nyrp.leisure.ach", function() LS.RegisterAchievements() end)
