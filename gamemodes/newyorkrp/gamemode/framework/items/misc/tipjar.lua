ITEM.Name = "Шляпа для чаевых"
ITEM.Description = "Старая жестянка «на удачу» для уличного музыканта. ПКМ → «Поставить» перед собой: прохожие смогут бросить вам чаевые (E). Заберите её вместе с деньгами — E."
ITEM.Model = "models/props_junk/garbage_metalcan001a.mdl"
ITEM.UseText = "Поставить"
ITEM.Price = 15
ITEM.Buffs = { { "Прохожие дают чаевые", true }, { "Уйдёте далеко на 5 минут — шляпа пропадёт", false } }
ITEM.Icon = { Angle = Angle(20, 200, 0), Zoom = 1.1 }
ITEM.OnUse = function(ply, it) return NYRP.StreetFun.PlaceTipJar(ply) end
