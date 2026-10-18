--[[
	SCP: Белая тишина — фреймворк-гейммод для Garry's Mod.
	shared.lua: метаданные и загрузчик. Ядро (core/) грузится первым, затем каждая папка modules/.
	Файлы подключаются по префиксу: sh_ — оба реалма, sv_ — сервер, cl_ — клиент.
]]

DeriveGamemode("sandbox")

GM.Name = "SCP: Белая тишина"
GM.Author = "John Make"
GM.Website = ""
GM.Version = "0.1.0"

WS = WS or {}
WS.Version = GM.Version
WS.Root = GM.FolderName .. "/gamemode/"

-- Общие пространства имён создаются заранее: порядок загрузки файлов не важен.
for _, ns in ipairs({ "Config", "UI", "Audio", "Intro" }) do
	WS[ns] = WS[ns] or {}
end

function WS.Include(path, realm)
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

-- Все .lua в папке (относительно gamemode/): sh_ → sv_ → cl_, внутри группы — сначала first, потом по алфавиту.
function WS.IncludeDir(dir, first)
	local base = WS.Root .. dir .. "/"
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
			if string.StartWith(f, prefix) then WS.Include(base .. f) end
		end
	end
end

-- Модули, от которых зависят другие, перечисляются здесь; остальные грузятся по алфавиту.
WS.ModuleOrder = {}

function WS.LoadModules()
	local _, dirs = file.Find(WS.Root .. "modules/*", "LUA")
	local loaded = {}
	for _, dir in ipairs(WS.ModuleOrder) do
		if table.HasValue(dirs, dir) then
			WS.IncludeDir("modules/" .. dir)
			loaded[dir] = true
		end
	end
	table.sort(dirs)
	for _, dir in ipairs(dirs) do
		if not loaded[dir] then WS.IncludeDir("modules/" .. dir) end
	end
end

WS.IncludeDir("core", { "sh_config.lua", "sh_util.lua" })
WS.LoadModules()
