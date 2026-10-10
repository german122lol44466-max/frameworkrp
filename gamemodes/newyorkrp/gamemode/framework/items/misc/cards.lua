ITEM.Name = "Колода карт"
ITEM.Description = "Потрёпанная колода из 52 карт. ПКМ → «Вытянуть карту» — все рядом увидят, что выпало. Кончились карты — колода тасуется заново."
ITEM.Model = "models/props_lab/box01a.mdl"
ITEM.UseText = "Вытянуть карту"
ITEM.Price = 5
ITEM.Buffs = { { "ПКМ — вытянуть карту (видят все рядом)", true }, { "Ещё: /roll, /coin, /dice в чате", true } }
ITEM.Icon = { Angle = Angle(30, 200, 0), Zoom = 1.3 }
ITEM.OnUse = function(ply, it) return NYRP.StreetFun.DrawCard(ply, it) end
