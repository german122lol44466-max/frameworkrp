--[[
	Дежурство служб: заступить — кнопка в служебном компьютере. На дежурстве рация сама настраивается
	на частоту службы (ROLE.Radio), каждые 10 минут — доплата ROLE.DutyPay, сотрудника видно в списке «На смене».
]]
local F = NYRP.Factions

function F.SetDuty(ply, on)
	local r = NYRP.Roles.List[ply:GetNW2String("nyrp.role", "")]
	if on and (not r or not r.Service) then on = false end
	ply:SetNW2Bool("nyrp.onDuty", on and true or false)
	if not on then
		NYRP.Notify(ply, "Дежурство окончено", "info")
		return
	end
	local Inv = NYRP.Inv
	local it = NYRP.Radio and NYRP.Radio.Item and NYRP.Radio.Item(ply)
	if r.Radio and it then
		it.data = it.data or {}
		it.data.freq = r.Radio
		it.data.on = true
		hook.Run("NYRP.EquipmentApplied", ply, Inv.Get(ply))
		Inv.Sync(ply)
		ply:EmitSound("nyrp/fx/radio_on.wav", 45)
		NYRP.Notify(ply, "Вы на дежурстве. Рация: " .. string.format("%.1f", r.Radio) .. " МГц", "success", 5)
	else
		NYRP.Notify(ply, "Вы на дежурстве" .. (r.Radio and (". Наденьте рацию — частота службы " .. string.format("%.1f", r.Radio)) or ""), "success", 5)
	end
end

hook.Add("NYRP.RoleChanged", "nyrp.duty", function(ply) ply:SetNW2Bool("nyrp.onDuty", false) end)
hook.Add("PlayerDisconnected", "nyrp.duty", function(ply) ply:SetNW2Bool("nyrp.onDuty", false) end)

timer.Create("nyrp.duty.pay", 600, 0, function()
	for _, p in ipairs(player.GetAll()) do
		if p:GetNW2Bool("nyrp.onDuty") and p:Alive() then
			local r = NYRP.Roles.List[p:GetNW2String("nyrp.role", "")]
			local pay = r and r.DutyPay or 0
			if pay > 0 then
				NYRP.Money.Add(p, pay)
				NYRP.Notify(p, "Доплата за дежурство: +" .. NYRP.Money.Format(pay), "success")
			end
		end
	end
end)
