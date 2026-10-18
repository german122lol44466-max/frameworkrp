--[[
	Шрифты (лежат в content/resource/fonts, OFL):
	  Alegreya Sans SC — субтитры интро (капитель); Cormorant Garamond — повествование;
	  Oswald — заголовки; IBM Plex Mono — служебные подписи; Exo 2 — главное меню и лобби.
	WS.Font(style, size[, blur]) — size в пикселях для 1080p, масштабируется под экран; blur — размытая копия для свечения.
]]

local families = {
	story = { "Cormorant Garamond Medium", 500 },
	storyi = { "Cormorant Garamond Medium", 500, true },
	storybold = { "Cormorant Garamond SemiBold", 600 },
	title = { "Oswald Medium", 500 },
	titlelight = { "Oswald Light", 300 },
	mono = { "IBM Plex Mono", 400 },
	sub = { "Alegreya Sans SC", 700 },
	subheavy = { "Alegreya Sans SC ExtraBold", 800 },
	submed = { "Alegreya Sans SC Medium", 500 },
	-- Exo 2 — главное меню и лобби
	menu = { "Exo 2", 400 },
	menulight = { "Exo 2 Light", 300 },
	menusemi = { "Exo 2 SemiBold", 600 },
	menubold = { "Exo 2", 700 },
}

local created = {}

local function create(name, style, size, blur)
	local fam = families[style] or families.story
	surface.CreateFont(name, {
		font = fam[1],
		weight = fam[2],
		italic = fam[3] or false,
		size = math.max(8, math.Round(size * ScrH() / 1080)),
		blursize = blur or 0,
		extended = true,
		antialias = true,
	})
end

function WS.Font(style, size, blur)
	local name = "ws." .. style .. "." .. size .. (blur and (".b" .. blur) or "")
	if not created[name] then
		create(name, style, size, blur)
		created[name] = { style, size, blur }
	end
	return name
end

-- При смене разрешения пересоздаём всё, что уже было создано.
hook.Add("OnScreenSizeChanged", "ws.fonts", function()
	for name, def in pairs(created) do
		create(name, def[1], def[2], def[3])
	end
end)
