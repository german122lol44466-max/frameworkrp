ITEM.Name = "Водка «Bowery»"
ITEM.Description = "Прозрачная водка из лавки на Бауэри. Крепость 40%. Без закуски — прямой путь на тротуар."
ITEM.Model = "models/props_junk/garbage_glassbottle002a.mdl"
ITEM.Stack = 2
ITEM.Thirst = -5
ITEM.Leaves = "bottle_empty"
ITEM.Buffs = { { "Крепость 40% — очень сильное опьянение", false }, { "Немного сушит", false } }
ITEM.OnUse = function(ply, item)
	if NYRP.Alcohol and NYRP.Alcohol.Drink then NYRP.Alcohol.Drink(ply, 36) end
end
