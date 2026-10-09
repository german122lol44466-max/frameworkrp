ITEM.Name = "Бинт"
ITEM.Description = "Стерильный бинт. Перетащите на руку, ногу или корпус в меню состояния (J): останавливает кровотечение."
ITEM.Model = "models/props_junk/garbage_bag001a.mdl"
ITEM.Stack = 5
ITEM.Treats = { arm = true, leg = true, body = true }   -- какие части тела лечит (head, body, arm, leg)
ITEM.Skill = 0                -- нужный уровень медицины
ITEM.TreatTime = 4            -- секунд (навык ускоряет)
ITEM.Difficulty = 0.0         -- сложность: выше — чаще неудача у новичка
ITEM.Buffs = { { "Руки, ноги, корпус: останавливает кровь", true }, { "Без навыка может сползти", false } }
ITEM.Icon = { Angle = Angle(40, 200, 0), Zoom = 1.2 }
