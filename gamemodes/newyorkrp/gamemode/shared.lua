--[[
	New-York Roleplay — фреймворк для Garry's Mod.
	shared.lua: метаданные гейммода и загрузчик ядра/модулей.
]]

DeriveGamemode("sandbox")

GM.Name = "New-York Roleplay"
GM.Author = "NYRP Team"
GM.Website = ""
GM.Version = "0.1.0"

NYRP = NYRP or {}
NYRP.Version = GM.Version
NYRP.Root = GM.FolderName .. "/gamemode/"

-- Подключает файл с учётом реалма по префиксу имени: sv_ / cl_ / sh_.
-- realm можно передать явно ("server" | "client" | "shared").
function NYRP.Include(path, realm)
	local name = string.GetFileFromFilename(path)
	realm = realm
		or (string.StartWith(name, "sv_") and "server")
		or (string.StartWith(name, "cl_") and "client")
		or "shared"

	if realm == "server" then
		if SERVER then return include(path) end
	elseif realm == "client" then
		if SERVER then AddCSLuaFile(path) else return include(path) end
	else
		if SERVER then AddCSLuaFile(path) end
		return include(path)
	end
end

-- Подключает все .lua файлы в папке (относительно gamemode/).
-- Порядок: sh_ → sv_ → cl_, внутри группы — по алфавиту.
function NYRP.IncludeDir(dir)
	local base = NYRP.Root .. dir .. "/"
	local files = file.Find(base .. "*.lua", "LUA")

	for _, prefix in ipairs({ "sh_", "sv_", "cl_" }) do
		for _, f in ipairs(files) do
			if string.StartWith(f, prefix) then
				NYRP.Include(base .. f)
			end
		end
	end
end

-- Модули, от которых зависят другие, грузятся первыми; остальные — по алфавиту.
NYRP.ModuleOrder = { "items", "characters", "chat", "recognition" }

-- Каждая подпапка modules/ — отдельный модуль, загружается целиком.
function NYRP.LoadModules()
	local _, dirs = file.Find(NYRP.Root .. "modules/*", "LUA")
	local loaded = {}

	for _, dir in ipairs(NYRP.ModuleOrder) do
		if table.HasValue(dirs, dir) then
			NYRP.IncludeDir("modules/" .. dir)
			loaded[dir] = true
		end
	end
	for _, dir in ipairs(dirs) do
		if not loaded[dir] then
			NYRP.IncludeDir("modules/" .. dir)
		end
	end
end

NYRP.IncludeDir("core")
NYRP.LoadModules()
