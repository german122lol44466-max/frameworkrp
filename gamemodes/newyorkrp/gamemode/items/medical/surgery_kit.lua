ITEM.Name = "Хирургический набор"
ITEM.Description = "Пинцет, зажимы, нить. Извлечь пулю из корпуса (медицина 3) или обработать ранение в голову (медицина 7)."
ITEM.Model = "models/props_lab/box01a.mdl"
ITEM.Stack = 1
ITEM.Uses = 3
ITEM.Treats = { body = true, head = true }
ITEM.Skill = 3
ITEM.SkillHead = 7
ITEM.TreatTime = 12
ITEM.Difficulty = 0.2
ITEM.Buffs = { { "Корпус и голова: полное лечение раны", true }, { "Нужна медицина 3 (голова — 7)", false } }
ITEM.Icon = { Angle = Angle(30, 200, 0), Zoom = 1.0 }
