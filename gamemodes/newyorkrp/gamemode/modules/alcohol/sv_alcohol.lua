--[[
	Опьянение на сервере: всасывание выпитого, трезвение, падения при тяжёлом опьянении,
	искажение речи в IC-чате, вода/кофе ускоряют трезвение, сохранение в c.flags.drunk.
]]

NYRP.Alcohol = NYRP.Alcohol or {}
local A = NYRP.Alcohol

local function setLevel(ply, v)
	v = math.Clamp(v, 0, A.Max)
	ply:SetNW2Float("nyrp.drunk", v)
	local c = ply.nyrpChar
	if c and c.flags then c.flags.drunk = v > 0.5 and math.Round(v, 1) or nil end
end
A.Set = setLevel

-- выпить: amount единиц всасывается постепенно (за несколько секунд)
function A.Drink(ply, amount)
	ply.nyrpAlcPending = (ply.nyrpAlcPending or 0) + amount
	local c = ply.nyrpChar
	if c and c.flags then c.flags.drinks = (c.flags.drinks or 0) + 1 end
	hook.Run("NYRP.AlcoholDrunk", ply, amount)
	-- предупреждение, когда выпито уже много
	local total = A.Level(ply) + ply.nyrpAlcPending
	if total >= 80 and (ply.nyrpAlcWarn or 0) < CurTime() then
		ply.nyrpAlcWarn = CurTime() + 60
		NYRP.Notify(ply, "Кажется, это уже лишнее… Ноги не держат.", "warning", 5)
	end
end

-- ------------------------------------------------------------ каждую секунду --
timer.Create("nyrp.alcohol", 1, 0, function()
	local Cond = NYRP.Cond
	for _, ply in ipairs(player.GetAll()) do
		local pend = ply.nyrpAlcPending or 0
		local lvl = A.Level(ply)
		if pend > 0 or lvl > 0 then
			local take = math.min(pend, A.Absorb)
			ply.nyrpAlcPending = pend - take
			lvl = lvl + take - A.SoberRate
			setLevel(ply, lvl)
			-- тяжёлое опьянение: можно рухнуть
			if lvl >= 80 and ply:Alive() and ply:OnGround() and not ply:InVehicle() and Cond and Cond.Fall
				and not (Cond.KO and Cond.KO(ply)) and not ply:GetNW2Bool("nyrp.sit") then
				local moving = ply:GetVelocity():Length2D() > 40
				local chance = (lvl - 75) / 25 * (moving and 0.06 or 0.02)
				if (ply.nyrpAlcFallNext or 0) < CurTime() and math.random() < chance then
					ply.nyrpAlcFallNext = CurTime() + 20
					Cond.Fall(ply, false, 3 + (lvl - 80) / 5)
					local near = {}
					for _, p in ipairs(player.GetAll()) do
						if p:GetPos():DistToSqr(ply:GetPos()) < 500 * 500 then near[#near + 1] = p end
					end
					if NYRP.Chat and NYRP.Chat.Send then NYRP.Chat.Send(near, NYRP.Chat.Types.ME, ply, "спотыкается на ровном месте и падает") end
				end
			end
		end
	end
end)

-- вода и кофе помогают протрезветь
local SOBER = { water = 10, coffee = 15, soda = 5, milk = 6 }
hook.Add("NYRP.ItemUsed", "nyrp.alcohol", function(ply, id)
	local s = SOBER[id]
	if not s then return end
	local had = A.Level(ply) + (ply.nyrpAlcPending or 0)
	if had <= 0 then return end
	ply.nyrpAlcPending = (ply.nyrpAlcPending or 0) * 0.7
	setLevel(ply, A.Level(ply) - s)
	if A.Level(ply) >= 15 then NYRP.Notify(ply, "Немного полегчало", "info", 3) end
end)

hook.Add("PlayerDeath", "nyrp.alcohol", function(ply)
	ply.nyrpAlcPending = 0
	setLevel(ply, 0)
end)

hook.Add("NYRP.CharacterLoaded", "nyrp.alcohol", function(ply, c)
	ply.nyrpAlcPending = 0
	ply:SetNW2Float("nyrp.drunk", math.Clamp(tonumber(c.flags and c.flags.drunk) or 0, 0, A.Max))
end)

-- -------------------------------------------------------------- речь --
local REPL = {
	["с"] = "ш", ["С"] = "Ш", ["з"] = "ж", ["З"] = "Ж", ["ц"] = "ш", ["ч"] = "щ",
	["s"] = "sh", ["S"] = "Sh", ["z"] = "zh",
}
local VOWEL = { ["а"] = true, ["о"] = true, ["у"] = true, ["э"] = true, ["ы"] = true, ["е"] = true, ["я"] = true, ["и"] = true,
	["a"] = true, ["o"] = true, ["u"] = true, ["e"] = true }

function A.Slur(text, lvl)
	local k = math.Clamp((lvl - 50) / 50, 0, 1)
	if k <= 0 then return text end
	local out = {}
	for _, code in utf8.codes(text) do
		local ch = utf8.char(code)
		if REPL[ch] and math.random() < 0.55 * k + 0.15 then
			ch = REPL[ch]
		elseif VOWEL[ch] and math.random() < 0.2 * k then
			ch = ch .. ch
		elseif ch == " " and math.random() < 0.1 + 0.15 * k then
			ch = math.random() < 0.5 and " *ик* " or "... "
		end
		out[#out + 1] = ch
	end
	local s = table.concat(out)
	if math.random() < 0.3 + 0.4 * k then s = s .. "... *ик*" end
	return s
end

hook.Add("PlayerSay", "nyrp.alcohol", function(ply, raw)
	if not ply.nyrpInternalSay or not IsValid(ply) then return end
	local lvl = A.Level(ply)
	if lvl < 55 then return end
	local Chat = NYRP.Chat
	if not Chat or not Chat.Parse then return end
	local kind, text = Chat.Parse(raw)
	local T = Chat.Types
	if kind ~= T.IC and kind ~= T.WHISPER and kind ~= T.YELL then return end
	if text == "" or (kind == T.IC and string.sub(raw, 1, 1) == "/") then return end
	-- префикс (/w, /y …) сохраняем, искажаем только текст
	local prefix = ""
	if #raw > #text and string.sub(raw, -#text) == text then prefix = string.sub(raw, 1, #raw - #text) end
	return prefix .. A.Slur(text, lvl)
end)

-- ---------------------------------------------------------------- админ --
local function cmd(name, fn)
	if NYRP.Chat and NYRP.Chat.AddCommand then NYRP.Chat.AddCommand(name, fn) return end
	timer.Simple(0, function() NYRP.Chat.AddCommand(name, fn) end)
end

cmd("/sober", function(ply, raw)
	if not ply:IsAdmin() then return end
	local part = string.lower(string.Trim(string.match(raw, "^%S+%s*(.*)$") or ""))
	local target = ply
	if part ~= "" then
		target = nil
		for _, p in ipairs(player.GetAll()) do
			if string.find(string.lower(p:Nick()), part, 1, true) or string.find(string.lower(NYRP.CharName(p) or ""), part, 1, true) then target = p break end
		end
	end
	if not IsValid(target) then NYRP.Notify(ply, "Игрок не найден", "error") return end
	target.nyrpAlcPending = 0
	setLevel(target, 0)
	NYRP.Notify(ply, "Протрезвлён: " .. NYRP.CharName(target), "success")
end)
