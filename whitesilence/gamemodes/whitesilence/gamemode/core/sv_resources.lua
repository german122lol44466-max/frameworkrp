--[[
	Раздача контента клиентам (FastDL / прямое скачивание с сервера).
	Если контент залит в Workshop — достаточно resource.AddWorkshop(<id>) в своём конфиге сервера.
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

-- Контент лежит в addons/whitesilence_content (или в gamemodes/whitesilence/content) — оба видны в GAME.
for _, dir in ipairs({ "materials/whitesilence", "sound/whitesilence" }) do
	addDir(dir)
end
for _, pattern in ipairs({ "CormorantGaramond_*.ttf", "Oswald_*.ttf", "IBMPlexMono_*.ttf", "AlegreyaSansSC_*.ttf", "Exo2_*.ttf" }) do
	for _, f in ipairs(file.Find("resource/fonts/" .. pattern, "GAME") or {}) do
		resource.AddSingleFile("resource/fonts/" .. f)
	end
end
