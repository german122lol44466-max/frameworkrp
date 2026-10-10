ROLE.Name = "Пожарные FDNY"
ROLE.Description = "Пожарный департамент Нью-Йорка. Тушат пожары, спасают людей, помогают при авариях."
ROLE.Color = Color(240, 140, 50)
ROLE.Icon = "r_fire"
ROLE.Model = nil
ROLE.Salary = 120
ROLE.Radio = 170.0                -- частота рации на дежурстве
ROLE.DutyPay = 25                -- за каждые 10 минут на дежурстве (наличными)
ROLE.Items = { "radio", "crowbar", "helmet", "extinguisher" }
ROLE.Whitelist = false
ROLE.MinHours = 1
ROLE.MinSkills = { strength = 2 }
ROLE.MaxMembers = 6
ROLE.Service = "Пожарные"
ROLE.Calls = { "Пожар в здании", "Возгорание машины", "Запах газа", "Человек заперт", "Спасение (высота)", "Другое" }
