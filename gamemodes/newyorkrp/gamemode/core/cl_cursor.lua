--[[
	Свой курсор везде: системный курсор у всех панелей заменяется на «blank»,
	а наш рисуется поверх всего в DrawOverlay. Тип (стрелка / рука / текст) берётся из того,
	что панель запросила через SetCursor.
]]

local meta = FindMetaTable("Panel")
local origSetCursor = meta.NYRPOrigSetCursor or meta.SetCursor
meta.NYRPOrigSetCursor = origSetCursor

function meta:SetCursor(kind)
	self.NYRPCursor = kind
	origSetCursor(self, "blank")
end

local function hide(pnl)
	if IsValid(pnl) then origSetCursor(pnl, "blank") end
	return pnl
end

local origCreate = vgui.NYRPOrigCreate or vgui.Create
vgui.NYRPOrigCreate = origCreate
function vgui.Create(...)
	return hide(origCreate(...))
end

local origFromTable = vgui.NYRPOrigCreateFromTable or vgui.CreateFromTable
vgui.NYRPOrigCreateFromTable = origFromTable
function vgui.CreateFromTable(...)
	return hide(origFromTable(...))
end

hook.Add("Initialize", "nyrp.cursor", function()
	hide(vgui.GetWorldPanel())
	hide(GetHUDPanel and GetHUDPanel())
end)
hook.Add("InitPostEntity", "nyrp.cursor", function()
	hide(vgui.GetWorldPanel())
end)

local kinds = {
	hand = "hand", sizeall = "hand", sizewe = "hand", sizens = "hand", sizenwse = "hand", sizenesw = "hand",
	beam = "text", ibeam = "text",
}

local function cursorKind()
	local pnl = vgui.GetHoveredPanel()
	while IsValid(pnl) do
		if pnl.NYRPCursor and pnl.NYRPCursor ~= "arrow" and pnl.NYRPCursor ~= "none" then
			return kinds[pnl.NYRPCursor] or "arrow"
		end
		if pnl.NYRPCursor == "arrow" then return "arrow" end
		pnl = pnl:GetParent()
	end
	return "arrow"
end

local scale = 1
local lastKind = "arrow"
hook.Add("DrawOverlay", "nyrp.cursor", function()
	if not vgui.CursorVisible() or gui.IsGameUIVisible() then return end
	local x, y = input.GetCursorPos()
	local kind = cursorKind()
	if kind ~= lastKind then scale = 0.82 lastKind = kind end
	scale = NYRP.UI.Approach(scale, input.IsMouseDown(MOUSE_LEFT) and 0.88 or 1, 18)
	local size = math.Round(NYRP.UI.S(30) * scale)
	surface.SetMaterial(NYRP.UI.Mat("nyrp/cursor/" .. kind .. ".png"))
	surface.SetDrawColor(255, 255, 255, 255)
	if kind == "text" then
		surface.DrawTexturedRect(x - size / 2, y - size / 2, size, size)
	else
		surface.DrawTexturedRect(x - size * 0.06, y - size * 0.04, size, size)
	end
end)
