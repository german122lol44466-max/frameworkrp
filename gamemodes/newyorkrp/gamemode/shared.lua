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

-- Пространства имён создаются заранее: файлы делают «local UI = NYRP.UI» при загрузке,
-- и таблица должна существовать независимо от порядка подключения.
for _, ns in ipairs({ "UI", "Config", "Chars", "Chat", "Items", "Inv", "Inventory", "Bags", "Camera",
	"Interact", "Recog", "Overhead", "Points", "DB",
	-- модули грузятся по алфавиту, а ссылаются друг на друга при загрузке (local W = NYRP.Waypoint):
	-- все общие таблицы создаём заранее, чтобы порядок файлов был неважен
	"Bags", "Bank", "Business", "Camera", "Combat", "Cond", "Containers", "Doors", "E911", "Gestures", "Health",
	"Jobs", "Money", "NPC", "Phone", "Radio", "Roles", "Skills", "Smoking", "Time", "Voice", "Waypoint", "Zones",
	"Police", "Fire", "EMS", "Street", "Factions" }) do
	NYRP[ns] = NYRP[ns] or {}
end

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
-- Порядок: sh_ → sv_ → cl_; внутри группы сначала файлы из first, потом по алфавиту.
function NYRP.IncludeDir(dir, first)
	local base = NYRP.Root .. dir .. "/"
	local files = file.Find(base .. "*.lua", "LUA")
	local rank = {}
	for i, f in ipairs(first or {}) do rank[f] = i end
	table.sort(files, function(a, b)
		local ra, rb = rank[a] or math.huge, rank[b] or math.huge
		if ra ~= rb then return ra < rb end
		return a < b
	end)

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

-- В ядре сначала конфиг, утилиты, тема интерфейса и шрифты — от них зависят остальные файлы.
NYRP.IncludeDir("core", { "sh_config.lua", "sh_util.lua", "sh_net.lua", "sv_db.lua", "cl_ui.lua", "cl_fonts.lua", "cl_elements.lua" })
NYRP.LoadModules()
