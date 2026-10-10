--[[
	Ежедневный бонус на сервере: расчёт серии по реальным суткам (время сервера), выплата наличными.
]]

NYRP.Daily = NYRP.Daily or {}
local D = NYRP.Daily

-- номер реальных суток по местному времени сервера
function D.Today()
	local t = os.date("*t")
	return math.floor(os.time({ year = t.year, month = t.month, day = t.day, hour = 12 }) / 86400)
end

local function state(ply)
	local c = ply.nyrpChar
	if not c then return end
	c.flags = c.flags or {}
	c.flags.daily = c.flags.daily or { day = 0, streak = 0 }
	return c.flags.daily
end

-- какой день серии будет при получении сегодня (1..7), и доступна ли награда
function D.Next(ply)
	local s = state(ply)
	if not s then return 1, false end
	local today = D.Today()
	if s.day == today then return s.streak, false end
	if s.day == today - 1 and s.streak < #D.Rewards then return s.streak + 1, true end
	return 1, true
end

function D.Send(ply, open)
	local s = state(ply)
	if not s then return end
	local day, avail = D.Next(ply)
	-- серия прервалась — показываем, сколько было
	local broken = avail and day == 1 and s.day > 0 and s.day < D.Today() - 1 and s.streak > 0
	net.Start("nyrp.daily")
	net.WriteUInt(day, 4)
	net.WriteBool(avail)
	net.WriteBool(broken and true or false)
	net.WriteBool(open and true or false)
	net.Send(ply)
end

net.Receive("nyrp.daily.claim", function(_, ply)
	if (ply.nyrpDailyNext or 0) > CurTime() then return end
	ply.nyrpDailyNext = CurTime() + 1
	if not NYRP.HasCharacter(ply) then return end
	local day, avail = D.Next(ply)
	if not avail then D.Send(ply, false) return end
	local s = state(ply)
	s.day, s.streak = D.Today(), day
	local reward = D.Rewards[day] or D.Rewards[1]
	NYRP.Money.Add(ply, reward)
	NYRP.Chars.Save(ply)
	ply:EmitSound("nyrp/fx/cash.wav", 55)
	NYRP.Notify(ply, "Ежедневный бонус, день " .. day .. ": +" .. NYRP.Money.Format(reward) .. (day < #D.Rewards and ". Заходите завтра!" or ". Серия завершена!"), "success", 6)
	hook.Run("NYRP.DailyClaimed", ply, day)
	D.Send(ply, false)
end)

-- при входе (после пробуждения персонажа) — окно, если бонус доступен
hook.Add("NYRP.CharacterLoaded", "nyrp.daily", function(ply)
	timer.Simple(9, function()
		if not IsValid(ply) or not NYRP.HasCharacter(ply) then return end
		local _, avail = D.Next(ply)
		D.Send(ply, avail)
	end)
end)

-- в игре наступили новые сутки — напомнить
timer.Create("nyrp.daily.remind", 600, 0, function()
	for _, ply in ipairs(player.GetAll()) do
		if NYRP.HasCharacter(ply) then
			local _, avail = D.Next(ply)
			if avail and ply.nyrpDailyReminded ~= D.Today() then
				ply.nyrpDailyReminded = D.Today()
				NYRP.Notify(ply, "Доступен ежедневный бонус: /daily", "info", 8)
			end
		end
	end
end)

local function cmd(name, fn)
	if NYRP.Chat and NYRP.Chat.AddCommand then NYRP.Chat.AddCommand(name, fn) return end
	timer.Simple(0, function() NYRP.Chat.AddCommand(name, fn) end)
end
local function open(ply) if NYRP.HasCharacter(ply) then D.Send(ply, true) end end
cmd("/daily", open)
cmd("/бонус", open)
