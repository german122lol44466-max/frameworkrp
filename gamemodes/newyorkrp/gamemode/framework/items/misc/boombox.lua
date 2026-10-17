ITEM.Name = "Бумбокс"
ITEM.Description = "Переносной радиоприёмник с мощным динамиком. ПКМ → «Поставить» перед собой; E по бумбоксу — выбрать интернет-радиостанцию, громкость, выключить или забрать. Музыку слышат все вокруг."
ITEM.Model = "models/props_lab/citizenradio.mdl"
ITEM.UseText = "Поставить"
ITEM.Price = 120
ITEM.Buffs = { { "6 радиостанций: lo-fi, джаз, рок, поп, хип-хоп, классика", true }, { "Уйдёте далеко на 5 минут — вернётся в сумку", false } }
ITEM.Icon = { Angle = Angle(10, 200, 0), Zoom = 1.1 }
ITEM.OnUse = function(ply, it)
	local BB = NYRP.Leisure and NYRP.Leisure.Boombox
	if SERVER and BB and BB.Place then return BB.Place(ply) end
	return false
end
