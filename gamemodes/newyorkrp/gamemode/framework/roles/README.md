# Роли (фракции)

Каждый файл `<id>.lua` — одна фракция. Имя файла — её id.

```lua
ROLE.Name = "Полиция NYPD"
ROLE.Description = "..."
ROLE.Color = Color(80, 140, 230)
ROLE.Icon = "r_police"          -- значок слева от ника: materials/nyrp/status/<имя>.png
ROLE.ShowIcon = true            -- false — не показывать значок
ROLE.Default = true             -- стартовая (ровно одна — гражданин)
ROLE.Model = nil                -- строка или { мужская, женская }
ROLE.Salary = 150               -- зарплата в игровую полночь на карту
ROLE.Items = { "radio" }        -- выдаётся при вступлении
ROLE.Jobs = true                -- может брать профессии (центр занятости)

-- как вступить (NPC-вербовщик: /npc factions)
ROLE.Whitelist = false          -- true — заявка, принимает администрация (/facaccept имя)
ROLE.MinHours = 2               -- часов игры этим персонажем
ROLE.MinSkills = { combat = 2 } -- навыки
ROLE.MaxMembers = 8             -- 0 — без лимита

-- 911 (телефон): эту службу можно вызвать, причины — свои
ROLE.Service = "Полиция"
ROLE.Calls = { "Ограбление", "Драка" }
```
Админ: `/setrole <имя> <id>`, `/facaccept <имя>` (принять заявку).
