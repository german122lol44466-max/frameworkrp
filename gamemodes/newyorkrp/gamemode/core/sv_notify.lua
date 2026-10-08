--[[
	Уведомления справа сверху. kind: "info" | "success" | "error" | "warning"
]]

function NYRP.Notify(ply, text, kind, duration)
	net.Start("nyrp.notify")
	net.WriteString(text)
	net.WriteString(kind or "info")
	net.WriteFloat(duration or 5)
	if ply then net.Send(ply) else net.Broadcast() end
end
