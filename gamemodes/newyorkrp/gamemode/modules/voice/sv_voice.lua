--[[
	Голосовой чат по дистанции (3D-звук), дальность — по режиму игрока (шёпот/голос/крик).
	Ничего не отключаем у движка: возвращаем явные значения, иначе войс «ломается».
]]

local V = NYRP.Voice

function GM:PlayerCanHearPlayersVoice(listener, talker)
	if listener == talker then return false, false end
	if not NYRP.HasCharacter(talker) or not talker:Alive() then return false, false end
	if NYRP.Cond and NYRP.Cond.KO(talker) then return false, false end
	local range = V.Range(talker)
	if listener:GetPos():DistToSqr(talker:GetPos()) > range * range then return false, false end
	return true, true
end

net.Receive("nyrp.voice.mode", function(_, ply)
	local m = net.ReadUInt(4)
	if V.Modes[m] then ply:SetNW2Int("nyrp.voiceMode", m) end
end)

hook.Add("Initialize", "nyrp.voice", function()
	RunConsoleCommand("sv_voiceenable", "1")
	-- стандартный значок над головой рисует движок — у нас свой
	if ConVarExists("mp_show_voice_icons") then RunConsoleCommand("mp_show_voice_icons", "0") end
end)
