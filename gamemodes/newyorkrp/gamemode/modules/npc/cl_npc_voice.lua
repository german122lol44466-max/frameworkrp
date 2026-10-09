--[[
	Озвучка реплик NPC (TTS у клиента: Amazon Polly, iSpeech, Яндекс, Google, свой сервер Piper — см. N.Voices в sh_npc.lua): голос выбирается в редакторе NPC (вкладка «Основное»).
	Звук идёт из NPC (3D), губы двигаются по громкости. Отключить: nyrp_npc_voice 0, громкость — nyrp_npc_voice_volume.
]]

local N = NYRP.NPC
local enabled = CreateClientConVar("nyrp_npc_voice", "1", true, false, "Озвучка реплик NPC")
local volume = CreateClientConVar("nyrp_npc_voice_volume", "0.9", true, false, "Громкость озвучки NPC", 0, 1)

local cur -- { ent, channel, queue = {url...}, voice, token }
local token = 0

local function urlencode(s)
	return (string.gsub(s, "[^%w%-_%.~]", function(c) return string.format("%%%02X", string.byte(c)) end))
end

-- куски до limit символов по границам предложений/слов (у Google ограничение ~200)
local function chunks(text, limit)
	local out, buf = {}, ""
	for word in string.gmatch(text, "%S+") do
		if utf8.len(buf .. " " .. word) and utf8.len(buf .. " " .. word) > limit and buf ~= "" then
			out[#out + 1] = buf
			buf = word
		else
			buf = buf == "" and word or (buf .. " " .. word)
		end
	end
	if buf ~= "" then out[#out + 1] = buf end
	return out
end

local function google(text, lang)
	local list = {}
	for _, c in ipairs(chunks(text, 190)) do
		list[#list + 1] = "https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&tl=" .. (lang or "ru") .. "&q=" .. urlencode(c)
	end
	return list
end

-- ответы ttsmp3 (ссылка на готовый mp3) кэшируем: одни и те же реплики не запрашиваем дважды
local pollyCache = {}

-- cb(список ссылок) — для голоса v; nil — сервис не ответил
local function resolve(text, v, cb)
	if v.engine == "polly" then
		local parts = chunks(text, 2900)
		local out, left, failed = {}, #parts, false
		for i, c in ipairs(parts) do
			local key = v.voice .. "|" .. c
			if pollyCache[key] then
				out[i] = pollyCache[key]
				left = left - 1
				if left == 0 then cb(out) end
			else
				HTTP({ method = "POST", url = "https://ttsmp3.com/makemp3_new.php",
					parameters = { msg = c, lang = v.voice, source = "ttsmp3" },
					success = function(code, body)
						local j = util.JSONToTable(body or "")
						if code == 200 and j and j.URL and j.URL ~= "" and tonumber(j.Error) == 0 then
							pollyCache[key] = j.URL
							out[i] = j.URL
						else failed = true end
						left = left - 1
						if left == 0 then cb(not failed and out or nil) end
					end,
					failed = function() failed = true left = left - 1 if left == 0 then cb(nil) end end })
			end
		end
		return
	end
	local list = {}
	if v.engine == "ispeech" then
		for _, c in ipairs(chunks(text, 250)) do
			list[#list + 1] = "https://www.ispeech.org/p/generic/getaudio?text=" .. urlencode(c) .. "&voice=" .. v.voice .. "&speed=0&action=convert"
		end
	elseif v.engine == "yandex" then
		for _, c in ipairs(chunks(text, 400)) do
			list[#list + 1] = "https://tts.voicetech.yandex.net/tts?format=mp3&quality=hi&platform=web&application=translate&lang=ru_RU&text=" .. urlencode(c)
		end
	elseif v.engine == "piper" then
		local srv = string.Trim(GetConVar("nyrp_tts_server"):GetString())
		if srv == "" then cb(nil) return end
		srv = string.gsub(srv, "/+$", "")
		for _, c in ipairs(chunks(text, 600)) do
			list[#list + 1] = srv .. "/tts?voice=" .. urlencode(v.voice) .. "&text=" .. urlencode(c)
		end
	else
		list = google(text, v.lang)
	end
	cb(list)
end

function N.StopSpeak()
	token = token + 1
	if cur and IsValid(cur.channel) then cur.channel:Stop() end
	if cur and IsValid(cur.ent) and cur.jaw then cur.ent:SetFlexWeight(cur.jaw, 0) end
	cur = nil
end

local function playNext(my)
	if not cur or cur.token ~= my then return end
	local url = table.remove(cur.queue, 1)
	if not url then N.StopSpeak() return end
	local flags = IsValid(cur.ent) and "3d noblock" or "noblock"
	sound.PlayURL(url, flags, function(ch, err)
		if not cur or cur.token ~= my then if IsValid(ch) then ch:Stop() end return end
		if not IsValid(ch) then
			-- этот сервис не ответил — дочитываем голосом Google (той же высоты)
			if not cur.fallback then
				cur.fallback = true
				cur.queue = google(cur.text, "ru")
				playNext(my)
			else
				N.StopSpeak()
			end
			return
		end
		cur.channel = ch
		if IsValid(cur.ent) then
			ch:SetPos(cur.ent:EyePos())
			ch:Set3DFadeDistance(220, 1200)
		end
		ch:SetPlaybackRate(cur.voice.rate or 1)
		ch:SetVolume(volume:GetFloat())
		ch:Play()
	end)
end

-- ent — NPC (nil — проиграть «в ушах», для прослушивания в редакторе)
function N.Speak(ent, text, voiceId)
	N.StopSpeak()
	local v = N.VoiceById[N.VoiceAlias[voiceId or ""] or voiceId or ""]
	if not v or v.id == "" or not enabled:GetBool() or not text or text == "" then return end
	-- в речи не нужны ремарки в звёздочках и скобках
	text = string.gsub(text, "%*[^%*]*%*", " ")
	text = string.gsub(text, "%b()", " ")
	text = string.Trim(string.gsub(text, "%s+", " "))
	if text == "" then return end
	token = token + 1
	local my = token
	cur = { ent = ent, queue = {}, voice = v, token = my, text = text }
	if IsValid(ent) then
		local jaw = ent:GetFlexIDByName("jaw_drop")
		cur.jaw = jaw and jaw >= 0 and jaw or nil
	end
	resolve(text, v, function(list)
		if not cur or cur.token ~= my then return end
		if not list or #list == 0 then
			cur.fallback = true
			list = google(text, "ru")
		end
		cur.queue = list
		playNext(my)
	end)
end

hook.Add("Think", "nyrp.npc.voice", function()
	if not cur then return end
	local ch = cur.channel
	if not IsValid(ch) then return end
	if IsValid(cur.ent) then ch:SetPos(cur.ent:EyePos()) end
	-- губы по громкости
	if cur.jaw and IsValid(cur.ent) then
		local l, r = ch:GetLevel()
		cur.ent:SetFlexWeight(cur.jaw, math.Clamp(((l or 0) + (r or 0)) * 2.2, 0, 1))
	end
	if ch:GetState() == GMOD_CHANNEL_STOPPED then
		cur.channel = nil
		playNext(cur.token)
	end
end)
