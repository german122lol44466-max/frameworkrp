--[[
	Озвучка реплик NPC (TTS из интернета у клиента): голос выбирается в редакторе NPC (вкладка «Основное»).
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

local function urlsFor(text, v)
	local list = {}
	if v.provider == "google" then
		for _, c in ipairs(chunks(text, 190)) do
			list[#list + 1] = "https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&tl=ru&q=" .. urlencode(c)
		end
	else
		for _, c in ipairs(chunks(text, 480)) do
			list[#list + 1] = "https://api.streamelements.com/kappa/v2/speech?voice=" .. v.voice .. "&text=" .. urlencode(c)
		end
	end
	return list
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
			-- сервис недоступен — молча без звука
			N.StopSpeak()
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
	local v = N.VoiceById[voiceId or ""]
	if not v or v.id == "" or not enabled:GetBool() or not text or text == "" then return end
	-- в речи не нужны ремарки в звёздочках и скобках
	text = string.gsub(text, "%*[^%*]*%*", " ")
	text = string.gsub(text, "%b()", " ")
	text = string.Trim(string.gsub(text, "%s+", " "))
	if text == "" then return end
	token = token + 1
	cur = { ent = ent, queue = urlsFor(text, v), voice = v, token = token }
	if IsValid(ent) then
		local jaw = ent:GetFlexIDByName("jaw_drop")
		cur.jaw = jaw and jaw >= 0 and jaw or nil
	end
	playNext(token)
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
