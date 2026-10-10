-- Блокнот: 10 листов. ПКМ → «Написать записку» — окно письма (modules/writing), лист становится «Запиской».
ITEM.Name = "Блокнот"
ITEM.Description = "Блокнот на 10 листов и ручка. Напишите записку и передайте её или оставьте на столе."
ITEM.Model = "models/props_lab/clipboard.mdl"
ITEM.Type = "misc"
ITEM.Stack = 1
ITEM.Price = 8
ITEM.UseText = "Написать записку"
ITEM.Buffs = { { "10 листов", true }, { "Записки до 1000 символов, с подписью", true } }
ITEM.Icon = { Angle = Angle(60, 90, 0), Zoom = 1.1 }
ITEM.OnUse = function(ply, it) return false end   -- окно открывается на клиенте (NYRP.ItemView)
