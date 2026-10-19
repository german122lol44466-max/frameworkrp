--[[
	Убираем «песочницу»: обычный игрок не видит и не может того, что выдаёт Garry's Mod.
	Суперадмины сохраняют инструменты (Shift+Q — меню песочницы, noclip, физган).
	  • нет noclip, спрея, физгана/тулгана по игрокам и врагам, спавна пропов;
	  • нет контекстного меню (C), подсказок песочницы, уведомлений «Undone» и т. п.;
	  • нет стандартного прицела, иконок убийств, информации о сущностях.
]]

local function admin(ply) return IsValid(ply) and (ply:IsSuperAdmin() or ply.wsEditing) end

hook.Add("PlayerNoClip", "ws.immersion", function(ply, on)
	if not on then return true end
	if not admin(ply) then return false end
end)

hook.Add("PlayerSpray", "ws.immersion", function(ply) if not admin(ply) then return true end end)

for _, h in ipairs({ "PlayerSpawnProp", "PlayerSpawnRagdoll", "PlayerSpawnEffect", "PlayerSpawnVehicle", "PlayerSpawnNPC",
	"PlayerSpawnSENT", "PlayerSpawnSWEP", "PlayerGiveSWEP", "PlayerSpawnObject" }) do
	hook.Add(h, "ws.immersion", function(ply) if not admin(ply) then return false end end)
end

hook.Add("PhysgunPickup", "ws.immersion", function(ply, ent)
	if not admin(ply) then return false end
end)
hook.Add("CanTool", "ws.immersion", function(ply) if not admin(ply) then return false end end)
hook.Add("CanProperty", "ws.immersion", function(ply) if not admin(ply) then return false end end)
hook.Add("CanDrive", "ws.immersion", function(ply) if not admin(ply) then return false end end)

if SERVER then
	-- в отряде нельзя толкать и «подбирать» товарищей
	hook.Add("AllowPlayerPickup", "ws.immersion", function(ply, ent)
		if ent:IsPlayer() or ent:GetClass() == "ws_enemy" then return false end
	end)
	return
end

-- ---------------------------------------------------------------- клиент

hook.Add("OnContextMenuOpen", "ws.immersion", function()
	if not admin(LocalPlayer()) then return false end
end)

hook.Add("HUDShouldDraw", "ws.immersion", function(name)
	if name == "CHudCrosshair" then return false end
end)

-- подсказки песочницы и всплывающие уведомления
hook.Add("AddHint", "ws.immersion", function() return false end)
hook.Add("SuppressHint", "ws.immersion", function() return true end)
hook.Add("InitPostEntity", "ws.immersion", function()
	RunConsoleCommand("cl_showhints", "0")
	-- без «Undone ...» и прочих notification песочницы
	if notification then
		notification.AddLegacy = function() end
		notification.AddProgress = function() end
	end
	if GAMEMODE then
		GAMEMODE.AddNotify = function() end
		GAMEMODE.PaintNotes = function() end
	end
end)

-- без иконок убийств и подписи «Игрок убил ...»
hook.Add("AddDeathNotice", "ws.immersion", function() return false end)

-- над сущностями песочницы не показывать подписи
hook.Add("HUDDrawTargetID", "ws.immersion", function() return false end)
