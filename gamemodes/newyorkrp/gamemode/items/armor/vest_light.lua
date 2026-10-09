ITEM.Name = "Лёгкий бронежилет"
ITEM.Description = "Скрытый жилет из кевлара. Держит пистолетную пулю, почти не стесняет движений."
ITEM.Model = "models/nyrp/props/w_vest.mdl"
ITEM.Slot = "vest"
ITEM.Armor = 25                    -- очки брони
ITEM.Protect = 0.35                -- насколько меньше урон и шанс ранения в корпус (0..0.9)
ITEM.ProtectZone = "body"          -- body — корпус, head — голова
ITEM.Speed = -0.03                 -- −3% к скорости
ITEM.Wear = { Follow = "body", Pos = Vector(1.5, 0, -3), Scale = 0.92 }   -- как выглядит на игроке
ITEM.Bodygroups = {}               -- например { ["torso"] = 2 } — у моделей с такими группами
ITEM.Icon = { Angle = Angle(10, 200, 0), Zoom = 0.9 }
