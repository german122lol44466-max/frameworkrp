--[[
	Меню тела (E по человеку без сознания или трупу): проверить пульс, помочь встать,
	оказать первую помощь (нужна аптечка/обезболивающее). Всё — с прогресс-баром на сервере.
]]

local I = NYRP.Interact

local function hasMed()
	for _, it in pairs(NYRP.Inventory.Data.slots or {}) do
		if it.id == "medkit" or it.id == "painkillers" then return true end
	end
end

function I.OpenBodyMenu(rag)
	local owner = rag:GetNW2Entity("nyrp.koOwner")
	local dead = rag:GetNW2Bool("nyrp.corpse")
	local crit = rag:GetNW2Bool("nyrp.koCritical")
	local opts = {
		{ id = "pulse", name = "Проверить пульс", icon = "heart" },
		{ id = "lift", name = "Помочь встать", icon = "user",
			disabled = dead or crit, note = dead and "Человек мёртв" or "Не может встать — нужна первая помощь" },
		{ id = "treat", name = "Первая помощь", icon = "medkit",
			disabled = dead or not crit or not hasMed(),
			note = dead and "Человек мёртв" or (not crit and "Человек и так в порядке" or "Нужна аптечка или обезболивающее") },
	}
	NYRP.WorldRadial.Open({
		anchor = function() return IsValid(rag) and I.Anchor(rag) end,
		valid = function() return IsValid(rag) and rag:NearestPoint(EyePos()):Distance(EyePos()) <= 140 end,
		options = opts,
		onSelect = function(opt)
			net.Start("nyrp.body.act")
			net.WriteString(opt.id)
			net.WriteEntity(rag)
			net.SendToServer()
		end,
	})
end
