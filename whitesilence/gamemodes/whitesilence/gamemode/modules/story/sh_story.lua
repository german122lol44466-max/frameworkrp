--[[
	Сюжет «Белая тишина»: 7 глав, ≈30–40 минут.

	Здесь только данные: реплики, точки карты и сценарий. Логика — sv_story.lua, экран — cl_story.lua,
	расстановка точек — scp_edit (sv_editor.lua / cl_editor.lua).

	Реплики озвучены нейросетью (tools/content/story_audio.py читает этот файл): одна реплика — одна строка
	вида  id = { who = "...", text = "..." },
]]

local S = WS.Story or {}
WS.Story = S

S.Speakers = {
	hq = { name = "Ледник", color = Color(150, 196, 236) },
	pilot = { name = "Борт-7", color = Color(226, 190, 120) },
	delta = { name = "Дельта-14", color = Color(214, 92, 84) },
}

S.Lines = {
	-- I. Высадка
	c1_a = { who = "hq", text = "Буран, это Ледник. Вас высадили в шести километрах от последней точки сигнала «Дельта-14»." },
	c1_b = { who = "hq", text = "Видимость плохая. Держитесь вместе. Огонь — только по подтверждённой цели." },
	c1_c = { who = "pilot", text = "Борт-7 уходит на базу. Связь через ретранслятор, если он ещё жив. Удачи, Буран." },
	c1_d = { who = "hq", text = "Вы на месте. Ищите следы группы. Любые." },
	-- II. Следы
	c2_a = { who = "hq", text = "Жетон… Сержант Орлов. Время смерти — не меньше недели назад." },
	c2_b = { who = "delta", text = "Ледник, это Дельта-14. Мы на позиции. Потерь нет." },
	c2_c = { who = "hq", text = "Это… невозможно. Буран, это не наш вызов. Будьте начеку." },
	c2_d = { who = "hq", text = "Третий. Все из «Дельты». Тогда кто выходит в эфир с их частоты?" },
	c2_e = { who = "delta", text = "Мы вас видим. Свои. Не стреляйте." },
	c2_f = { who = "hq", text = "Буран, доложите! … Понял. Они носят снаряжение «Дельты». Это не люди." },
	-- III. Ретранслятор
	c3_a = { who = "hq", text = "Нам нужна связь. В двух километрах — ретранслятор. Запустите его." },
	c3_b = { who = "hq", text = "Идёт синхронизация. Держите позицию, пока канал не станет стабильным." },
	c3_c = { who = "delta", text = "Буран… зачем вы пришли? Здесь тихо. Здесь хорошо." },
	c3_d = { who = "hq", text = "Канал есть. Слушайте: «Дельта-14» вышла на связь десять минут назад. С ваших координат." },
	-- IV. Лагерь
	c4_a = { who = "hq", text = "Их базовый лагерь к северу. Если там остались записи — они нужны нам." },
	c4_b = { who = "hq", text = "Лагерь занят. Зачистите его. Осторожно — они не чувствуют боли." },
	c4_c = { who = "hq", text = "Журнал командира: «День четвёртый. Орлов вернулся из метели. Он не помнит своего имени»." },
	c4_d = { who = "hq", text = "На карте отмечен объект семь. Бункер за перевалом. Туда они и шли." },
	-- V. Перевал
	c5_a = { who = "hq", text = "Пройдите перевал. Метель усиливается — сокращайте дистанцию." },
	c5_b = { who = "delta", text = "Мы ждали вас. Мы всегда ждём." },
	c5_c = { who = "hq", text = "Вход в бункер обесточен. Запустите генератор." },
	c5_d = { who = "hq", text = "Гермодверь открывается. Две минуты. Не подпускайте их." },
	c5_e = { who = "hq", text = "Дверь открыта. Входите." },
	-- VI. Источник
	c6_a = { who = "hq", text = "То, что внутри, — источник. Он копирует погибших. Заложите заряды и уходите." },
	c6_b = { who = "delta", text = "Останьтесь. Станьте нами." },
	c6_c = { who = "hq", text = "Заряды на месте. Отходите на безопасное расстояние." },
	c6_d = { who = "hq", text = "Взрыв зафиксирован. Сигнал «Дельта-14»… пропал. Хорошая работа, Буран." },
	-- VII. Эвакуация
	c7_a = { who = "pilot", text = "Буран, это Борт-7. Иду к вам. Обозначьте площадку." },
	c7_b = { who = "pilot", text = "Вижу вас на радаре. Три минуты. Держитесь!" },
	c7_c = { who = "delta", text = "Ледник, это Буран. Мы на позиции. Потерь нет." },
	c7_d = { who = "pilot", text = "Площадка чистая, сажусь! Все на борт!" },
}

-- Время реплик (с) — генерирует tools/content/story_audio.py в sh_story_len.lua; иначе оценка по длине текста
S.LineLength = S.LineLength or {}

