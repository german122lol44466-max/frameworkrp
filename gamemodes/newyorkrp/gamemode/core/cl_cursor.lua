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

-- Свободная мышь (gui.EnableScreenClicker): «пустой» курсор у панели мира заставляет движок снова
-- захватывать мышь под обзор. Поэтому свободная мышь — это невидимая панель на весь экран поверх игры:
-- курсор у неё наш, клики уходят в обычный хук GUIMousePressed/GUIMouseReleased, клавиатура остаётся у игры.
local origClicker = gui.NYRPOrigClicker or gui.EnableScreenClicker
gui.NYRPOrigClicker = origClicker
NYRP.ScreenClicker = NYRP.ScreenClicker or false
local catcher

function gui.EnableScreenClicker(on)
	NYRP.ScreenClicker = on and true or false
	origClicker(on)                         -- штатное освобождение мыши движком
	if on then
		if IsValid(catcher) then return end
		catcher = origCreate("EditablePanel")
		catcher:SetSize(ScrW(), ScrH())
		catcher:SetPos(0, 0)
		catcher:MakePopup()
		catcher:SetKeyboardInputEnabled(false)
		catcher:SetMouseInputEnabled(true)
		catcher:SetCursor("arrow")
		catcher.Paint = function() end
		catcher.OnMousePressed = function(_, code) hook.Run("GUIMousePressed", code, gui.ScreenToVector(gui.MousePos())) end
		catcher.OnMouseReleased = function(_, code) hook.Run("GUIMouseReleased", code, gui.ScreenToVector(gui.MousePos())) end
		catcher.OnMouseWheeled = function(_, delta) hook.Run("NYRP.MouseWheel", delta) end
		catcher.OnScreenSizeChanged = function(s) s:SetSize(ScrW(), ScrH()) end
	else
		if IsValid(catcher) then catcher:Remove() end
		catcher = nil
	end
end

function gui.NYRPCatcher() return catcher end

-- Сторож свободной мыши: если что-то (движок, другая панель, смена фокуса) снова захватило мышь,
-- пока она должна быть свободной, — возвращаем. Не чаще 4 раз в секунду, чтобы не мерцало.
local nextFix = 0
hook.Add("Think", "nyrp.cursor.keep", function()
	if not NYRP.ScreenClicker or gui.IsGameUIVisible() then return end
	if not IsValid(catcher) or not catcher:IsVisible() then
		if IsValid(catcher) then catcher:Remove() end
		catcher = nil
		gui.EnableScreenClicker(true)
		return
	end
end)

-- Если мышь всё же захвачена игрой, движения приходят сюда как повороты камеры —
-- это и есть признак «мышь пропала»: камеру не крутим и снова освобождаем курсор.
hook.Add("InputMouseApply", "nyrp.cursor.keep", function(cmd, x, y)
	if not NYRP.ScreenClicker or gui.IsGameUIVisible() then return end
	if (x ~= 0 or y ~= 0) and RealTime() > nextFix then
		nextFix = RealTime() + 0.5
		origClicker(false)
		origClicker(true)
	end
	cmd:SetMouseX(0)
	cmd:SetMouseY(0)
	return true
end)

-- Отладка: nyrp_debug_cursor 1 — кто держит мышь (видно на скриншоте).
local dbg = CreateClientConVar("nyrp_debug_cursor", "0", false, false)
hook.Add("PostRenderVGUI", "nyrp.cursor.debug", function()
	if not dbg:GetBool() then return end
	local hov = vgui.GetHoveredPanel()
	local foc = vgui.GetKeyboardFocus()
	local lines = {
		"ScreenClicker: " .. tostring(NYRP.ScreenClicker),
		"CursorVisible: " .. tostring(vgui.CursorVisible()),
		"catcher: " .. tostring(IsValid(catcher)) .. (IsValid(catcher) and (" visible=" .. tostring(catcher:IsVisible())) or ""),
		"hovered: " .. (IsValid(hov) and (hov:GetClassName() .. " " .. tostring(hov.NYRPCursor)) or "-"),
		"focus: " .. (IsValid(foc) and foc:GetClassName() or "-"),
	}
	for i, l in ipairs(lines) do
		draw.SimpleTextOutlined(l, "DermaDefault", 12, 12 + i * 16, Color(255, 255, 120), 0, 0, 1, color_black)
	end
end)

hook.Add("Initialize", "nyrp.cursor", function()
	hide(GetHUDPanel and GetHUDPanel())
end)

-- Курсор панели (SetCursor) -> наш вид. Картинки: materials/nyrp/cursor/<вид>.png
local kinds = {
	hand = "hand", sizeall = "move", sizewe = "resize_h", sizens = "resize_v",
	sizenwse = "resize_d2", sizenesw = "resize_d1", beam = "text", ibeam = "text",
	no = "no", hourglass = "wait", waitarrow = "wait", crosshair = "zoom",
}
-- Размер (доля от базового) и «острие» (куда указывает курсор) в долях картинки.
local shapes = {
	arrow = { size = 1.0, hx = 4 / 64, hy = 3.5 / 64 },
	hand = { size = 0.84, hx = 0.41, hy = 0.19 },
	grab = { size = 0.84, hx = 0.5, hy = 0.5 },
	text = { size = 0.8, hx = 0.5, hy = 0.5 },
}
local DEFAULT_SHAPE = { size = 0.8, hx = 0.5, hy = 0.5 }

local function cursorKind()
	-- тащим предмет / держим нажатой «руку» — сжатая ладонь
	if NYRP.Inventory and NYRP.Inventory.Drag then return "grab" end
	local pnl = vgui.GetHoveredPanel()
	while IsValid(pnl) do
		local c = pnl.NYRPCursor
		if c and c ~= "arrow" and c ~= "none" and c ~= "blank" then
			local k = kinds[c] or "arrow"
			if k == "hand" and input.IsMouseDown(MOUSE_LEFT) then return "grab" end
			if not pnl:IsEnabled() and k == "hand" then return "no" end
			return k
		end
		if c == "arrow" then return "arrow" end
		pnl = pnl:GetParent()
	end
	return "arrow"
end

local scale = 1
local lastKind = "arrow"
hook.Add("DrawOverlay", "nyrp.cursor", function()
	-- курсор с «пустой» картинкой движок может считать скрытым — учитываем и режим свободной мыши
	if not (vgui.CursorVisible() or NYRP.ScreenClicker) or gui.IsGameUIVisible() then return end
	local x, y = input.GetCursorPos()
	local kind = cursorKind()
	if kind ~= lastKind then scale = 0.8 lastKind = kind end
	scale = NYRP.UI.Approach(scale, input.IsMouseDown(MOUSE_LEFT) and 0.9 or 1, 18)
	local sh = shapes[kind] or DEFAULT_SHAPE
	local size = math.Round(NYRP.UI.S(29) * sh.size * scale)
	surface.SetMaterial(NYRP.UI.Mat("nyrp/cursor/" .. kind .. ".png"))
	surface.SetDrawColor(255, 255, 255, 255)
	surface.DrawTexturedRect(x - size * sh.hx, y - size * sh.hy, size, size)
end)
