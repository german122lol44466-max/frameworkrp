--[[
	Отправка контента клиентам (FastDL / прямое скачивание).
	Для Workshop-сервера достаточно подписки на аддон с контентом — тогда это не нужно.
]]

local function addDir(dir)
	local files, dirs = file.Find(dir .. "/*", "GAME")
	for _, f in ipairs(files or {}) do
		resource.AddSingleFile(dir .. "/" .. f)
	end
	for _, d in ipairs(dirs or {}) do
		addDir(dir .. "/" .. d)
	end
end

-- Контент гейммода лежит в gamemodes/newyorkrp/content и смонтирован в GAME.
for _, dir in ipairs({ "materials/nyrp", "materials/models/nyrp", "models/nyrp", "sound/nyrp" }) do
	addDir(dir)
end
for _, f in ipairs(file.Find("resource/fonts/Manrope_*.ttf", "GAME") or {}) do
	resource.AddSingleFile("resource/fonts/" .. f)
end
for _, f in ipairs(file.Find("resource/fonts/Oswald_*.ttf", "GAME") or {}) do
	resource.AddSingleFile("resource/fonts/" .. f)
end
