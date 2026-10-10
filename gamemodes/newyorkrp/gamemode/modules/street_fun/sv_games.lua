--[[
	Кости, монетка и карты (сервер).
	  /roll [макс] (/ролл) — случайное число 1..макс (по умолчанию 100, до 1 000 000);
	  /coin (/монетка) — орёл или решка;  /dice (/кости) — два шестигранных кубика;
	  колода карт (предмет «Колода карт», ПКМ «Вытянуть карту») — карта из колоды; кончилась — тасуется заново.
	Результат видят все в радиусе обычной речи: строка в чате (как /me) и картинка над головой на 5 секунд.
]]

NYRP.StreetFun = NYRP.StreetFun or {}
local SF = NYRP.StreetFun
local Chat = NYRP.Chat

local function nearby(ply)
	local range = NYRP.Config.Ranges.Say
	local out = {}
	for _, p in ipairs(player.GetAll()) do
		if p:GetPos():DistToSqr(ply:GetPos()) <= range * range then out[#out + 1] = p end
	end
	return out
end

local function canPlay(ply)
	if not NYRP.HasCharacter(ply) or not ply:Alive() then return false end
	if (ply.nyrpFunNext or 0) > CurTime() then
		NYRP.Notify(ply, "Не так быстро", "warning", 2)
		return false
	end
	ply.nyrpFunNext = CurTime() + 2
	return true
end

-- показать результат: чат (/me) + картинка над головой
function SF.Show(ply, kind, a, b, text)
	local rec = nearby(ply)
	Chat.Send(rec, Chat.Types.ME, ply, text)
	net.Start("nyrp.fun.show")
	net.WriteEntity(ply)
	net.WriteString(kind)
	net.WriteUInt(a or 0, 32)
	net.WriteUInt(b or 0, 32)
	net.Send(rec)
end

local function roll(ply, raw)
	if not canPlay(ply) then return end
	local max = math.floor(tonumber(string.match(raw, "^%S+%s+(%d+)") or "") or 100)
	max = math.Clamp(max, 2, 1000000)
	local n = math.random(1, max)
	ply:EmitSound("physics/wood/wood_box_impact_soft" .. math.random(1, 3) .. ".wav", 55, 140)
	SF.Show(ply, "roll", n, max, "бросает кость (1–" .. max .. "): выпало " .. n)
end
Chat.AddCommand("/roll", roll)
Chat.AddCommand("/ролл", roll)

local function coin(ply)
	if not canPlay(ply) then return end
	local heads = math.random(2) == 1
	ply:EmitSound("nyrp/fx/money.wav", 50, 160)
	SF.Show(ply, "coin", heads and 1 or 2, 0, "подбрасывает монетку: " .. (heads and "орёл" or "решка"))
end
Chat.AddCommand("/coin", coin)
Chat.AddCommand("/монетка", coin)

local function dice(ply)
	if not canPlay(ply) then return end
	local a, b = math.random(6), math.random(6)
	ply:EmitSound("physics/wood/wood_box_impact_soft" .. math.random(1, 3) .. ".wav", 55, 160)
	SF.Show(ply, "dice", a, b, "бросает два кубика: " .. a .. " и " .. b .. " (сумма " .. (a + b) .. ")")
end
Chat.AddCommand("/dice", dice)
Chat.AddCommand("/кости", dice)

-- колода карт: оставшиеся карты хранятся в предмете (data.left)
function SF.DrawCard(ply, it)
	if not canPlay(ply) then return false end
	it.data = it.data or {}
	local left = it.data.left
	if type(left) ~= "table" or #left == 0 then
		left = {}
		for i = 1, 52 do left[i] = i end
		it.data.left = left
		ply:EmitSound("physics/cardboard/cardboard_box_impact_soft" .. math.random(1, 3) .. ".wav", 50, 150)
		Chat.Send(nearby(ply), Chat.Types.ME, ply, "тасует колоду карт")
	end
	local card = table.remove(left, math.random(#left))
	ply:AnimRestartGesture(GESTURE_SLOT_CUSTOM, ACT_GMOD_GESTURE_ITEM_GIVE, true)
	SF.Show(ply, "card", card, #left, "вытягивает карту: " .. SF.CardName(card) .. " (в колоде осталось " .. #left .. ")")
	NYRP.Inv.Sync(ply)
	return false   -- колода не тратится
end
