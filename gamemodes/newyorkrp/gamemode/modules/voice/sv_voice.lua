--[[
	Голосовой чат по дистанции (3D-звук).
	Ничего не отключаем у движка: возвращаем явные значения, иначе войс «ломается».
]]

function GM:PlayerCanHearPlayersVoice(listener, talker)
	if listener == talker then return false, false end
	if not NYRP.HasCharacter(talker) or not talker:Alive() then return false, false end
	local range = NYRP.Config.Ranges.Voice
	if listener:GetPos():DistToSqr(talker:GetPos()) > range * range then return false, false end
	return true, true
end

hook.Add("Initialize", "nyrp.voice", function()
	RunConsoleCommand("sv_voiceenable", "1")
	-- стандартный значок над головой рисует движок — у нас свой
	if ConVarExists("mp_show_voice_icons") then RunConsoleCommand("mp_show_voice_icons", "0") end
end)
