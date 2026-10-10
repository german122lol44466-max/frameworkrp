-- Полученное письмо (из почтового ящика): текст, отправитель, адрес, дата — в it.data. ПКМ → «Прочитать».
ITEM.Name = "Письмо"
ITEM.Description = "Вскрытое письмо из почтового ящика."
ITEM.Model = "models/props_c17/paper01.mdl"
ITEM.Type = "misc"
ITEM.Stack = 1
ITEM.UseText = "Прочитать"
ITEM.Buffs = {}
ITEM.Icon = { Angle = Angle(70, 0, 0), Zoom = 1.2 }
ITEM.OnUse = function(ply, it) return false end
