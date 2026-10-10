-- Записка: текст, подпись и дата — в данных предмета (it.data). ПКМ → «Прочитать».
ITEM.Name = "Записка"
ITEM.Description = "Листок из блокнота с текстом."
ITEM.Model = "models/props_c17/paper01.mdl"
ITEM.Type = "misc"
ITEM.Stack = 1
ITEM.UseText = "Прочитать"
ITEM.Buffs = {}
ITEM.Icon = { Angle = Angle(70, 90, 0), Zoom = 1.2 }
ITEM.OnUse = function(ply, it) return false end   -- читается на клиенте (NYRP.ItemView)
