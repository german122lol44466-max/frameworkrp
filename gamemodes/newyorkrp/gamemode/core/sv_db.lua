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
