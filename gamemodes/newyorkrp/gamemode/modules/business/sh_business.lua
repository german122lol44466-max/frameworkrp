--[[
	Бизнес. Как в жизни:
	  1) ратуша (NPC: /npc cityhall) — заявление: вид деятельности, название, проверка данных, пошлина с карты,
	     подпись → лицензия (документ в сумке, номер, печать);
	  2) там же — свободные коммерческие помещения (админ: /doorbusiness <цена/день> [название]) → аренда, метка на двери;
	  3) ключи — почтовый ящик; F1 по двери — открыть/закрыть бизнес. Пока открыто и владелец рядом —
	     каждые 10 минут на счёт приходит выручка (зависит от вида деятельности).
]]
NYRP.Business = NYRP.Business or {}
local B = NYRP.Business

B.Types = {
	{ id = "shop", name = "Магазин у дома", icon = "store", fee = 400, income = { 40, 90 } },
	{ id = "cafe", name = "Кафе", icon = "coffee", fee = 500, income = { 50, 110 } },
	{ id = "bar", name = "Бар", icon = "bottle", fee = 700, income = { 60, 140 } },
	{ id = "garage", name = "Автосервис", icon = "tools", fee = 800, income = { 70, 150 } },
	{ id = "salon", name = "Салон красоты", icon = "user", fee = 450, income = { 45, 100 } },
	{ id = "pawn", name = "Ломбард", icon = "dollar", fee = 900, income = { 60, 170 } },
	{ id = "office", name = "Офис / агентство", icon = "briefcase2", fee = 600, income = { 55, 120 } },
}
B.TypeById = {}
for _, t in ipairs(B.Types) do B.TypeById[t.id] = t end
