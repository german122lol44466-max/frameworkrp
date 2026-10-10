--[[
	Механики служб.
	  Все службы: терминал (nyrp_terminal: устав из framework/charters/<роль>.txt, вызовы 911, кто на смене),
	              шкаф снаряжения (nyrp_armory: выдаёт ROLE.Items раз в 10 минут),
	              служебные двери (/doorfaction <роль|off> — открывают только сотрудники).
	  NYPD: наручники (ЛКМ — надеть, ПКМ — вести/отпустить, R — снять), розыск и штрафы в терминале.
	  EMS:  дефибриллятор (ЛКМ по телу — реанимация, если смерть была не больше 30 с назад), больничная койка,
	        автоматический вызов скорой к человеку в критическом состоянии, список пострадавших в терминале.
	  FDNY: пожары (nyrp_fire: растут и распространяются, обжигают; /fire — поджечь, случайные пожары, если пожарные на смене),
	        огнетушитель (держать ЛКМ, заправка у гидранта), список пожаров в терминале.
	Ставит админ: спавн-меню (вкладка Entities → New-York Roleplay) или /terminal <роль>, /armory <роль>, /bed.
]]
NYRP.Factions = NYRP.Factions or {}
local F = NYRP.Factions

function F.Cuffed(ply) return ply:GetNW2Bool("nyrp.cuffed") end

-- в наручниках: медленно, без бега и прыжков
hook.Add("SetupMove", "nyrp.cuffs", function(ply, mv)
	if not F.Cuffed(ply) then return end
	mv:SetMaxClientSpeed(math.min(mv:GetMaxClientSpeed(), ply:GetWalkSpeed() * 0.6))
	mv:SetButtons(bit.band(mv:GetButtons(), bit.bnot(bit.bor(IN_JUMP, IN_SPEED, IN_ATTACK, IN_ATTACK2))))
end)
