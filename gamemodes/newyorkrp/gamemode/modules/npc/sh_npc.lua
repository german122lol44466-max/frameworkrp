--[[
	NPC: торговец и собеседник. Настраиваются админом через C-меню (ПКМ по NPC → «Настроить NPC»):
	имя, описание, модель, анимация (sequence), диалог (реплики и ответы), товары (за деньги или
	в обмен на предметы), задания (принести предмет / дойти до точки, награда, реплики).
	Сохраняются на карте: data/nyrp/npcs/<карта>.json.

	Данные NPC:
	{ id, kind = "trader"|"talk", name, desc, model, seq,
	  dialog = { start = "start", nodes = { [id] = { text, options = { { text, act, arg } } } } },
	     act: "goto" (arg = id реплики) | "trade" | "quest" (arg = id задания) | "turnin" (arg = id задания) | "close"
	  trade = { { item, n, money, costItem, costN } },
	  quests = { [id] = { name, desc, type = "bring"|"reach", item, n, point = {x,y,z}, radius,
	                      reward = { money, item, n }, accept, done, repeatable } } }
]]

NYRP.NPC = NYRP.NPC or {}
local N = NYRP.NPC

N.Kinds = { trader = "Торговец", talk = "Собеседник" }
N.Acts = {
	{ "goto", "Перейти к реплике" }, { "trade", "Открыть торговлю" }, { "quest", "Дать задание" },
	{ "turnin", "Сдать задание" }, { "close", "Закончить разговор" },
}

function N.Default(kind)
	local trader = kind == "trader"
	return {
		kind = trader and "trader" or "talk",
		name = trader and "Тони «Лавка»" or "Старик Фрэнк",
		desc = trader and "Хозяин угловой лавки, знает цену всему." or "Сидит здесь с утра, видел всё, что творится в квартале.",
		model = trader and "models/player/group01/male_07.mdl" or "models/player/group01/male_02.mdl",
		seq = "idle_all_01",
		dialog = {
			start = "start",
			nodes = {
				start = {
					text = trader and "Заходи, не стесняйся. Чего желаешь?" or "А, это ты... Чего надо?",
					options = trader and {
						{ text = "Покажи, что есть.", act = "trade" },
						{ text = "Ничего, просто смотрю.", act = "close" },
					} or {
						{ text = "Как жизнь в квартале?", act = "goto", arg = "news" },
						{ text = "Бывай.", act = "close" },
					},
				},
				news = { text = "Тихо, пока копы не приезжают. Держи ухо востро.", options = { { text = "Понял.", act = "goto", arg = "start" } } },
			},
		},
		trade = trader and {
			{ item = "water", n = 1, money = 5 },
			{ item = "soda", n = 1, money = 4 },
			{ item = "takeout", n = 1, money = 12 },
		} or {},
		quests = {},
	}
end

function N.QuestKey(npcId, qid) return npcId .. "/" .. qid end

local function str(v, max) return NYRP.CleanText(tostring(v or ""), max) end
local function num(v, lo, hi, def) return math.Clamp(math.floor(tonumber(v) or def or lo), lo, hi) end
local function id(v) return string.sub(string.gsub(tostring(v or ""), "[^%w_%-]", ""), 1, 32) end

