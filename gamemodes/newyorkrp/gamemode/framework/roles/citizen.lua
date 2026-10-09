-- Роль по умолчанию: её получает каждый новый персонаж. Гражданину доступны профессии (центр занятости).
ROLE.Name = "Гражданин"
ROLE.Description = "Обычный житель Нью-Йорка. Работает (центр занятости), снимает квартиру, открывает бизнес."
ROLE.Color = Color(120, 214, 110)
ROLE.Icon = "r_citizen"           -- значок слева от ника (materials/nyrp/status/<имя>.png); у гражданина не показывается
ROLE.ShowIcon = false
ROLE.Default = true
ROLE.Model = nil                  -- nil — модель персонажа
ROLE.Salary = 0
ROLE.Items = {}
ROLE.Jobs = true                  -- может брать профессии
