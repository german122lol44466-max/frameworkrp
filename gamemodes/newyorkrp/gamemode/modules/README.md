# Модули

Каждая подпапка здесь — модуль; все её `.lua` файлы подключаются автоматически
по префиксу: `sh_` (общий), `sv_` (сервер), `cl_` (клиент).

```
modules/
  hud/
    cl_hud.lua
  economy/
    sh_economy.lua
    sv_economy.lua
```

## Важно про хуки

В GMod значение, возвращённое из обработчика хука, **останавливает все остальные обработчики** этого хука.
Поэтому в «событийных» хуках (`Initialize`, `InitPostEntity`, `PlayerSpawn`, `NYRP.CharacterLoaded` и т.п.)
ничего не возвращайте и не передавайте туда напрямую функцию, которая что-то возвращает:

```lua
hook.Add("InitPostEntity", "my.module", function() myInit() end)   -- правильно
hook.Add("InitPostEntity", "my.module", myInit)                      -- опасно, если myInit возвращает значение
```
