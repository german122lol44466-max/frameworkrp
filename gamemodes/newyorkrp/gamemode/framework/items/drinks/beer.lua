ITEM.Name = "Пиво «Brooklyn Lager»"
ITEM.Description = "Холодное светлое пиво бруклинской пивоварни. Крепость 5%. Пара бутылок — и мир становится добрее."
ITEM.Model = "models/props_junk/garbage_glassbottle001a.mdl"
ITEM.Stack = 6
ITEM.Thirst = 15
ITEM.Leaves = "bottle_empty"
ITEM.Buffs = { { "+15 к жажде", true }, { "Крепость 5% — лёгкое опьянение", false } }
-- опьянение: модуль modules/alcohol (сила — сколько единиц добавляет к уровню опьянения 0..100)
ITEM.OnUse = function(ply, item)
	if NYRP.Alcohol and NYRP.Alcohol.Drink then NYRP.Alcohol.Drink(ply, 12) end
end
