local S = NYRP.Smoking

function S.PutInMouth(ply)
	if S.State(ply) > 0 then NYRP.Notify(ply, "Сигарета уже во рту", "warning") return false end
	ply:SetNW2Int("nyrp.cig", 1)
	ply:AnimRestartGesture(GESTURE_SLOT_CUSTOM, ACT_GMOD_GESTURE_ITEM_PLACE, true)
	NYRP.Notify(ply, "Сигарета во рту. Подкурите зажигалкой: слот «В руке», ЛКМ.", "item", 4)
	return true
end

function S.Light(ply)
	if S.State(ply) ~= 1 then return false end
	ply:SetNW2Int("nyrp.cig", 2)
	ply:SetNW2Float("nyrp.cigEnd", CurTime() + S.BurnTime)
	ply.nyrpNextPuff = CurTime() + 3
	return true
end

function S.Remove(ply, finished)
	if S.State(ply) == 0 then return end
	local wasLit = S.Lit(ply)
	ply:SetNW2Int("nyrp.cig", 0)
	if finished and wasLit then
		ply:SetNW2Float("nyrp.thirst", math.max(0, ply:GetNW2Float("nyrp.thirst", 100) - 5))
		ply:SetHealth(math.max(1, ply:Health() - 2))
		NYRP.Notify(ply, "Сигарета догорела", "item", 3)
	end
end

-- затяжки: дым и звук у всех рядом (эффект рисует клиент по net), кашель
timer.Create("nyrp.smoking", 1, 0, function()
	for _, ply in ipairs(player.GetAll()) do
		if S.Lit(ply) and not ply:Alive() then
			S.Remove(ply)
		elseif S.Lit(ply) and CurTime() >= ply:GetNW2Float("nyrp.cigEnd", 0) then
			S.Remove(ply, true)
		elseif S.Lit(ply) then
			-- бафф: выносливость восстанавливается быстрее
			ply:SetNW2Float("nyrp.stamina", math.min(100, ply:GetNW2Float("nyrp.stamina", 100) + 1.5))
			if CurTime() >= (ply.nyrpNextPuff or 0) then
				ply.nyrpNextPuff = CurTime() + math.Rand(7, 11)
				ply:EmitSound("nyrp/fx/smoke_inhale.wav", 50, math.random(95, 105), 0.6)
				timer.Simple(1.5, function()
					if not IsValid(ply) or not S.Lit(ply) then return end
					ply:EmitSound("nyrp/fx/smoke_exhale.wav", 50, math.random(95, 105), 0.6)
					net.Start("nyrp.smoke.puff") net.WriteEntity(ply) net.SendPVS(ply:GetPos())
					if math.random() < 0.12 then
						timer.Simple(0.8, function()
							if IsValid(ply) and ply:Alive() then
								local c = ply.nyrpChar
								ply:EmitSound("nyrp/fx/cough.wav", 62, c and c.gender == "female" and 120 or 100)
								ply:AnimRestartGesture(GESTURE_SLOT_CUSTOM, ACT_GMOD_GESTURE_DISAGREE, true)
							end
						end)
					end
				end)
			end
		end
	end
end)

hook.Add("PlayerDeath", "nyrp.smoking", function(ply) S.Remove(ply) end)
hook.Add("NYRP.CharacterLoaded", "nyrp.smoking", function(ply) S.Remove(ply) end)

-- выбросить сигарету изо рта (C-меню)
net.Receive("nyrp.smoke.drop", function(_, ply)
	if S.State(ply) == 0 then return end
	S.Remove(ply)
	ply:EmitSound("physics/cardboard/cardboard_box_impact_soft1.wav", 45, 160)
end)

-- зажигалка: тратим газ у надетой зажигалки
function S.UseLighter(ply)
	local inv = NYRP.Inv.Get(ply)
	local it = inv.equip and inv.equip.tool
	if not it or it.id ~= "lighter" then return false end
	local def = NYRP.Items.Get("lighter")
	it.data = it.data or {}
	it.data.uses = (it.data.uses or def.uses or 40) - 1
	if it.data.uses <= 0 then
		inv.equip.tool = nil
		if ply:HasWeapon("nyrp_lighter") then ply:StripWeapon("nyrp_lighter") end
		NYRP.Notify(ply, "В зажигалке кончился газ", "warning")
	end
	NYRP.Inv.Sync(ply)
	return true
end
