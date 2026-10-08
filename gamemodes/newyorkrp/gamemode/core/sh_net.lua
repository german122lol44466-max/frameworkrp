--[[
	Регистрация сетевых сообщений. Все имена в одном месте.
]]

NYRP.NetMessages = {
	"nyrp.notify",
	"nyrp.ready",
	-- персонажи
	"nyrp.char.list", "nyrp.char.create", "nyrp.char.load", "nyrp.char.delete", "nyrp.char.loaded",
	"nyrp.char.menu", "nyrp.char.state",
	-- точки камер
	"nyrp.points", "nyrp.points.save",
	-- инвентарь
	"nyrp.inv.sync", "nyrp.inv.move", "nyrp.inv.equip", "nyrp.inv.unequip", "nyrp.inv.use", "nyrp.inv.drop",
	"nyrp.inv.open", "nyrp.inv.close", "nyrp.inv.anim", "nyrp.inv.view",
	"nyrp.action",
	-- чат
	"nyrp.chat.say", "nyrp.chat.msg", "nyrp.chat.typing",
	-- смерть
	"nyrp.death.respawn",
	-- знакомства
	"nyrp.recog.sync", "nyrp.recog.introduce",
	"nyrp.interact.use",
	-- жесты
	"nyrp.gesture.play",
	-- взаимодействие с игроком, деньги
	"nyrp.player.act", "nyrp.money.give",
	-- режим голоса
	"nyrp.voice.mode",
	-- запрос «показать удостоверение»
	"nyrp.id.request", "nyrp.id.answer",
	-- время суток
	"nyrp.time.light",
	-- контейнеры
	"nyrp.cont.progress", "nyrp.cont.open", "nyrp.cont.sync", "nyrp.cont.close",
}

if SERVER then
	for _, name in ipairs(NYRP.NetMessages) do
		util.AddNetworkString(name)
	end
end
