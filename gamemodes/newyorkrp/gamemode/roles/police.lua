ROLE.Name = "Полицейский NYPD"
ROLE.Description = "Патрульный полиции Нью-Йорка. Следит за порядком, выписывает штрафы."
ROLE.Color = Color(80, 140, 230)
ROLE.Icon = "shield"
ROLE.Model = { "models/player/police.mdl", "models/player/police_fem.mdl" }   -- по полу персонажа: мужская, женская
ROLE.Salary = 120
ROLE.Items = { "radio", "baton" }
ROLE.Whitelist = true             -- назначает только администрация: /setrole <имя> police
