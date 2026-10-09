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
N.Voices = {
	{ id = "", name = "Без озвучки" },
	{ id = "maxim", name = "Максим — мужской", provider = "se", voice = "Maxim", rate = 1.0 },
	{ id = "maxim_low", name = "Максим — низкий, басовитый", provider = "se", voice = "Maxim", rate = 0.86 },
	{ id = "maxim_old", name = "Старик", provider = "se", voice = "Maxim", rate = 0.78 },
	{ id = "maxim_fast", name = "Максим — быстрый, нервный", provider = "se", voice = "Maxim", rate = 1.15 },
	{ id = "tatyana", name = "Татьяна — женский", provider = "se", voice = "Tatyana", rate = 1.0 },
	{ id = "tatyana_low", name = "Татьяна — низкий", provider = "se", voice = "Tatyana", rate = 0.9 },
	{ id = "tatyana_young", name = "Девушка — высокий", provider = "se", voice = "Tatyana", rate = 1.14 },
	{ id = "child", name = "Ребёнок", provider = "se", voice = "Tatyana", rate = 1.32 },
	{ id = "google", name = "Диктор (Google)", provider = "google", rate = 1.0 },
	{ id = "google_low", name = "Диктор — низкий (Google)", provider = "google", rate = 0.85 },
	{ id = "robot", name = "Автоответчик", provider = "google", rate = 0.72 },
	{ id = "en_brian", name = "Брайан — английский акцент", provider = "se", voice = "Brian", rate = 1.0 },
	{ id = "en_joanna", name = "Джоанна — английский акцент", provider = "se", voice = "Joanna", rate = 1.0 },
}
N.VoiceById = {}
for _, v in ipairs(N.Voices) do N.VoiceById[v.id] = v end

function N.Sanitize(d)
	if type(d) ~= "table" then return end
	local out = {
		voice = N.VoiceById[d.voice or ""] and d.voice or "",
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
