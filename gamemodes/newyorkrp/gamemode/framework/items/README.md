# Предметы

Каждый файл `<папка>/<id>.lua` — один предмет. Имя файла — его id (по нему выдают предмет, кладут в лут и т.д.).
Папка задаёт тип по умолчанию: `food` (еда), `drinks` (напитки), `medical` (медицина), `clothing` (одежда),
`armor` (броня), `weapons` (оружие), `tools` (инструменты в руку), `documents` (документы), `misc` (разное).
Новые папки можно создавать — тогда укажите `ITEM.Type`.

```lua
ITEM.Name = "Бутылка воды"                    -- название
ITEM.Description = "Холодная вода."             -- описание
ITEM.Model = "models/props_junk/garbage_plasticbottle003a.mdl"
ITEM.Type = "drink"     -- food | drink | medical | clothing | armor | weapon | tool | document | misc
ITEM.Stack = 5          -- сколько штук в одной ячейке

-- еда / напитки / медицина (использование — ПКМ в инвентаре)
ITEM.Hunger = 0         -- + к сытости
ITEM.Thirst = 35        -- + к жажде
ITEM.Health = 0         -- + к здоровью
ITEM.Stamina = 0        -- + к выносливости
ITEM.UseText = "Выпить" -- подпись кнопки
ITEM.UseSound = "nyrp/fx/drink1.wav"
ITEM.Leaves = "bottle_empty"   -- что остаётся после (id другого предмета)
ITEM.Uses = 1           -- сколько раз можно использовать (пачка сигарет — 20)

-- одежда и броня (куда надевается)
ITEM.Slot = "head"      -- head, glasses, mask, jacket, shirt, gloves, pants, shoes, vest
ITEM.Bodygroups = { ["torso"] = 2 }   -- какие бодигруппы модели игрока меняет (имя группы = номер)
ITEM.Armor = 25         -- очки брони
ITEM.Protect = 0.5      -- защита от ранений 0..0.9
ITEM.ProtectZone = "body"   -- body (корпус) или head (голова)
ITEM.Speed = -0.1       -- −10% к скорости (тяжёлая броня)
ITEM.Heavy = true       -- отметка «тяжёлая броня»
ITEM.HidesFace = true   -- скрывает лицо (вас не узнают)
ITEM.Wear = { Follow = "body", Pos = Vector(1.5, 0, -3), Scale = 1 }   -- модель видна на игроке

-- оружие и инструменты
ITEM.Slot = "secondary" -- primary, secondary, melee, tool (в руке), phone, radio
ITEM.Weapon = "weapon_pistol"   -- класс оружия
ITEM.Ammo = { "Pistol", 36 }    -- патроны при первой экипировке

-- необязательно
ITEM.Buffs = { { "Плюс", true }, { "Минус", false } }   -- иначе соберутся сами из чисел выше
ITEM.Icon = { Angle = Angle(10, 90, 0), Zoom = 1.1 }   -- ракурс иконки
ITEM.Disabled = true    -- временно выключить предмет
ITEM.OnUse = function(ply, item) return true end   -- свой код (для тех, кто умеет)
```
