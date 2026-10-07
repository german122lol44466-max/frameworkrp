<p align="center"><img src="branding/banner_1920x600.png" alt="New-York Roleplay"></p>

# New-York Roleplay (NYRP)

Фреймворк-гейммод для Garry's Mod: ролевая игра в Нью-Йорке.

## Установка

Скопируйте папку `gamemodes/newyorkrp` в `garrysmod/gamemodes/` на сервере
и запустите его с `+gamemode newyorkrp` (карты с префиксом `rp_`).

## Что уже есть

- База на `sandbox` с загрузчиком файлов по префиксу `sh_` / `sv_` / `cl_`.
- Автозагрузка модулей из `gamemode/modules/<модуль>/`.
- Отключён стандартный HUD: здоровье, броня, патроны, прицел, индикатор урона,
  ник при наведении, история подбора предметов, килфид. Список — в
  `gamemode/core/sh_config.lua` (`NYRP.Config.HiddenHUD`).

## Структура

```
gamemodes/newyorkrp/
  newyorkrp.txt          описание гейммода
  logo.png, icon24.png   лого в меню GMod
  gamemode/
    init.lua, cl_init.lua, shared.lua
    core/                ядро (конфиг, утилиты, скрытие HUD)
    modules/             модули фреймворка
branding/                лого, баннер, обои
tools/branding/          генератор графики (python3 + Pillow)
```

## Брендинг

| Файл | Размер |
|---|---|
| `branding/logo_1024.png` / `logo_512.png` / `logo_256.png` | квадратное лого |
| `branding/banner_1920x600.png` | баннер |
| `branding/wallpaper_1920x1080.png` | обои / загрузочный экран |

Перегенерировать: `python3 tools/branding/generate.py`.