function S.LineTime(id)
	if S.LineLength[id] then return S.LineLength[id] end
	local l = S.Lines[id]
	return l and (1.2 + utf8.len(l.text) * 0.065) or 0
end

--[[
	Точки карты. Расставляются в scp_edit; нерасставленные — подбираются автоматически
	(near — от какой точки, dist — на каком расстоянии; по навмешу, если он есть).
	prop — что ставится на точке: "body" — тело бойца, иначе модель.
]]
S.Points = {
	{ id = "spawn", name = "Высадка отряда", kind = "spawn" },
	{ id = "crash", name = "Последний сигнал «Дельта-14»", near = "spawn", dist = { 1800, 3000 }, r = 320 },
	{ id = "body1", name = "Тело 1", near = "crash", dist = { 120, 420 }, prop = "body" },
	{ id = "body2", name = "Тело 2", near = "crash", dist = { 200, 520 }, prop = "body" },
	{ id = "body3", name = "Тело 3", near = "crash", dist = { 260, 620 }, prop = "body" },
	{ id = "cp_relay", name = "Чекпоинт: ретранслятор", kind = "spawn", near = "crash", dist = { 0, 150 } },
	{ id = "relay", name = "Ретранслятор", near = "crash", dist = { 1800, 3000 }, r = 450, prop = "models/props_lab/reciever_cart.mdl" },
	{ id = "cp_camp", name = "Чекпоинт: лагерь", kind = "spawn", near = "relay", dist = { 100, 250 } },
	{ id = "camp", name = "Лагерь «Дельты»", near = "relay", dist = { 1800, 2800 }, r = 500 },
	{ id = "log", name = "Журнал командира", near = "camp", dist = { 120, 380 }, prop = "models/props_lab/clipboard.mdl" },
	{ id = "map", name = "Карта", near = "camp", dist = { 120, 380 }, prop = "models/props_lab/binderredlabel.mdl" },
	{ id = "cp_pass", name = "Чекпоинт: перевал", kind = "spawn", near = "camp", dist = { 0, 200 } },
	{ id = "pass", name = "Перевал", near = "camp", dist = { 2000, 3000 }, r = 400 },
	{ id = "bunker", name = "Вход в бункер", near = "pass", dist = { 1500, 2500 }, r = 350 },
	{ id = "generator", name = "Генератор", near = "bunker", dist = { 200, 500 }, r = 500, prop = "models/props_vehicles/generatortrailer01.mdl" },
	{ id = "cp_core", name = "Чекпоинт: источник", kind = "spawn", near = "bunker", dist = { 0, 150 } },
	{ id = "core", name = "Источник", near = "bunker", dist = { 600, 1200 }, r = 300, prop = "models/props_combine/combine_interface001.mdl" },
	{ id = "charge1", name = "Заряд 1", near = "core", dist = { 90, 200 } },
	{ id = "charge2", name = "Заряд 2", near = "core", dist = { 90, 200 } },
	{ id = "charge3", name = "Заряд 3", near = "core", dist = { 90, 200 } },
	{ id = "detonate", name = "Безопасное расстояние", near = "core", dist = { 1200, 1800 }, r = 300 },
	{ id = "cp_lz", name = "Чекпоинт: эвакуация", kind = "spawn", near = "detonate", dist = { 0, 150 } },
	{ id = "lz", name = "Площадка эвакуации", near = "detonate", dist = { 1500, 2500 }, r = 550 },
}
S.PointById = {}
for i, p in ipairs(S.Points) do p.index = i S.PointById[p.id] = p end

-- Группы врагов: у каждой — свои точки появления (сколько угодно); нет точек — появляются вокруг цели
S.Groups = {
	{ id = "ambush", name = "Засада у тел", near = "crash" },
	{ id = "relay", name = "Волны у ретранслятора", near = "relay" },
	{ id = "camp", name = "Охрана лагеря", near = "camp" },
	{ id = "pass", name = "Патруль перевала", near = "pass" },
	{ id = "bunker_out", name = "Патруль у бункера", near = "bunker" },
	{ id = "bunker", name = "Волны у генератора", near = "generator" },
	{ id = "core", name = "Стража источника", near = "core" },
	{ id = "lz", name = "Волны на эвакуации", near = "lz" },
}
S.GroupById = {}
for _, g in ipairs(S.Groups) do S.GroupById[g.id] = g end

