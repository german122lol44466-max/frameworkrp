--[[
	Интро: сценарий. Здесь — тексты, тайминги кадров и звуковые метки (секунды от начала).
	Логика отрисовки — cl_intro.lua, эффекты (снег, туман, зерно) — cl_fx.lua.

	Ход интро:
	  0.0  Арктика в метели, отряд МОГ «Дельта-14» вдалеке; через секунду — текст.
	 12.2  Ближе к отряду. «Но что-то в них было уже не так...» — в очках бойцов загорается бледный отблеск.
	 19.8  Погибший боец: кровь на перчатке и снегу, рация в снегу, «Купол» вызывает отряд.
	 30.9  Салон вертолёта: группа летит на задание.
	 43.0  Знак Фонда.
]]

local I = WS.Intro

I.Path = "whitesilence/intro/"
I.Length = 51.0

-- Кадры: начало, конец, проявление, затемнение (секунды)
I.Shots = {
	{ id = "arctic", from = 0.0, to = 11.8, fadeIn = 2.6, fadeOut = 1.2 },
	{ id = "closeup", from = 12.2, to = 19.4, fadeIn = 1.4, fadeOut = 1.2 },
	{ id = "dead", from = 19.8, to = 30.5, fadeIn = 1.6, fadeOut = 1.2 },
	{ id = "heli", from = 30.9, to = 42.5, fadeIn = 1.5, fadeOut = 1.2 },
	{ id = "banner", from = 43.0, to = 50.6, fadeIn = 0.25, fadeOut = 1.4 },
}

--[[
	Титры (заглавные пишите сразу заглавными: string.upper не понимает кириллицу). style: caps — разрядка Oswald, story — крупный курсив, line — обычный, brand/motto — под знаком.
	y — доля высоты экрана (верх блока), shade — тёмная подложка под текстом.
]]
I.Texts = {
	{ at = 1.2, to = 10.0, style = "caps", y = 0.165, text = "АРКТИКА. МЕТЕЛЬ." },
	{ at = 2.3, to = 10.0, style = "story", y = 0.215, text = "МОГ «Дельта-14» была на задании по сдерживанию аномального объекта." },

	{ at = 13.2, to = 17.9, style = "story", y = 0.18, text = "Но что-то в них было уже не так..." },

	{ at = 21.4, to = 29.0, style = "story", y = 0.165, shade = true, text = "Они все — были мертвы." },
	{ at = 23.3, to = 29.0, style = "line", y = 0.235, text = "Их сигнал пропал ещё неделю назад." },

	{ at = 32.4, to = 41.0, style = "story", y = 0.16, shade = true, text = "Ты — сотрудник спецподразделения." },
	{ at = 34.3, to = 41.0, style = "line", y = 0.225, text = "Твоя задача — нейтрализовать данных существ, которые притворяются отрядом." },

	{ at = 44.1, to = 49.3, style = "brand", y = 0.655, text = "ФОНД SCP" },
	{ at = 45.2, to = 49.3, style = "motto", y = 0.745, text = "ОБЕЗОПАСИТЬ. УДЕРЖАТЬ. СОХРАНИТЬ." },
}

--[[
	Звуки: play — файл из sound/whitesilence/intro (без .ogg), id — имя для fade/stop.
	vol — громкость, fade — нарастание; fade = <id> + vol + time — сменить громкость; stop = <id> + time.
]]
I.Cues = {
	{ at = 0.0, play = "blizzard", id = "wind", vol = 0.8, fade = 3.0, loop = true },
	{ at = 10.6, play = "fade_boom", vol = 0.85 },
	{ at = 11.4, play = "dread", vol = 0.8 },
	{ at = 13.0, play = "heartbeat", id = "heart", vol = 0.5, fade = 2.5 },
	{ at = 16.3, play = "fade_riser", vol = 0.55 },
	{ at = 18.6, stop = "heart", time = 1.2 },
	{ at = 19.3, play = "fade_boom", vol = 0.7 },
	{ at = 19.6, fade = "wind", vol = 0.32, time = 2.5 },
	{ at = 20.2, play = "radio", vol = 0.9 },
	{ at = 28.6, play = "heli_interior", id = "heli", vol = 0.9, fade = 3.5, loop = true },
	{ at = 29.0, stop = "wind", time = 2.5 },
	{ at = 41.3, stop = "heli", time = 2.2 },
	{ at = 42.7, play = "banner_hit", vol = 1.0 },
}

-- Когда горит лампочка рации (идёт передача): от/до, секунды интро
I.RadioTx = { { 20.8, 23.9 }, { 24.6, 28.1 }, { 28.8, 31.0 } }

-- Координаты в кадрах (пиксели исходника 2560x1440)
I.ImageW, I.ImageH = 2560, 1440
I.RadioLed = { 0.7872 * 2560, 0.4012 * 1440 }
I.HeliDoor = { 1400, 250, 2330, 1150 }
I.HeliLamp = { 420, 118 }
