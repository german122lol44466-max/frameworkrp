--[[
	Сесть: Alt + E (держать Alt и нажать E) на стул, скамейку, диван, край стола, ступеньку —
	любую горизонтальную поверхность на высоте до ~40 ед. Если смотреть себе под ноги — сесть на пол.
	Встать — Пробел или ещё раз Alt + E.
	Анимации — из общих анимаций игроков (models/m_anm.mdl, f_anm.mdl): ACT_HL2MP_SIT (sit, с оружием —
	sit_pistol, sit_smg1 ...) и sit_zen (на полу). Они есть у всех моделей игроков, подключающих эти анимации.
]]
NYRP.Sit = NYRP.Sit or {}
local S = NYRP.Sit

function S.Sitting(ply) return ply:GetNW2Bool("nyrp.sit") end
function S.Ground(ply) return ply:GetNW2Bool("nyrp.sitGround") end

hook.Add("CalcMainActivity", "nyrp.sit", function(ply)
	if not S.Sitting(ply) then return end
	if S.Ground(ply) then
		local seq = ply:LookupSequence("sit_zen")
		if seq and seq >= 0 then return ACT_HL2MP_SIT, seq end
	end
	return ACT_HL2MP_SIT, -1
end)

-- сидя — не ходим, не прыгаем, не приседаем
hook.Add("SetupMove", "nyrp.sit", function(ply, mv, cmd)
	if not S.Sitting(ply) then return end
	mv:SetForwardSpeed(0)
	mv:SetSideSpeed(0)
	mv:SetUpSpeed(0)
	mv:SetVelocity(vector_origin)
	mv:SetButtons(bit.band(mv:GetButtons(), bit.bnot(bit.bor(IN_DUCK, IN_SPEED))))
end)
