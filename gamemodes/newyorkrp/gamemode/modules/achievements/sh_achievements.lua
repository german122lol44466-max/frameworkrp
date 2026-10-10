--[[
	Достижения: 25 целей с прогрессом и денежной наградой. Прогресс — c.flags.ach = { done = {[id] = время}, p = {[счётчик] = n} }.
	Открытие — всплывающее уведомление с иконкой и звуком, награда наличными.
	Окно «Достижения»: /achievements (/достижения) или меню памяти (H) → «Воспоминания» → «Достижения».
	Счётчики берутся из существующих механик (хуки и обёртки функций в рантайме, без правки чужих файлов).
]]

NYRP.Ach = NYRP.Ach or {}
local A = NYRP.Ach

-- stat — какой счётчик, goal — сколько нужно; reward — $ наличными
A.List = {
	{ id = "first_pay", name = "Первая зарплата", desc = "Выполните первое рабочее задание", icon = "cash", stat = "jobs", goal = 1, reward = 50 },
	{ id = "worker", name = "Трудяга", desc = "Выполните 10 рабочих заданий", icon = "briefcase", stat = "jobs", goal = 10, reward = 150 },
	{ id = "workaholic", name = "Трудоголик", desc = "Выполните 50 рабочих заданий", icon = "briefcase2", stat = "jobs", goal = 50, reward = 500 },
	{ id = "cash_1k", name = "Тысяча в кармане", desc = "Держите $1 000 наличными", icon = "dollar", stat = "cash", goal = 1000, reward = 100 },
	{ id = "cash_10k", name = "Толстый кошелёк", desc = "Держите $10 000 наличными", icon = "coins", stat = "cash", goal = 10000, reward = 500 },
	{ id = "bank_25k", name = "Солидный счёт", desc = "Накопите $25 000 на банковских счетах", icon = "bank", stat = "bank", goal = 25000, reward = 750 },
	{ id = "fire_1", name = "Укротитель огня", desc = "Потушите пожар", icon = "flame", stat = "fires", goal = 1, reward = 100 },
	{ id = "fire_10", name = "Герой FDNY", desc = "Потушите 10 очагов", icon = "flame2", stat = "fires", goal = 10, reward = 400 },
	{ id = "heal_1", name = "Добрый самаритянин", desc = "Помогите человеку без сознания или верните к жизни", icon = "medkit", stat = "heals", goal = 1, reward = 100 },
	{ id = "heal_10", name = "Ангел-хранитель", desc = "Окажите помощь 10 раз", icon = "heart", stat = "heals", goal = 10, reward = 400 },
	{ id = "arrest_1", name = "Закон есть закон", desc = "Арестуйте нарушителя", icon = "badge", stat = "arrests", goal = 1, reward = 100 },
	{ id = "arrest_10", name = "Гроза улиц", desc = "Проведите 10 арестов", icon = "shield", stat = "arrests", goal = 10, reward = 400 },
	{ id = "jailed", name = "За решёткой", desc = "Окажитесь в КПЗ", icon = "lock", stat = "jailed", goal = 1, reward = 25 },
	{ id = "sit", name = "В ногах правды нет", desc = "Сядьте на стул или скамейку", icon = "user", stat = "sit", goal = 1, reward = 20 },
	{ id = "stock_1", name = "Первая сделка", desc = "Купите акции на NY Stock Exchange", icon = "coins", stat = "trades", goal = 1, reward = 50 },
	{ id = "stock_wolf", name = "Волк с Уолл-стрит", desc = "Заработайте $1 000 чистой прибыли на бирже", icon = "dollar", stat = "stockProfit", goal = 1000, reward = 300 },
	{ id = "scratch_win", name = "Счастливчик", desc = "Выиграйте по скретч-карте", icon = "sun", stat = "scratchWins", goal = 1, reward = 25 },
	{ id = "scratch_20", name = "Азартный", desc = "Сотрите 20 скретч-карт", icon = "certificate", stat = "scratches", goal = 20, reward = 50 },
	{ id = "jackpot", name = "Джекпот!", desc = "Сорвите джекпот NY Lotto", icon = "coins", stat = "lotto", goal = 1, reward = 100 },
	{ id = "drinks", name = "Душа компании", desc = "Выпейте 10 порций алкоголя", icon = "bottle", stat = "drinks", goal = 10, reward = 30 },
	{ id = "explorer", name = "Исследователь", desc = "Откройте 5 районов города", icon = "map_pin", stat = "zones", goal = 5, reward = 100 },
	{ id = "clean", name = "Чистый город", desc = "Выбросите в урну 20 вещей", icon = "trash", stat = "trash", goal = 20, reward = 80 },
	{ id = "talker", name = "Болтун", desc = "Скажите 100 реплик в IC-чате", icon = "message", stat = "talk", goal = 100, reward = 30 },
	{ id = "skill_5", name = "Мастер своего дела", desc = "Поднимите любой навык до 5 уровня", icon = "target", stat = "skill", goal = 5, reward = 250 },
	{ id = "collector", name = "Коллекционер", desc = "Получите 10 достижений", icon = "certificate", stat = "achs", goal = 10, reward = 500 },
}
A.ById = {}
for i, a in ipairs(A.List) do a.idx = i A.ById[a.id] = a end

if SERVER then
	util.AddNetworkString("nyrp.ach.unlock")  -- сервер -> клиент: открыто достижение (id)
	util.AddNetworkString("nyrp.ach.data")    -- сервер -> клиент: прогресс (и открыть окно)
	util.AddNetworkString("nyrp.ach.req")     -- клиент -> сервер: запросить прогресс
end
