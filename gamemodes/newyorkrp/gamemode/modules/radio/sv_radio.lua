local R = NYRP.Radio
local Inv = NYRP.Inv
local T = NYRP.Chat.Types

local function radioItem(ply)
	local inv = Inv.Get(ply)
	local it = inv.equip and inv.equip.radio
	if it and it.id == "radio" then return it end
end
R.Item = radioItem

local function apply(ply)
	local it = radioItem(ply)
	if not it then
		ply:SetNW2Float("nyrp.radioFreq", 0)
		ply:SetNW2Bool("nyrp.radioTx", false)
		return
	end
	it.data = it.data or {}
	it.data.freq = R.Clamp(it.data.freq or 150)
	ply:SetNW2Float("nyrp.radioFreq", it.data.on == false and 0 or it.data.freq)
	ply:SetNW2Float("nyrp.radioSet", it.data.freq)
end
hook.Add("NYRP.EquipmentApplied", "nyrp.radio", function(...) apply(...) end)

net.Receive("nyrp.radio.set", function(_, ply)
	if (ply.nyrpRadioNext or 0) > CurTime() then return end
	ply.nyrpRadioNext = CurTime() + 0.2
	local freq, on = net.ReadFloat(), net.ReadBool()
	local it = radioItem(ply)
	if not it then NYRP.Notify(ply, "Наденьте рацию в слот «Рация»", "warning") return end
	it.data = it.data or {}
	it.data.freq = R.Clamp(freq)
	it.data.on = on
	apply(ply)
	Inv.Sync(ply)
	ply:EmitSound("buttons/button16.wav", 45, 140)
end)

-- передача голосом: держит ПКМ с рацией в руке (SWEP ставит nyrp.radioTx)
function R.SetTx(ply, tx)
	if tx and R.Freq(ply) <= 0 then return end
	if R.Transmitting(ply) == tx then return end
	ply:SetNW2Bool("nyrp.radioTx", tx)
end

local function sameFreq(a, b)
	local fa, fb = R.Freq(a), R.Freq(b)
	return fa > 0 and math.abs(fa - fb) < 0.05
end
R.SameFreq = sameFreq

hook.Add("PlayerCanHearPlayersVoice", "nyrp.radio", function(listener, talker)
	if listener ~= talker and R.Transmitting(talker) and talker:Alive() and listener:Alive() and sameFreq(talker, listener)
		and not (NYRP.Cond and NYRP.Cond.KO(listener)) then
		return true, false
	end
end)

hook.Add("PlayerDeath", "nyrp.radio", function(ply) ply:SetNW2Bool("nyrp.radioTx", false) end)

-- /r текст
local function say(ply, raw)
	local text = string.Trim(string.match(raw, "^%S+%s*(.*)$") or "")
	if text == "" then return end
	if not NYRP.HasCharacter(ply) or not ply:Alive() then return end
	if not radioItem(ply) then NYRP.Notify(ply, "У вас нет рации (слот «Рация»)", "warning") return end
	if R.Freq(ply) <= 0 then NYRP.Notify(ply, "Рация выключена", "warning") return end
	local f = R.Format(R.Freq(ply))
	local listeners, near = {}, {}
	local range = NYRP.Chat.Range(T.IC)
	for _, p in ipairs(player.GetAll()) do
		if p == ply or (sameFreq(ply, p) and p:Alive()) then
			listeners[#listeners + 1] = p
		elseif p:GetPos():DistToSqr(ply:GetPos()) <= range * range then
			near[#near + 1] = p
		end
	end
	NYRP.Chat.Send(listeners, T.RADIO, ply, f .. "\n" .. text)
	if #near > 0 then NYRP.Chat.Send(near, T.RADIO, ply, "near\n" .. text) end
	ply:EmitSound("nyrp/fx/radio_on.wav", 50)
	NYRP.Print(string.format("[рация %s] %s (%s): %s", f, ply:Nick(), NYRP.CharName(ply), text))
end
NYRP.Chat.AddCommand("/r", say)
NYRP.Chat.AddCommand("/р", say)
NYRP.Chat.AddCommand("/radio", say)
