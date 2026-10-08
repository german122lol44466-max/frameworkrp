--[[
	Общие функции персонажей: генерация случайных персонажей, проверка данных создания.
]]

NYRP.Chars = NYRP.Chars or {}
local Chars = NYRP.Chars

Chars.FirstNames = {
	male = { "Джеймс", "Майкл", "Тони", "Фрэнк", "Джо", "Дэнни", "Винни", "Маркус", "Луис", "Эдди", "Рэй", "Ник", "Сэм", "Карлос", "Питер" },
	female = { "Мэри", "Линда", "Джессика", "Анджела", "Тереза", "Нина", "Роза", "Кэти", "Моника", "Сара", "Лиза", "Дженни", "Эмили", "Ванесса" },
}
Chars.LastNames = { "Ковальски", "Морелли", "О'Брайен", "Гарсия", "Миллер", "Розенберг", "Сантос", "Келли", "Руссо",
	"Джонсон", "Уильямс", "Мартинес", "Лоренцо", "Шапиро", "Мёрфи", "Новак", "Риччи", "Коэн" }
Chars.Descriptions = {
	"Невысокий человек в потёртой куртке, взгляд усталый, но внимательный.",
	"Аккуратно одет, пахнет дешёвым одеколоном и кофе из ближайшей закусочной.",
	"На руках следы машинного масла, говорит с бруклинским акцентом.",
	"Держится уверенно, будто знает каждый переулок Манхэттена.",
	"Тихий, постоянно поглядывает на часы и на прохожих.",
	"Улыбчивый, в кармане вечно торчит смятая газета.",
	"Немного сутулится, на шее старый шрам, голос хриплый.",
	"Приехал в город недавно и ещё не привык к шуму Нью-Йорка.",
}

function Chars.RandomData()
	local gender = math.random() < 0.6 and "male" or "female"
	local models = NYRP.Config.Models[gender]
	local skills, left = {}, NYRP.Config.SkillPoints
	for _, s in ipairs(NYRP.Config.Skills) do skills[s.id] = 0 end
	while left > 0 do
		local s = NYRP.Config.Skills[math.random(#NYRP.Config.Skills)].id
		if skills[s] < NYRP.Config.SkillMax then skills[s] = skills[s] + 1 left = left - 1 end
	end
	return {
		name = table.Random(Chars.FirstNames[gender]) .. " " .. table.Random(Chars.LastNames),
		description = table.Random(Chars.Descriptions),
		gender = gender,
		model = models[math.random(#models)],
		height = math.random(gender == "male" and 172 or 160, gender == "male" and 192 or 180),
		skills = skills,
		bag = math.random() < 0.5 and "waistbag" or "backpack",
	}
end

-- Проверка данных создания. Возвращает (ok, ошибка или очищенные данные).
function Chars.Validate(d)
	if type(d) ~= "table" then return false, "Неверные данные" end
	local name = NYRP.CleanText(d.name, 32)
	if utf8.len(name) < 3 then return false, "Имя слишком короткое (минимум 3 символа)" end
	if not string.find(name, " ") then return false, "Укажите имя и фамилию через пробел" end
	local desc = NYRP.CleanText(d.description, 300)
	if utf8.len(desc) < 10 then return false, "Описание слишком короткое (минимум 10 символов)" end
	local gender = d.gender == "female" and "female" or "male"
	if not table.HasValue(NYRP.Config.Models[gender], d.model) then return false, "Неверная модель" end
	local height = math.Clamp(math.floor(tonumber(d.height) or 175), NYRP.Config.HeightMin, NYRP.Config.HeightMax)
	local skills, total = {}, 0
	for _, s in ipairs(NYRP.Config.Skills) do
		local v = math.Clamp(math.floor(tonumber(d.skills and d.skills[s.id]) or 0), 0, NYRP.Config.SkillMax)
		skills[s.id] = v
		total = total + v
	end
	if total > NYRP.Config.SkillPoints then return false, "Слишком много очков навыков" end
	local bag = NYRP.Config.Bags[d.bag] and d.bag or "waistbag"
	return true, { name = name, description = desc, gender = gender, model = d.model, height = height, skills = skills, bag = bag }
end

-- Масштаб модели по росту (175 см = 1.0).
function Chars.HeightScale(height)
	return math.Clamp((height or 175) / 175, 0.9, 1.15)
end
