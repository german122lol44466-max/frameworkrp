ITEM.Name = "Красное вино"
ITEM.Description = "Бутылка калифорнийского каберне из винной лавки в Виллидже. Крепость 13%."
ITEM.Model = "models/props_junk/garbage_glassbottle003a.mdl"
ITEM.Stack = 2
ITEM.Thirst = 10
ITEM.Leaves = "bottle_empty"
ITEM.Buffs = { { "+10 к жажде", true }, { "Крепость 13% — заметное опьянение", false } }
ITEM.OnUse = function(ply, item)
	if NYRP.Alcohol and NYRP.Alcohol.Drink then NYRP.Alcohol.Drink(ply, 20) end
end
