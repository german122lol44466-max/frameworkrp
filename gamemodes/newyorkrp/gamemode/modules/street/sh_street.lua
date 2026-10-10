--[[
	Уличные объекты Нью-Йорка (модели — tools/models/build_city.py, реальные размеры):
	  гидрант (заправить огнетушитель), газетный автомат (газета со свежими новостями города, $1),
	  паркомат (оплатить парковку), почтовый ящик USPS (письма почтальона), тележка хот-догов (еда),
	  урна (выбросить мусор), таксофон (бесплатный 911), знак остановки (расписание).
	Ставит админ: спавн-меню (вкладка Entities → New-York Roleplay) или /street <вид>, убрать — /streetremove.
	Сохраняются в data/nyrp/street_<карта>.json.
]]
NYRP.Street = NYRP.Street or {}
local S = NYRP.Street

S.Types = {
	hydrant = { name = "Пожарный гидрант", model = "models/nyrp/city/hydrant.mdl", text = "Заправить огнетушитель", icon = "droplet" },
	newsbox = { name = "Газетный автомат", model = "models/nyrp/city/newsbox.mdl", text = "Купить газету ($1)", icon = "j_reporter" },
	parkingmeter = { name = "Паркомат", model = "models/nyrp/city/parkingmeter.mdl", text = "Оплатить парковку ($2 / час)", icon = "dollar" },
	usps = { name = "Почтовый ящик USPS", model = "models/nyrp/city/usps_box.mdl", text = "Почта США", icon = "j_mail" },
	hotdog = { name = "Тележка хот-догов", model = "models/nyrp/city/hotdog_cart.mdl", text = "Купить еду", icon = "food" },
	trash = { name = "Урна", model = "models/nyrp/city/trash_basket.mdl", text = "Выбросить мусор", icon = "trash" },
	payphone = { name = "Таксофон", model = "models/nyrp/city/payphone.mdl", text = "Позвонить в 911 (бесплатно)", icon = "phone_call" },
	busstop = { name = "Остановка автобуса", model = "models/nyrp/city/bus_stop.mdl", text = "Расписание", icon = "clock" },
}

-- меню тележки хот-догов
S.Food = {
	{ id = "hotdog", price = 3 }, { id = "pretzel", price = 2 }, { id = "soda", price = 1 }, { id = "coffee", price = 2 },
}

-- заголовки газеты «New York Daily News» (к ним добавляются события сервера)
S.Headlines = {
	"Мэрия обещает отремонтировать мост Квинсборо к весне",
	"В Бруклине открылся ещё один кофейня-бар с котами",
	"Метро: поезда линии L снова ходят с опозданием",
	"NYPD усилила патрули в Нижнем Манхэттене",
	"Цены на аренду в Квинсе выросли на 4%",
	"Пожарные FDNY спасли кошку с крыши на 5-й авеню",
	"Хот-доги подорожали на 50 центов: продавцы винят инфляцию",
	"Центральный парк: открыт сезон катка",
	"Таксисты жалуются на пробки у Таймс-сквер",
	"Ратуша упрощает выдачу лицензий малому бизнесу",
}
