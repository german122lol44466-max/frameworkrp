--[[
	Элементы интерфейса в стиле NYRP: кнопки, слайдер, переключатель, поле ввода, скролл, контекстное меню.
]]

local UI = NYRP.UI

-- ---------------------------------------------------------------- Button --
local BUTTON = {}

function BUTTON:Init()
	self:SetText("")
	self.Label = ""
	self.IconName = nil
	self.Hover = 0
	self.Accent = UI.Col.accent
	self.FontName = NYRP.Font("semibold", 18)
	self.Align = TEXT_ALIGN_LEFT
	self.Style = "flat"   -- flat | solid | ghost
end

function BUTTON:SetLabel(t) self.Label = t end
function BUTTON:SetIcon(name) self.IconName = name end
function BUTTON:SetStyle(s) self.Style = s end
function BUTTON:SetAccent(col) self.Accent = col end
function BUTTON:SetFontStyle(style, size) self.FontName = NYRP.Font(style, size) end
function BUTTON:SetAlign(a) self.Align = a end

function BUTTON:OnCursorEntered()
	if self:IsEnabled() then UI.Sound("hover") end
end

function BUTTON:OnDepressed()
	if self:IsEnabled() then UI.Sound("click") end
end

function BUTTON:Paint(w, h)
	local hovered = self:IsHovered() and self:IsEnabled()
	self.Hover = UI.Approach(self.Hover, hovered and 1 or 0, 14)
	local r = math.min(UI.S(8), h / 2)
	local alpha = self:IsEnabled() and 255 or 90
	if self.Style == "solid" then
		UI.RoundedRect(r, 0, 0, w, h, UI.LerpColor(self.Hover, UI.Alpha(self.Accent, 220), self.Accent))
	elseif self.Style == "ghost" then
		UI.Outline(r, 0, 0, w, h, UI.Alpha(self.Accent, 60 + self.Hover * 140), 1)
		UI.RoundedRect(r, 0, 0, w, h, UI.Alpha(self.Accent, self.Hover * 25))
	else
		UI.RoundedRect(r, 0, 0, w, h, Color(255, 255, 255, 8 + self.Hover * 14))
		if self.Hover > 0.01 then
			UI.RoundedRect(math.min(r, UI.S(2)), 0, h * 0.2, UI.S(3), h * 0.6 * self.Hover, UI.Alpha(self.Accent, 255 * self.Hover))
		end
	end

	local textCol = self.Style == "solid" and UI.Col.black or UI.LerpColor(self.Hover, UI.Col.text, UI.Col.white or color_white)
	textCol = Color(textCol.r, textCol.g, textCol.b, alpha)
	local pad = UI.S(14) + self.Hover * UI.S(4) * (self.Style == "flat" and 1 or 0)
	local x = pad
	local isz = math.Round(h * 0.46)
	if self.IconName then
		if self.Align == TEXT_ALIGN_CENTER and self.Label == "" then
			UI.DrawIcon(self.IconName, w / 2, h / 2, isz, textCol)
			return
		end
		UI.DrawIcon(self.IconName, x + isz / 2, h / 2, isz, self.Style == "solid" and textCol or UI.LerpColor(self.Hover, UI.Col.dim, self.Accent))
		x = x + isz + UI.S(10)
	end
	if self.Align == TEXT_ALIGN_CENTER then
		draw.SimpleText(self.Label, self.FontName, w / 2, h / 2, textCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	else
		draw.SimpleText(self.Label, self.FontName, x, h / 2, textCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	return true
end
vgui.Register("NYRP.Button", BUTTON, "DButton")

-- ------------------------------------------------------------ IconButton --
local ICONBTN = {}
function ICONBTN:Init()
	self:SetText("")
	self.Hover = 0
	self.IconName = "close"
	self.Tooltip = nil
end
function ICONBTN:SetIcon(n) self.IconName = n end
function ICONBTN:OnCursorEntered() UI.Sound("hover") end
function ICONBTN:OnDepressed() UI.Sound("click") end
function ICONBTN:Paint(w, h)
	self.Hover = UI.Approach(self.Hover, self:IsHovered() and 1 or 0, 14)
	UI.Circle(w / 2, h / 2, w / 2, Color(255, 255, 255, 10 + self.Hover * 20))
	local col = UI.LerpColor(self.Hover, UI.Col.dim, UI.Col.accent)
	UI.DrawIcon(self.IconName, w / 2, h / 2, w * 0.52, col)
	return true
end
vgui.Register("NYRP.IconButton", ICONBTN, "DButton")

-- ---------------------------------------------------------------- Slider --
local SLIDER = {}
function SLIDER:Init()
	self.Min, self.Max, self.Decimals = 0, 1, 2
	self.Value = 0
	self.Label = ""
	self.Hover = 0
	self.Suffix = ""
	self.Percent = false
	self:SetTall(UI.S(54))
	self:SetCursor("hand")
end
function SLIDER:SetLabel(t) self.Label = t end
function SLIDER:SetMinMax(a, b) self.Min, self.Max = a, b end
function SLIDER:SetDecimals(d) self.Decimals = d end
function SLIDER:SetPercent(b) self.Percent = b end
function SLIDER:SetSuffix(s) self.Suffix = s end
function SLIDER:SetValue(v, silent)
	v = math.Clamp(math.Round(v, self.Decimals), self.Min, self.Max)
	if v == self.Value then return end
	self.Value = v
	if self.ConVarName then RunConsoleCommand(self.ConVarName, tostring(v)) end
	if not silent and self.OnValueChanged then self:OnValueChanged(v) end
end
function SLIDER:SetConVar(name)
	self.ConVarName = name
	local cv = GetConVar(name)
	if cv then self.Value = cv:GetFloat() end
end
function SLIDER:BarRect()
	local w, h = self:GetSize()
	return UI.S(2), h - UI.S(16), w - UI.S(4), UI.S(6)
end
function SLIDER:UpdateFromMouse()
	local bx, _, bw = self:BarRect()
	local mx = self:CursorPos()
	local frac = math.Clamp((mx - bx) / bw, 0, 1)
	self:SetValue(self.Min + (self.Max - self.Min) * frac)
end
function SLIDER:OnMousePressed(code)
	if code ~= MOUSE_LEFT then return end
	self.Dragging = true
	self:MouseCapture(true)
	self:UpdateFromMouse()
	UI.Sound("toggle")
end
function SLIDER:OnMouseReleased()
	self.Dragging = false
	self:MouseCapture(false)
end
function SLIDER:Think()
	if self.Dragging then self:UpdateFromMouse() end
end
function SLIDER:Paint(w, h)
	self.Hover = UI.Approach(self.Hover, (self:IsHovered() or self.Dragging) and 1 or 0, 12)
	draw.SimpleText(self.Label, NYRP.Font("medium", 17), 0, UI.S(4), UI.Col.text)
	local val = self.Percent and (math.Round(self.Value * 100) .. "%") or (self.Value .. self.Suffix)
	draw.SimpleText(val, NYRP.Font("semibold", 16), w, UI.S(4), UI.Col.accent, TEXT_ALIGN_RIGHT)
	local bx, by, bw, bh = self:BarRect()
	local frac = (self.Value - self.Min) / math.max(self.Max - self.Min, 1e-6)
	UI.RoundedRect(bh / 2, bx, by, bw, bh, Color(255, 255, 255, 18))
	UI.RoundedRect(bh / 2, bx, by, math.max(bw * frac, bh), bh, UI.Col.accent)
	local kr = UI.S(7) + self.Hover * UI.S(2)
	UI.Circle(bx + bw * frac, by + bh / 2, kr, color_white)
end
vgui.Register("NYRP.Slider", SLIDER, "Panel")

-- ---------------------------------------------------------------- Toggle --
local TOGGLE = {}
function TOGGLE:Init()
	self.Label = ""
	self.Desc = nil
	self.On = false
	self.Anim = 0
	self:SetTall(UI.S(46))
	self:SetCursor("hand")
end
function TOGGLE:SetLabel(t) self.Label = t end
function TOGGLE:SetDescription(t) self.Desc = t end
function TOGGLE:SetConVar(name)
	self.ConVarName = name
	self.On = GetConVar(name):GetBool()
	self.Anim = self.On and 1 or 0
end
function TOGGLE:SetChecked(b) self.On = b self.Anim = b and 1 or 0 end
function TOGGLE:OnMousePressed(code)
	if code ~= MOUSE_LEFT then return end
	self.On = not self.On
	UI.Sound("toggle")
	if self.ConVarName then RunConsoleCommand(self.ConVarName, self.On and "1" or "0") end
	if self.OnChange then self:OnChange(self.On) end
end
function TOGGLE:Paint(w, h)
	self.Anim = UI.Approach(self.Anim, self.On and 1 or 0, 14)
	local sw, sh = UI.S(42), UI.S(22)
	local sx, sy = w - sw, h / 2 - sh / 2
	if self.Desc then
		draw.SimpleText(self.Label, NYRP.Font("medium", 17), 0, h / 2 - UI.S(2), UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
		draw.SimpleText(self.Desc, NYRP.Font("regular", 14), 0, h / 2 + UI.S(1), UI.Col.faint, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	else
		draw.SimpleText(self.Label, NYRP.Font("medium", 17), 0, h / 2, UI.Col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	UI.RoundedRect(sh / 2, sx, sy, sw, sh, UI.LerpColor(self.Anim, Color(255, 255, 255, 22), UI.Col.accent))
	UI.Circle(sx + sh / 2 + (sw - sh) * self.Anim, sy + sh / 2, sh / 2 - UI.S(3), self.On and UI.Col.black or color_white)
end
vgui.Register("NYRP.Toggle", TOGGLE, "Panel")

-- ------------------------------------------------------------- TextEntry --
local ENTRY = {}
function ENTRY:Init()
	self:SetFont(NYRP.Font("medium", 17))
	self:SetTextColor(UI.Col.text)
	self:SetCursorColor(UI.Col.accent)
	self:SetHighlightColor(UI.Alpha(UI.Col.accent, 90))
	self:SetPaintBackground(false)
	self.Focus = 0
	self:SetTall(UI.S(42))
	self:SetTextInset(UI.S(12), 0)
end
function ENTRY:Paint(w, h)
	self.Focus = UI.Approach(self.Focus, self:HasFocus() and 1 or 0, 12)
	UI.RoundedRect(UI.S(8), 0, 0, w, h, Color(255, 255, 255, 10 + self.Focus * 6))
	UI.Outline(UI.S(8), 0, 0, w, h, UI.LerpColor(self.Focus, Color(255, 255, 255, 18), UI.Alpha(UI.Col.accent, 160)), 1)
	if self:GetText() == "" and self:GetPlaceholderText() then
		local ty = self:IsMultiline() and UI.S(10) or h / 2
		draw.SimpleText(self:GetPlaceholderText(), self:GetFont(), UI.S(12), ty, UI.Col.faint, TEXT_ALIGN_LEFT,
			self:IsMultiline() and TEXT_ALIGN_TOP or TEXT_ALIGN_CENTER)
	end
	self:DrawTextEntryText(UI.Col.text, UI.Alpha(UI.Col.accent, 90), UI.Col.accent)
	return true
end
vgui.Register("NYRP.TextEntry", ENTRY, "DTextEntry")

-- ---------------------------------------------------------------- Scroll --
local SCROLL = {}
function SCROLL:Init()
	local bar = self:GetVBar()
	bar:SetWide(UI.S(4))
	bar:SetHideButtons(true)
	bar.Paint = function() end
	bar.btnGrip.Paint = function(s, w, h)
		UI.RoundedRect(w / 2, 0, 0, w, h, Color(255, 255, 255, s:IsHovered() and 60 or 28))
	end
end
vgui.Register("NYRP.Scroll", SCROLL, "DScrollPanel")

-- ---------------------------------------------------------- Context menu --
-- UI.Menu({ {text = "...", icon = "trash", color = Color, func = function() end}, {divider = true}, ... })
function UI.Menu(options, x, y)
	if IsValid(UI.ActiveMenu) then UI.ActiveMenu:Remove() end
	local catcher = vgui.Create("DPanel")
	catcher:SetSize(ScrW(), ScrH())
	catcher:SetPos(0, 0)
	catcher:MakePopup()
	catcher:SetKeyboardInputEnabled(false)
	catcher.Paint = function() end
	catcher.OnMousePressed = function(s) s:Remove() end
	UI.ActiveMenu = catcher

	local menu = vgui.Create("DPanel", catcher)
	local w = UI.S(220)
	local rowH = UI.S(38)
	local h = UI.S(8)
	for _, o in ipairs(options) do h = h + (o.divider and UI.S(9) or rowH) end
	h = h + UI.S(8)
	local mx, my = x or gui.MouseX(), y or gui.MouseY()
	menu:SetSize(w, h)
	menu:SetPos(math.min(mx + 4, ScrW() - w - 8), math.min(my + 4, ScrH() - h - 8))
	menu.Born = RealTime()
	menu.Paint = function(s, pw, ph)
		local t = UI.Ease((RealTime() - s.Born) / 0.15)
		s:SetAlpha(255 * t)
		UI.RoundedBlurPanel(s, UI.S(10), 4)
		UI.RoundedRect(UI.S(10), 0, 0, pw, ph, Color(14, 16, 24, 235))
		UI.Outline(UI.S(10), 0, 0, pw, ph, Color(255, 255, 255, 18), 1)
	end
	local cy = UI.S(8)
	for _, o in ipairs(options) do
		if o.divider then
			local div = vgui.Create("DPanel", menu)
			div:SetPos(UI.S(12), cy + UI.S(4))
			div:SetSize(w - UI.S(24), 1)
			div.Paint = function(_, dw, dh) surface.SetDrawColor(255, 255, 255, 16) surface.DrawRect(0, 0, dw, dh) end
			cy = cy + UI.S(9)
		else
			local b = vgui.Create("NYRP.Button", menu)
			b:SetPos(UI.S(6), cy)
			b:SetSize(w - UI.S(12), rowH)
			b:SetLabel(o.text)
			b:SetIcon(o.icon)
			b:SetFontStyle("medium", 16)
			if o.color then b:SetAccent(o.color) end
			b:SetEnabled(o.disabled ~= true)
			b.DoClick = function()
				catcher:Remove()
				if o.func then o.func() end
			end
			cy = cy + rowH
		end
	end
	UI.Sound("open")
	return catcher
end

-- Простое окно подтверждения.
function UI.Confirm(title, text, yesText, onYes)
	local bg = vgui.Create("DPanel")
	bg:SetSize(ScrW(), ScrH())
	bg:MakePopup()
	bg.Born = RealTime()
	bg.Paint = function(s, w, h)
		local t = UI.Ease((RealTime() - s.Born) / 0.2)
		UI.BlurPanel(s, 4 * t)
		surface.SetDrawColor(0, 0, 0, 150 * t)
		surface.DrawRect(0, 0, w, h)
	end
	local box = vgui.Create("DPanel", bg)
	box:SetSize(UI.S(440), UI.S(210))
	box:Center()
	box.Paint = function(s, w, h)
		UI.RoundedRect(UI.S(12), 0, 0, w, h, UI.Col.panel)
		UI.Outline(UI.S(12), 0, 0, w, h, UI.Col.stroke, 1)
		draw.SimpleText(title, NYRP.Font("title", 26), UI.S(24), UI.S(20), UI.Col.text)
		local lines = UI.Wrap(text, NYRP.Font("regular", 16), w - UI.S(48))
		for i, l in ipairs(lines) do
			draw.SimpleText(l, NYRP.Font("regular", 16), UI.S(24), UI.S(62) + (i - 1) * UI.S(22), UI.Col.dim)
		end
	end
	local yes = vgui.Create("NYRP.Button", box)
	yes:SetSize(UI.S(190), UI.S(42))
	yes:SetPos(UI.S(24), UI.S(146))
	yes:SetLabel(yesText or "Да")
	yes:SetStyle("solid")
	yes:SetAccent(UI.Col.red)
	yes:SetAlign(TEXT_ALIGN_CENTER)
	yes.DoClick = function() bg:Remove() onYes() end
	local no = vgui.Create("NYRP.Button", box)
	no:SetSize(UI.S(190), UI.S(42))
	no:SetPos(UI.S(226), UI.S(146))
	no:SetLabel("Отмена")
	no:SetStyle("ghost")
	no:SetAlign(TEXT_ALIGN_CENTER)
	no.DoClick = function() bg:Remove() end
	return bg
end
