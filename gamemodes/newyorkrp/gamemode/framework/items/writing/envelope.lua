-- Конверт: ПКМ → «Написать письмо» у почтовых ящиков дома или синего ящика USPS — письмо уходит
-- в почтовый ящик выбранной квартиры (modules/writing).
ITEM.Name = "Конверт с маркой"
ITEM.Description = "Почтовый конверт с маркой. Напишите письмо и отправьте его у почтовых ящиков или синего ящика USPS."
ITEM.Model = "models/props_c17/paper01.mdl"
ITEM.Type = "misc"
ITEM.Stack = 5
ITEM.Price = 3
ITEM.UseText = "Написать письмо"
ITEM.Buffs = { { "Доставка в почтовый ящик квартиры", true } }
ITEM.Icon = { Angle = Angle(70, 0, 0), Zoom = 1.2 }
ITEM.OnUse = function(ply, it) return false end