--[[
	Сценарий. Шаги:
	  say      — реплики, ждём окончания
	  goto     — дойти до точки (point, radius); near = { dist, lines } — реплики на подходе
	  interact — удерживать E на каждой из points; lines[point] — реплики после
	  kill     — уничтожить всех, кто появился в шаге (spawn)
	  hold     — удерживать зону time секунд, волны врагов waves; mid[доля] — реплики по ходу
	  explode  — подрыв в точке
	  finish   — конец операции
	У любого шага: text (задача), marker (вид метки), lines (в начале), done (в конце), spawn (враги в начале).
]]
S.Chapters = {
	{ id = "landing", title = "Высадка", spawn = "spawn", steps = {
		{ type = "say", lines = { "c1_a", "c1_b", "c1_c" } },
		{ type = "goto", point = "crash", text = "Дойти до последней точки сигнала «Дельта-14»", marker = "goto", done = { "c1_d" } },
	} },
	{ id = "traces", title = "Следы", spawn = "crash", steps = {
		{ type = "interact", points = { "body1", "body2", "body3" }, text = "Осмотреть тела", label = "Осмотреть", marker = "search",
			lines = {}, after = { body1 = { "c2_a" }, body2 = { "c2_b", "c2_c" }, body3 = { "c2_d" } } },
		{ type = "kill", text = "Отразить нападение", lines = { "c2_e" }, spawn = { { group = "ambush", count = 5, mode = "assault" } },
			done = { "c2_f" } },
	} },
	{ id = "relay", title = "Ретранслятор", spawn = "cp_relay", steps = {
		{ type = "say", lines = { "c3_a" } },
		{ type = "goto", point = "relay", text = "Добраться до ретранслятора", marker = "radio",
			spawn = { { group = "relay", count = 2, mode = "guard" } } },
		{ type = "interact", points = { "relay" }, use = 4, text = "Запустить ретранслятор", label = "Запустить", marker = "radio" },
		{ type = "hold", point = "relay", time = 150, text = "Удерживать ретранслятор", marker = "defend", lines = { "c3_b" },
			waves = { group = "relay", every = 32, count = 3, first = 6 }, mid = { [0.5] = { "c3_c" } }, done = { "c3_d" } },
	} },
	{ id = "camp", title = "Лагерь", spawn = "cp_camp", steps = {
		{ type = "goto", point = "camp", text = "Найти лагерь «Дельты»", marker = "goto", lines = { "c4_a" },
			spawn = { { group = "camp", count = 6, mode = "guard" } }, near = { dist = 1400, lines = { "c4_b" } } },
		{ type = "kill", text = "Зачистить лагерь" },
		{ type = "interact", points = { "log", "map" }, text = "Найти журнал и карту", label = "Забрать", marker = "intel",
			after = { log = { "c4_c" }, map = { "c4_d" } } },
	} },
	{ id = "pass", title = "Перевал", spawn = "cp_pass", steps = {
		{ type = "goto", point = "pass", text = "Пройти перевал", marker = "goto", lines = { "c5_a" },
			spawn = { { group = "pass", count = 5, mode = "patrol" } }, near = { dist = 1000, lines = { "c5_b" } } },
		{ type = "goto", point = "bunker", text = "Найти вход в бункер", marker = "door",
			spawn = { { group = "bunker_out", count = 4, mode = "patrol" } }, done = { "c5_c" } },
		{ type = "interact", points = { "generator" }, use = 4, text = "Запустить генератор", label = "Запустить", marker = "power" },
		{ type = "hold", point = "generator", time = 120, text = "Удерживать генератор, пока открывается дверь", marker = "defend",
			lines = { "c5_d" }, waves = { group = "bunker", every = 28, count = 3, first = 4 }, done = { "c5_e" } },
	} },
	{ id = "core", title = "Источник", spawn = "cp_core", steps = {
		{ type = "goto", point = "core", text = "Найти источник", marker = "enemy", lines = { "c6_a" },
			spawn = { { group = "core", count = 5, mode = "guard" } }, near = { dist = 900, lines = { "c6_b" } } },
		{ type = "interact", points = { "charge1", "charge2", "charge3" }, use = 3, text = "Заложить заряды", label = "Заложить",
			marker = "charge", plant = "models/weapons/w_slam.mdl", done = { "c6_c" } },
		{ type = "goto", point = "detonate", text = "Отойти на безопасное расстояние", marker = "goto" },
		{ type = "explode", point = "core", done = { "c6_d" } },
	} },
	{ id = "lz", title = "Эвакуация", spawn = "cp_lz", steps = {
		{ type = "goto", point = "lz", text = "Выйти к площадке эвакуации", marker = "extract", lines = { "c7_a" } },
		{ type = "hold", point = "lz", time = 180, text = "Удерживать площадку до прибытия вертолёта", marker = "extract",
			lines = { "c7_b" }, waves = { group = "lz", every = 25, count = 4, first = 5 }, mid = { [0.6] = { "c7_c" } },
			done = { "c7_d" } },
		{ type = "finish" },
	} },
}

S.Roman = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }

-- Финальные титры
S.EndingText = {
	"Источник уничтожен. Сигнал {«Дельта-14»} больше не выходил в эфир.",
	"Отряд «Буран» вернулся на базу в полном составе.",
	"Через шесть дней на частоте Ледника прозвучал новый вызов:",
	"{«Ледник, это Буран. Мы на позиции. Потерь нет.»}",
}
