--[[
	Точки появления и сохранение позиции — общая часть (сетевые сообщения).
	  sv_spawns.lua — точки по ролям (/spawnadd, /spawnremove, /spawns) и выбор места при возрождении,
	                  сохранение позиции персонажа при выходе / смене персонажа (c.flags.lastPos / lastMap).
	  cl_spawns.lua — маркеры точек у админа.
]]

NYRP.Spawns = NYRP.Spawns or {}

if SERVER then
	util.AddNetworkString("nyrp.spawns.show")
end
