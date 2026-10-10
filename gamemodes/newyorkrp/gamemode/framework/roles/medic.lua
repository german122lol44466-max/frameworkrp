ROLE.Name = "Скорая помощь EMS"
ROLE.Description = "Парамедики города. Едут на вызовы, поднимают раненых, лечат пулевые и переломы."
ROLE.Color = Color(230, 90, 90)
ROLE.Icon = "r_medic"
ROLE.Model = nil
ROLE.Salary = 130
ROLE.Items = { "medkit", "medkit", "bandage", "bandage", "splint", "surgery_kit", "radio", "defib" }
ROLE.Whitelist = false
ROLE.MinHours = 1
ROLE.MinSkills = { medicine = 2 }
ROLE.MaxMembers = 6
ROLE.Service = "Скорая"
ROLE.Calls = { "Огнестрельное ранение", "Человек без сознания", "Перелом", "Сильное кровотечение", "ДТП", "Плохо с сердцем", "Другое" }
