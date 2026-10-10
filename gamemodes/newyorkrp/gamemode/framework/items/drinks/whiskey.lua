ITEM.Name = "Виски «Hudson Reserve»"
ITEM.Description = "Бурбон с медовыми нотками. Крепость 40%. Пить лучше маленькими глотками."
ITEM.Model = "models/props_junk/glassjug01.mdl"
ITEM.Stack = 2
ITEM.Thirst = -5
ITEM.Leaves = "bottle_empty"
ITEM.Buffs = { { "Крепость 40% — сильное опьянение", false }, { "Немного сушит", false } }
ITEM.OnUse = function(ply, item)
	if NYRP.Alcohol and NYRP.Alcohol.Drink then NYRP.Alcohol.Drink(ply, 32) end
end
