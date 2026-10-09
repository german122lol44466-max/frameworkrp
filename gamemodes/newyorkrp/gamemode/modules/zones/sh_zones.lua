--[[
	Зоны карты (районы, здания): при входе слева посередине на 8 секунд появляется иконка и название,
	название печатается как на машинке (звук на каждую букву).
	Админ: /areaedit — список зон и «Новая зона»: ЛКМ — первый угол, долетите до второго — ЛКМ,
	затем название и одна из 50 иконок. Хранятся в data/nyrp/zones_<карта>.json.
]]

NYRP.Zones = NYRP.Zones or {}
local Z = NYRP.Zones
Z.List = Z.List or {}

Z.Icons = {
	"building", "building-skyscraper", "building-hospital", "building-store", "building-bank", "building-church",
	"building-factory", "building-warehouse", "building-bridge", "building-bridge-2", "building-community",
	"building-estate", "building-arch", "building-castle", "building-stadium", "building-carousel",
	"building-monument", "building-lighthouse", "building-cottage", "home", "tree", "trees", "fountain", "beach",
	"anchor", "ship", "plane", "train", "bus", "car", "motorbike", "bike", "parking", "gas-station", "school",
	"shield", "ambulance", "pill", "coffee", "pizza", "beer", "shopping-cart", "shopping-bag", "tools", "barbell",
	"book-2", "music", "cards", "skull", "bed",
}

function Z.Contains(z, pos)
	return pos.x >= z.min.x and pos.x <= z.max.x and pos.y >= z.min.y and pos.y <= z.max.y and pos.z >= z.min.z and pos.z <= z.max.z
end

-- самая маленькая зона, в которой точка (вложенные: «Бруклин» → «Кафе на углу»)
function Z.At(pos)
	local best, vol
	for _, z in ipairs(Z.List) do
		if Z.Contains(z, pos) then
			local v = (z.max.x - z.min.x) * (z.max.y - z.min.y) * (z.max.z - z.min.z)
			if not vol or v < vol then best, vol = z, v end
		end
	end
	return best
end
