--[[
	Панель настроек — используется в инвентаре (шестерёнка) и в меню паузы.
	NYRP.UI.BuildSettings(parent) заполняет parent элементами.
]]

local UI = NYRP.UI

function UI.BuildSettings(parent)
	local scroll = vgui.Create("NYRP.Scroll", parent)
	scroll:Dock(FILL)
	local function section(title)
		local l = scroll:Add("DPanel")
		l:Dock(TOP)
		l:SetTall(UI.S(38))
		l:DockMargin(0, UI.S(8), 0, 0)
		l.Paint = function(_, w, h)
			draw.SimpleText(string.upper(title), NYRP.Font("title", 16), 0, h - UI.S(6), UI.Col.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
			surface.SetDrawColor(255, 255, 255, 14)
			surface.DrawRect(0, h - 1, w, 1)
		end
	end
	local function add(class, setup)
		local p = scroll:Add(class)
		p:Dock(TOP)
		p:DockMargin(0, UI.S(6), UI.S(8), 0)
		setup(p)
		return p
	end

	section("Звук")
	add("NYRP.Slider", function(p)
		p:SetLabel("Громкость музыки")
		p:SetMinMax(0, 1)
		p:SetPercent(true)
		p:SetConVar("nyrp_music_volume")
	end)
	add("NYRP.Toggle", function(p) p:SetLabel("Звуки интерфейса") p:SetConVar("nyrp_ui_sounds") end)

	section("Интерфейс")
	add("NYRP.Toggle", function(p)
		p:SetLabel("Инвентарь на одной странице")
		p:SetDescription("Сумка, одежда и оружие в одном окне")
		p:SetConVar("nyrp_inv_combined")
		p.OnChange = function() if NYRP.Inventory and NYRP.Inventory.Rebuild then NYRP.Inventory.Rebuild() end end
	end)

	section("Камера")
	add("NYRP.Toggle", function(p) p:SetLabel("Третье лицо") p:SetConVar("nyrp_thirdperson") end)
	return scroll
end
