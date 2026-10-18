--[[
	Мелкие общие функции: лог, сглаживания, интерполяции.
]]

function WS.Print(...)
	MsgC(Color(196, 38, 38), "[WS] ", Color(220, 225, 230), string.format(...), "\n")
end

-- Плавное приближение к цели со скоростью speed (единиц в секунду).
function WS.Approach(cur, target, speed)
	return math.Approach(cur, target, speed * FrameTime())
end

local E = {}
WS.Ease = E

function E.Clamp01(x) return x < 0 and 0 or (x > 1 and 1 or x) end
function E.Smooth(x) x = E.Clamp01(x) return x * x * (3 - 2 * x) end
function E.OutCubic(x) x = 1 - E.Clamp01(x) return 1 - x * x * x end
function E.InOutSine(x) return -(math.cos(math.pi * E.Clamp01(x)) - 1) / 2 end
function E.OutExpo(x) x = E.Clamp01(x) return x == 1 and 1 or 1 - 2 ^ (-10 * x) end

-- Окно 0..1..0: нарастает за fadeIn с момента a, держится до b, гаснет за fadeOut.
function E.Window(t, a, b, fadeIn, fadeOut)
	if t < a or t > b + fadeOut then return 0 end
	if t < a + fadeIn then return E.Smooth((t - a) / fadeIn) end
	if t > b then return 1 - E.Smooth((t - b) / fadeOut) end
	return 1
end

-- Отрезок времени -> 0..1
function E.Range(t, a, b)
	return E.Clamp01((t - a) / (b - a))
end

-- Верхний регистр с кириллицей (string.upper в GMod кириллицу не трогает)
function WS.Upper(s)
	local out = {}
	for _, c in utf8.codes(s) do
		if c >= 0x430 and c <= 0x44F then c = c - 0x20
		elseif c == 0x451 then c = 0x401
		elseif c >= 97 and c <= 122 then c = c - 32 end
		out[#out + 1] = utf8.char(c)
	end
	return table.concat(out)
end
