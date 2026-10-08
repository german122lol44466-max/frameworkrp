--[[
	Хранилище: SQLite (sv.db) сервера Garry's Mod.
]]

NYRP.DB = NYRP.DB or {}

local function q(str)
	local res = sql.Query(str)
	if res == false then
		NYRP.Print("SQL ошибка: " .. tostring(sql.LastError()) .. " в запросе: " .. str)
	end
	return res
end
NYRP.DB.Query = q

function NYRP.DB.Escape(v)
	return sql.SQLStr(tostring(v))
end

q([[CREATE TABLE IF NOT EXISTS nyrp_players (
	steamid TEXT PRIMARY KEY,
	playtime INTEGER DEFAULT 0,
	last_char INTEGER DEFAULT 0
)]])

q([[CREATE TABLE IF NOT EXISTS nyrp_characters (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	steamid TEXT,
	name TEXT,
	description TEXT,
	gender TEXT,
	model TEXT,
	height INTEGER,
	skills TEXT,
	bag TEXT,
	inventory TEXT,
	equipment TEXT,
	hunger REAL DEFAULT 100,
	thirst REAL DEFAULT 100,
	health INTEGER DEFAULT 100,
	recognized TEXT DEFAULT '[]',
	created INTEGER,
	flags TEXT DEFAULT '{}'
)]])

-- Миграция: таблица могла быть создана старой версией режима без новых столбцов —
-- тогда сохранение персонажа молча падало и после перезапуска всё сбрасывалось.
do
	local need = {
		nyrp_characters = {
			{ "skills", "TEXT DEFAULT '{}'" }, { "bag", "TEXT DEFAULT 'waistbag'" }, { "inventory", "TEXT DEFAULT '[]'" },
			{ "equipment", "TEXT DEFAULT '{}'" }, { "hunger", "REAL DEFAULT 100" }, { "thirst", "REAL DEFAULT 100" },
			{ "health", "INTEGER DEFAULT 100" }, { "recognized", "TEXT DEFAULT '[]'" }, { "created", "INTEGER" },
			{ "flags", "TEXT DEFAULT '{}'" },
		},
		nyrp_players = { { "playtime", "INTEGER DEFAULT 0" }, { "last_char", "INTEGER DEFAULT 0" } },
	}
	for tbl, cols in pairs(need) do
		local have = {}
		local rows = sql.Query("PRAGMA table_info(" .. tbl .. ")")
		if type(rows) ~= "table" then rows = {} end
		for i = 1, #rows do
			local r = rows[i]
			if type(r) == "table" and type(r.name) == "string" then have[r.name] = true end
		end
		for _, c in ipairs(cols) do
			if not have[c[1]] then
				q("ALTER TABLE " .. tbl .. " ADD COLUMN " .. c[1] .. " " .. c[2])
				NYRP.Print("БД: добавлен столбец " .. tbl .. "." .. c[1])
			end
		end
	end
end
