ROLE.Name = "Полиция NYPD"
ROLE.Description = "Патрульные Нью-Йоркского департамента полиции. Приезжают на вызовы 911, ловят грабителей, выписывают штрафы."
ROLE.Color = Color(80, 140, 230)
ROLE.Icon = "r_police"
ROLE.Model = { "models/player/police.mdl", "models/player/police_fem.mdl" }   -- мужская, женская
ROLE.Salary = 150                 -- в игровую полночь на карту
ROLE.Items = { "radio", "baton", "pistol", "vest_light" }
-- требования (меню фракций у NPC-вербовщика)
ROLE.Whitelist = false            -- true — только по одобрению администрации (заявка)
ROLE.MinHours = 2                 -- сколько часов отыграть этим персонажем
ROLE.MinSkills = { combat = 2 }   -- навыки
ROLE.MaxMembers = 8               -- 0 — без ограничения
-- 911: причины вызова этой службы
ROLE.Service = "Полиция"
ROLE.Calls = { "Ограбление", "Драка", "Угрозы оружием", "Кража", "Подозрительный человек", "Шум и беспорядок", "Другое" }
