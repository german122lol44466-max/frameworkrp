--[[
	Голосовые фразы (G): список общий для клиента и сервера.
	Звук — sound/whitesilence/game/vo_<голос>_<id>.mp3, голос у игрока свой (один из двух).
	act — жест, который боец показывает рукой.
]]

WS.Phrases = {
	{ id = "forward", text = "Вперёд!", act = ACT_SIGNAL_FORWARD },
	{ id = "cover", text = "Прикрываю!", act = ACT_SIGNAL_HALT },
	{ id = "contact", text = "Контакт! Вижу цель!", act = ACT_SIGNAL_FORWARD },
	{ id = "reload", text = "Перезаряжаюсь!", act = ACT_GMOD_GESTURE_ITEM_GIVE },
	{ id = "fallback", text = "Отходим!", act = ACT_SIGNAL_GROUP },
	{ id = "help", text = "Нужна помощь!", act = ACT_GMOD_GESTURE_WAVE },
	{ id = "clear", text = "Чисто.", act = ACT_GMOD_GESTURE_AGREE },
	{ id = "listen", text = "Тихо... Слышите?", act = ACT_SIGNAL_HALT },
}

WS.PhraseVoices = { "dmitri", "denis" }

function WS.PhraseVoice(ply)
	return WS.PhraseVoices[ply:EntIndex() % #WS.PhraseVoices + 1]
end
