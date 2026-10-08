--[[
	Шрифты: Manrope (интерфейс, чат), Oswald (заголовки), Exo 2 (ники над головой). Лежат в content/resource/fonts.
	NYRP.Font(style, size) — size в пикселях для 1080p, масштабируется под экран.
]]

local families = {
	regular = { "Manrope", 400 },
	medium = { "Manrope Medium", 500 },
	semibold = { "Manrope SemiBold", 600 },
	bold = { "Manrope ExtraBold", 800 },
	title = { "Oswald SemiBold", 600 },
	titlemed = { "Oswald Medium", 500 },
	titlelight = { "Oswald Light", 300 },
	-- Exo 2 — ники над игроками
	tag = { "Exo 2 Medium", 500 },
	tagbold = { "Exo 2 SemiBold", 600 },
}

local created = {}

local function create(name, style, size)
	local fam = families[style] or families.regular
	surface.CreateFont(name, {
		font = fam[1],
		weight = fam[2],
		size = math.max(8, math.Round(size * ScrH() / 1080)),
		extended = true,
		antialias = true,
	})
end

function NYRP.Font(style, size)
	local name = "nyrp." .. style .. "." .. size
	if not created[name] then
		create(name, style, size)
		created[name] = { style, size }
	end
	return name
end

hook.Add("OnScreenSizeChanged", "nyrp.fonts", function()
	for name, def in pairs(created) do
		create(name, def[1], def[2])
	end
end)

-- Шрифт фиксированного размера в пикселях (для 3D2D-текста в мире — не зависит от разрешения).
local raw = {}
function NYRP.FontRaw(style, size)
	local name = "nyrp.raw." .. style .. "." .. size
	if not raw[name] then
		local fam = families[style] or families.regular
		surface.CreateFont(name, { font = fam[1], weight = fam[2], size = size, extended = true, antialias = true })
		raw[name] = true
	end
	return name
end