-- Очистка данных от клиента-редактора (сервер).
-- Голоса озвучки реплик (TTS через интернет у клиента). rate меняет высоту/темп голоса.
-- Голоса озвучки. Разные «движки» — это разные дикторы, а не один голос с другой интонацией:
--   polly  — Amazon Polly через ttsmp3.com: Максим (муж.), Татьяна (жен.);
--   ispeech — iSpeech: свои мужской и женский голос;
--   yandex — голос Яндекс.Переводчика;
--   google — диктор Google (ru и дикторы соседних языков, читающие кириллицу — с акцентом);
--   piper  — нейросетевые голоса Piper на своём сервере (Денис, Дмитрий, Ирина, Руслан):
--            tools/tts/piper_server.py, адрес — серверная переменная nyrp_tts_server.
-- Если сервис не ответил, реплика всё равно прозвучит голосом Google (с той же высотой).
N.Voices = {
	{ id = "", name = "Без озвучки" },
	-- Amazon Polly
	{ id = "maxim", name = "Максим — мужской", engine = "polly", voice = "Maxim", rate = 1.0, group = "Polly" },
	{ id = "maxim_low", name = "Максим — бас", engine = "polly", voice = "Maxim", rate = 0.86, group = "Polly" },
	{ id = "maxim_old", name = "Максим — старик", engine = "polly", voice = "Maxim", rate = 0.76, group = "Polly" },
	{ id = "maxim_fast", name = "Максим — нервный", engine = "polly", voice = "Maxim", rate = 1.16, group = "Polly" },
	{ id = "tatyana", name = "Татьяна — женский", engine = "polly", voice = "Tatyana", rate = 1.0, group = "Polly" },
	{ id = "tatyana_low", name = "Татьяна — женщина постарше", engine = "polly", voice = "Tatyana", rate = 0.9, group = "Polly" },
	{ id = "tatyana_young", name = "Татьяна — девушка", engine = "polly", voice = "Tatyana", rate = 1.12, group = "Polly" },
	-- iSpeech
	{ id = "isp_m", name = "Виктор — мужской (iSpeech)", engine = "ispeech", voice = "rurussianmale", rate = 1.0, group = "iSpeech" },
	{ id = "isp_m_low", name = "Виктор — хриплый бас (iSpeech)", engine = "ispeech", voice = "rurussianmale", rate = 0.84, group = "iSpeech" },
	{ id = "isp_f", name = "Ольга — женский (iSpeech)", engine = "ispeech", voice = "rurussianfemale", rate = 1.0, group = "iSpeech" },
	-- Яндекс
	{ id = "yandex", name = "Яндекс — диктор", engine = "yandex", rate = 1.0, group = "Яндекс" },
	{ id = "yandex_low", name = "Яндекс — низкий", engine = "yandex", rate = 0.85, group = "Яндекс" },
	-- Google
	{ id = "google", name = "Google — дикторша", engine = "google", lang = "ru", rate = 1.0, group = "Google" },
	{ id = "child", name = "Google — ребёнок", engine = "google", lang = "ru", rate = 1.3, group = "Google" },
	{ id = "robot", name = "Google — автоответчик", engine = "google", lang = "ru", rate = 0.66, group = "Google" },
	{ id = "uk", name = "Украинский акцент", engine = "google", lang = "uk", rate = 1.0, group = "Акценты" },
	{ id = "bg", name = "Болгарский акцент", engine = "google", lang = "bg", rate = 1.0, group = "Акценты" },
	{ id = "sr", name = "Сербский акцент", engine = "google", lang = "sr", rate = 0.92, group = "Акценты" },
	{ id = "mk", name = "Македонский акцент", engine = "google", lang = "mk", rate = 1.0, group = "Акценты" },
	-- Piper (свой сервер)
	{ id = "piper_denis", name = "Денис — нейросеть (Piper)", engine = "piper", voice = "ru_RU-denis-medium", rate = 1.0, group = "Piper" },
	{ id = "piper_dmitri", name = "Дмитрий — нейросеть (Piper)", engine = "piper", voice = "ru_RU-dmitri-medium", rate = 1.0, group = "Piper" },
	{ id = "piper_ruslan", name = "Руслан — нейросеть (Piper)", engine = "piper", voice = "ru_RU-ruslan-medium", rate = 1.0, group = "Piper" },
	{ id = "piper_irina", name = "Ирина — нейросеть (Piper)", engine = "piper", voice = "ru_RU-irina-medium", rate = 1.0, group = "Piper" },
	{ id = "piper_old", name = "Дмитрий — старик (Piper)", engine = "piper", voice = "ru_RU-dmitri-medium", rate = 0.82, group = "Piper" },
}
-- старые id голосов из прошлых версий
N.VoiceAlias = { google_low = "maxim_low", en_brian = "maxim", en_joanna = "tatyana", uk_low = "uk" }
-- адрес своего TTS-сервера Piper (видят клиенты): nyrp_tts_server "http://1.2.3.4:5002"
CreateConVar("nyrp_tts_server", "", { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Адрес TTS-сервера Piper для голосов NPC")
N.VoiceById = {}
for _, v in ipairs(N.Voices) do N.VoiceById[v.id] = v end

function N.Sanitize(d)
	if type(d) ~= "table" then return end
	local out = {
		voice = N.VoiceById[N.VoiceAlias[d.voice or ""] or d.voice or ""] and (N.VoiceAlias[d.voice or ""] or d.voice) or "",
		kind = N.Kinds[d.kind] and d.kind or "talk",
		name = str(d.name, 48), desc = str(d.desc, 200),
		model = str(d.model, 128), seq = str(d.seq, 64),
		dialog = { start = id(d.dialog and d.dialog.start) ~= "" and id(d.dialog.start) or "start", nodes = {} },
		trade = {}, quests = {},
	}
	if out.name == "" then out.name = "Незнакомец" end
	if not string.match(out.model, "^models/.+%.mdl$") then out.model = "models/player/group01/male_07.mdl" end
	local acts = {}
	for _, a in ipairs(N.Acts) do acts[a[1]] = true end
	local nNodes = 0
	for rawId, node in pairs(d.dialog and d.dialog.nodes or {}) do
		local nid = id(rawId)
		if nid ~= "" and type(node) == "table" and nNodes < 64 then
			nNodes = nNodes + 1
			local nd = { text = str(node.text, 500), options = {} }
			for i, o in ipairs(node.options or {}) do
				if i > 8 then break end
				if type(o) == "table" and acts[o.act] then
					nd.options[#nd.options + 1] = { text = str(o.text, 120), act = o.act, arg = o.arg and id(o.arg) or nil }
				end
			end
			out.dialog.nodes[nid] = nd
		end
	end
	if not out.dialog.nodes[out.dialog.start] then
		out.dialog.nodes[out.dialog.start] = { text = "...", options = { { text = "Пока.", act = "close" } } }
	end
	for i, t in ipairs(d.trade or {}) do
		if i > 40 then break end
		if type(t) == "table" and NYRP.Items.Get(t.item or "") then
			local o = { item = t.item, n = num(t.n, 1, 50, 1), money = num(t.money, 0, 1000000, 0) }
			if t.costItem and NYRP.Items.Get(t.costItem) then o.costItem = t.costItem o.costN = num(t.costN, 1, 50, 1) end
			out.trade[#out.trade + 1] = o
		end
	end
	local nQ = 0
	for rawQ, q in pairs(d.quests or {}) do
		local qid = id(rawQ)
		if qid ~= "" and type(q) == "table" and nQ < 16 then
			nQ = nQ + 1
			local o = {
				name = str(q.name, 60), desc = str(q.desc, 300), type = q.type == "reach" and "reach" or "bring",
				accept = str(q.accept, 400), done = str(q.done, 400), repeatable = q.repeatable == true,
				reward = { money = num(q.reward and q.reward.money, 0, 1000000, 0) },
			}
			if o.type == "bring" then
				o.item = NYRP.Items.Get(q.item or "") and q.item or "water"
				o.n = num(q.n, 1, 50, 1)
			else
				local p = q.point or {}
				o.point = { x = tonumber(p.x) or 0, y = tonumber(p.y) or 0, z = tonumber(p.z) or 0 }
				o.radius = num(q.radius, 32, 2000, 150)
			end
			if q.reward and NYRP.Items.Get(q.reward.item or "") then
				o.reward.item = q.reward.item
				o.reward.n = num(q.reward.n, 1, 50, 1)
			end
			out.quests[qid] = o
		end
	end
	return out
end
