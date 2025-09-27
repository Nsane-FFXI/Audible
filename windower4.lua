_addon.name     = 'Audible'
_addon.author   = 'Thorny, concept and sounds by Nsane'
_addon.version  = '1.1'
_addon.commands = {'aud', 'audible'}

-- Dependencies
local packets  = require('packets')
local res      = require('resources')
local wildcard = require('wildcard')
local config   = require('config')

-- Settings (persisted)
local defaults = {
    Debug = false,
    DetectParty = true,
    DetectAlliance = true,
    VolumePercent = 25,
}
local settings = config.load(defaults)

-- Trigger tables and helpers
local triggers = {
    AllText               = require('triggers.alltext'),
    Chat                  = require('triggers.chat'),
    ChatMon               = require('triggers.chatmon'),
    DebuffedByStatus      = require('triggers.debuffedbystatus'),
    DebuffingByStatus     = require('triggers.debuffingbystatus'),
    DebuffedBySpell       = require('triggers.debuffedbyspell'),
    DebuffingBySpell      = require('triggers.debuffingbyspell'),
    LostBuff              = require('triggers.lostbuff'),
    LostDebuff            = require('triggers.lostdebuff'),
    MiscActions           = require('triggers.miscactions'),
    MobDispelled          = require('triggers.mobdispelled'),
    MobReadies            = require('triggers.mobreadies'),
    MobUses               = require('triggers.mobuses'),
    TreasureHunterUpgrade = require('triggers.treasurehunterupgrade'),
}

-- Small IO helpers
local function _sanitize(rel)
    return (rel or ''):gsub('[^%w]', '_')
end

local function _read_all(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local data = f:read('*a')
    f:close()
    return data
end

local function _write_all(path, bytes)
    local dir = path:match('^(.*)[/\\]')
    if dir then pcall(windower.create_dir, dir) end
    local f = io.open(path, 'wb')
    if not f then return false end
    f:write(bytes)
    f:close()
    return true
end

-- WAV utilities: simple 16-bit PCM gain scaler
local function _find_chunk(buf, tag)
    local i = 13 -- skip "RIFF"(4) + size(4) + "WAVE"(4)
    while i + 8 <= #buf do
        local t = buf:sub(i, i + 3)
        local b1, b2, b3, b4 = buf:byte(i + 4, i + 7)
        local sz = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
        if t == tag then return i, sz end
        i = i + 8 + sz
    end
    return nil, nil
end

local function _parse_wav(buf)
    if not buf or #buf < 44 then return nil, 'file too small' end
    if buf:sub(1, 4) ~= 'RIFF' or buf:sub(9, 12) ~= 'WAVE' then return nil, 'not wav' end
    local fmt_off, fmt_sz = _find_chunk(buf, 'fmt ')
    local dat_off, dat_sz = _find_chunk(buf, 'data')
    if not fmt_off or not dat_off then return nil, 'missing chunks' end
    local lo, hi = buf:byte(fmt_off + 8, fmt_off + 9)
    local audio_fmt = lo + hi * 256
    local ch_lo, ch_hi = buf:byte(fmt_off + 10, fmt_off + 11)
    local channels = ch_lo + ch_hi * 256
    local bps_lo, bps_hi = buf:byte(fmt_off + 22, fmt_off + 23)
    local bits = bps_lo + bps_hi * 256
    local data_start = dat_off + 8
    return {
        fmt_off = fmt_off, fmt_sz = fmt_sz,
        data_off = dat_off, data_sz = dat_sz,
        data_start = data_start, channels = channels, bits = bits, audio_fmt = audio_fmt
    }
end

local function _scale_wav_16(buf, info, gain)
    local out, j = {}, 1
    local i = info.data_start
    local n = info.data_sz

    local function clamp(v)
        if v > 32767 then return 32767 end
        if v < -32768 then return -32768 end
        return v
    end

    -- header up to data
    out[j] = buf:sub(1, info.data_start - 1); j = j + 1

    local k = 0
    while k < n do
        local b1, b2 = buf:byte(i + k, i + k + 1)
        if not b1 or not b2 then break end
        local v = b1 + b2 * 256
        if v >= 32768 then v = v - 65536 end
        v = clamp(math.floor(v * gain + 0.5))
        if v < 0 then v = v + 65536 end
        out[j] = string.char(v % 256)
        out[j + 1] = string.char(math.floor(v / 256) % 256)
        j = j + 2
        k = k + 2
    end

    -- any tail after data
    local tail = info.data_start + info.data_sz
    if tail <= #buf then out[j] = buf:sub(tail) end
    return table.concat(out)
end

-- Ensure a gain-adjusted file exists. Supports 16-bit PCM only.
local function ensure_gainfile(relative, gain)
    local allowed = { [0]=0, [0.5]=0.5, [1]=1, [3]=3, [5]=5 }
    gain = allowed[gain] or 1

    local base_rel = relative
    local base_abs
    if base_rel:find('^[/\\]') or base_rel:find(':') then
        base_abs = base_rel
    else
        base_abs = ('%sresources/audio/%s'):format(windower.addon_path, base_rel)
    end

    -- No processing for 0x (mute handled by caller) or 1x
    if gain == 0 or gain == 1 then return base_abs end

    local out_root = ('%sresources/audio/__gain'):format(windower.addon_path)
    pcall(windower.create_dir, out_root)

    local tag = (gain == 0.5 and '050')
             or (gain == 3   and '300')
             or (gain == 5   and '500')
             or '100'

    local out = ('%s/%s__x%s.wav'):format(out_root, _sanitize(base_rel), tag)

    if windower.file_exists and windower.file_exists(out) then
        return out
    end

    local bytes = _read_all(base_abs)
    if not bytes then return base_abs end

    local info = _parse_wav(bytes)
    if not info or info.audio_fmt ~= 1 or info.bits ~= 16 then
        return base_abs
    end

    local processed = _scale_wav_16(bytes, info, gain)
    if _write_all(out, processed) then
        return out
    else
        return base_abs
    end
end

-- Volume and gain mapping
local function plays_from_percent(p)
    p = math.floor(math.max(0, math.min(100, p or 50)))
    if p <= 0  then return 0 end
    if p >= 88 then return 3 end
    if p >= 63 then return 2 end
    return 1
end

local function gain_from_percent(p)
    p = math.floor(math.max(0, math.min(100, p or 50)))
    if p <= 0  then return 0 end
    if p <= 37 then return 0.5 end
    if p <= 62 then return 1 end
    if p <= 87 then return 3 end
    return 5
end

local function volume_label(p)
    p = math.floor(math.max(0, math.min(100, p or 50)))
    if p == 0  then return 'Muted' end
    if p <= 37 then return 'Soft' end
    if p <= 62 then return 'Normal' end
    if p <= 87 then return 'Loud' end
    return 'Maximum'
end

local function normalize_volume_input(v)
    if v and v >= 0 and v <= 4 then
        return ({0, 25, 50, 75, 100})[v + 1]
    end
    return math.floor(math.max(0, math.min(100, v or 50)))
end

local function play_sound_for(_, relative)
    local plays = plays_from_percent(settings.VolumePercent)
    local gain  = gain_from_percent(settings.VolumePercent)
    if plays == 0 or gain == 0 then return false end

    -- Prefer single-file gain when possible
    local path = ensure_gainfile(relative, gain)
    if gain ~= 1 then
        windower.play_sound(path)
        return true
    end

    -- Gain 1x; layer if needed
    if plays == 1 then
        if path:find('__x') then
            windower.play_sound(path)
        else
            local base = relative
            if not (relative:find('^[/\\]') or relative:find(':')) then
                base = ('%sresources/audio/%s'):format(windower.addon_path, relative)
            end
            windower.play_sound(base)
        end
        return true
    end
end

-- Persist selected fields
local function persist(patch)
    local disk = config.load(defaults)
    if patch and patch.VolumePercent ~= nil then
        disk.VolumePercent = math.floor(math.max(0, math.min(100, patch.VolumePercent)))
    end
    pcall(config.save, disk)
    settings = disk
end

-- Packet parsing and trigger evaluation
local function ParseActionPacket(data)
    local bitData = data
    local bitOffset = 40
    local function UnpackBits(length)
        local value = bitData:unpack('b' .. length, (bitOffset / 8):floor() + 1, bitOffset % 8 + 1)
        bitOffset = bitOffset + length
        return value
    end

    local actionPacket = T{}
    actionPacket.UserId = UnpackBits(32)
    local targetCount = UnpackBits(6)
    bitOffset = bitOffset + 4
    actionPacket.Type = UnpackBits(4)
    actionPacket.Id = UnpackBits(17)
    bitOffset = bitOffset + 15
    actionPacket.Recast = UnpackBits(32)

    actionPacket.Targets = T{}
    for _ = 1, targetCount do
        local target = T{}
        target.Id = UnpackBits(32)
        local actionCount = UnpackBits(4)
        target.Actions = T{}
        for _ = 1, actionCount do
            local action = T{}
            action.Reaction = UnpackBits(5)
            action.Animation = UnpackBits(12)
            action.SpecialEffect = UnpackBits(7)
            action.Knockback = UnpackBits(3)
            action.Param = UnpackBits(17)
            action.Message = UnpackBits(10)
            action.Flags = UnpackBits(31)

            if UnpackBits(1) == 1 then
                local ae = T{}
                ae.Damage = UnpackBits(10)
                ae.Param = UnpackBits(17)
                ae.Message = UnpackBits(10)
                action.AdditionalEffect = ae
            end

            if UnpackBits(1) == 1 then
                local se = T{}
                se.Damage = UnpackBits(10)
                se.Param = UnpackBits(14)
                se.Message = UnpackBits(10)
                action.SpikesEffect = se
            end

            target.Actions:append(action)
        end
        actionPacket.Targets:append(target)
    end

    return actionPacket
end

local partyKeys = { 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }
local allyKeys  = { 'a10', 'a11', 'a12', 'a13', 'a14', 'a15', 'a20', 'a21', 'a22', 'a23', 'a24', 'a25' } -- fixed

local function GetTriggerIds()
    local party = windower.ffxi.get_party()
    local ids = T{}

    if settings.DetectParty then
        for _, key in ipairs(partyKeys) do
            local val = party and party[key]
            if val and val.mob and val.mob.id then
                ids:append(val.mob.id)
            end
        end
    else
        local val = party and party['p0']
        if val and val.mob and val.mob.id then
            ids:append(val.mob.id)
        end
    end

    if settings.DetectAlliance then
        for _, key in ipairs(allyKeys) do
            local val = party and party[key]
            if val and val.mob and val.mob.id then
                ids:append(val.mob.id)
            end
        end
    end

    return ids
end

local function EvaluateTriggers(category, key)
    local tbl = triggers[category]
    local trigger = tbl and tbl[key]
    if trigger then
        if settings.Debug then
            print(string.format('Triggered!  Category:%s Param:%s File:%s', category, tostring(key), trigger))
        end
        play_sound_for(category, trigger)
        return true
    else
        if settings.Debug then
            print(string.format('Triggered!  Category:%s Param:%s File:None', category, tostring(key)))
        end
        return false
    end
end

local function EvaluateChatEntry(entry, params)
    local msg = (entry.CaseSensitive == true) and params.Message or params.LowerMessage

    if entry.ProcessedWildcard ~= nil and not msg:match(entry.ProcessedWildcard) then
        return false
    end
    if entry.ProcessedPattern ~= nil and not msg:match(entry.ProcessedPattern) then
        return false
    end

    if entry.Mode ~= nil then
        if type(entry.Mode) == 'table' then
            if not entry.Mode:contains(params.Mode) then return false end
        elseif entry.Mode ~= params.Mode then
            return false
        end
    end

    if entry.Sender ~= nil and (entry.Sender:lower() ~= params.Sender) then
        return false
    end

    return true
end

local function EvaluateChat(params)
    for _, entry in ipairs(triggers.Chat) do
        if EvaluateChatEntry(entry, params) and type(entry.Sound) == 'string' then
            if play_sound_for('Chat', entry.Sound) and settings.Debug then
                print(string.format('Triggered!  Category:Chat Param:%s File:%s', params.Message, entry.Sound))
            end
        end
    end
end

-- Pattern builders for Chat and AllText
local function BuildPattern(entry, name)
    if entry.Wildcard ~= nil then
        if entry.CaseSensitive ~= true then
            entry.ProcessedWildcard = wildcard:Convert((entry.Wildcard:lower()):gsub('%%$name', name:lower()))
        else
            entry.ProcessedWildcard = wildcard:Convert(entry.Wildcard:gsub('%%$name', name))
        end
    end
    if entry.Pattern ~= nil then
        if entry.CaseSensitive ~= true then
            entry.ProcessedPattern = (entry.Pattern:lower()):gsub('%%$name', name:lower())
        else
            entry.ProcessedPattern = entry.Pattern:gsub('%%$name', name)
        end
    end
    if type(entry.Mode) == 'table' then
        entry.Mode = T(entry.Mode)
    end
end

local function BuildPatterns(name)
    for _, entry in ipairs(triggers.Chat) do
        BuildPattern(entry, name)
    end
    for _, entry in ipairs(triggers.AllText) do
        BuildPattern(entry, name)
    end
end

local currentName
do
    local player = windower.ffxi.get_player()
    currentName = player and player.name and player.name:lower() or '$name'
    BuildPatterns(currentName)
end

-- Event hooks
windower.register_event('incoming chunk', function(id, data)
    if id == 0x00A then
        local packet = packets.parse('incoming', data)
        local name = packet['Player Name']
        local lname = name and name:lower() or nil
        if lname and lname ~= currentName then
            BuildPatterns(lname)
            currentName = lname
        end
    end

    if id == 0x017 then
        local player = windower.ffxi.get_player() or {}
        local packet = packets.parse('incoming', data)

        if packet.Mode == 12 then
            EvaluateTriggers('ChatMon', 'GM')
        end
        if packet.Mode == 3 and packet['Sender Name'] ~= player.name then
            EvaluateTriggers('ChatMon', 'Tell')
        end
        if player.name and packet.Message:lower():contains(player.name:lower()) then
            EvaluateTriggers('ChatMon', 'Talk')
        end

        local parsed = windower.convert_auto_trans(packet.Message)
        local params = {
            Message = parsed,
            LowerMessage = parsed:lower(),
            Mode = res.chat[packet.Mode].en,
            Sender = packet['Sender Name'],
        }
        EvaluateChat(params)
    end

    if id == 0x028 then
        local packet = ParseActionPacket(data)
        local ids = GetTriggerIds()

        -- Monster acts
        if packet.UserId > 1000000 then
            for _, target in ipairs(packet.Targets) do
                local targetsSelf = target.Id == ids[1]
                for _, action in ipairs(target.Actions) do
                    local messageId = action.Message

                    if T{43, 675}:contains(messageId) then
                        local param = action.Param
                        local skillData = param < 256 and res.weapon_skills[param] or res.monster_abilities[param]
                        if skillData then EvaluateTriggers('MobReadies', skillData.en) end

                    elseif messageId == 326 then
                        local abilData = res.job_abilities[action.Param]
                        if abilData then EvaluateTriggers('MobReadies', abilData.en) end

                    elseif T{3, 327}:contains(messageId) then
                        local spellData = res.spells[action.Param]
                        if spellData then EvaluateTriggers('MobReadies', spellData.en) end

                    elseif messageId == 716 then
                        local wsData = res.weapon_skills[action.Param]
                        if wsData then EvaluateTriggers('MobReadies', wsData.en) end

                    elseif T{100, 102, 108, 110, 119, 122, 734, 738}:contains(messageId) then
                        local abilityData = res.job_abilities[packet.Id]
                        if abilityData then EvaluateTriggers('MobUses', abilityData.en) end

                    elseif T{101, 135}:contains(messageId) then
                        local wsData = res.monster_abilities[packet.Id]
                        if wsData then EvaluateTriggers('MobUses', wsData.en) end
                    end

                    if targetsSelf then
                        if T{82,127,141,160,164,203,236,237,242,243,267,268,269,270,271,272,277,278,279,320,374,375,412,645,754,755,804}:contains(messageId) then
                            if not EvaluateTriggers('DebuffedByStatus', action.Param) then
                                local buffData = res.buffs[action.Param]
                                if buffData then EvaluateTriggers('DebuffedByStatus', buffData.en) end
                            end
                        elseif T{2,7,252}:contains(messageId) then
                            if not EvaluateTriggers('DebuffedBySpell', packet.Id) then
                                local spellData = res.spells[packet.Id]
                                if spellData then EvaluateTriggers('DebuffedBySpell', spellData.en) end
                            end
                        end
                    end
                end
            end
        end

        -- Self acts
        if packet.UserId == ids[1] then
            for _, target in ipairs(packet.Targets) do
                for _, action in ipairs(target.Actions) do
                    EvaluateTriggers('MiscActions', action.Message)
                end
            end
        end

        -- Party/alliance acts
        if ids:contains(packet.UserId) then
            for _, target in ipairs(packet.Targets) do
                for _, action in ipairs(target.Actions) do
                    local messageId = action.Message

                    if T{82,127,141,160,164,203,236,237,242,243,267,268,269,270,271,272,277,278,279,320,374,375,412,645,754,755,804}:contains(messageId) then
                        if not EvaluateTriggers('DebuffingByStatus', action.Param) then
                            local buffData = res.buffs[action.Param]
                            if buffData then EvaluateTriggers('DebuffingByStatus', buffData.en) end
                        end

                    elseif T{2,7,252}:contains(messageId) then
                        if not EvaluateTriggers('DebuffingBySpell', packet.Id) then
                            local spellData = res.spells[packet.Id]
                            if spellData then EvaluateTriggers('DebuffingBySpell', spellData.en) end
                        end

                    elseif T{603, 608}:contains(messageId) then
                        EvaluateTriggers('TreasureHunterUpgrade', action.Param)
                    end
                end
            end
        end
    end

    if id == 0x029 then
        local action_message = packets.parse('incoming', data)
        local ids = GetTriggerIds()
        if action_message['Actor'] == ids[1] then
            if T{64,204,206,321,322,341,342,343,344,350,351,378,531,647}:contains(action_message.Message) then
                local trigger = (action_message.Target > 1000000) and 'LostDebuff' or 'LostBuff'
                if not EvaluateTriggers(trigger, action_message['Param 1']) then
                    local buffData = res.buffs[action_message['Param 1']]
                    if buffData then EvaluateTriggers(trigger, buffData.en) end
                end
            else
                EvaluateTriggers('MiscActions', action_message.Message)
            end
        end
    end

    if id == 0x21 then
        EvaluateTriggers('ChatMon', 'Trade')
    end

    if id == 0x0DC then
        EvaluateTriggers('ChatMon', 'Invite')
    end
end)

-- Incoming text (system feed, not packet 0x017)
local function EvaluateText(params)
    for _, entry in ipairs(triggers.AllText) do
        if EvaluateChatEntry(entry, params) and type(entry.Sound) == 'string' then
            if play_sound_for('AllText', entry.Sound) and settings.Debug then
                print(string.format('Triggered!  Category:Text Param:%s File:%s', params.Message, entry.Sound))
            end
        end
    end
end

windower.register_event('incoming text', function(original, _, mode)
    local parsed = windower.convert_auto_trans(original)
    local chat = res.chat[mode]
    local params = {
        Message = parsed,
        LowerMessage = parsed:lower(),
        Mode = chat and chat.en or mode,
    }
    EvaluateText(params)
end)

windower.register_event('emote', function(emote_id, sender_id, target_id)
    local myId = (windower.ffxi.get_player() or {}).id
    if target_id == myId and sender_id ~= myId then
        EvaluateTriggers('ChatMon', 'Emote')
    end
end)

windower.register_event('examined', function(sender_name, _)
    local myName = (windower.ffxi.get_player() or {}).name
    if myName and sender_name ~= myName then
        EvaluateTriggers('ChatMon', 'Examine')
    end
end)

-- Status print
local function print_status()
    local label = volume_label(settings.VolumePercent)
    windower.add_to_chat(207, ('[Audible] Volume: %s'):format(label))
end

-- Commands
windower.register_event('addon command', function(...)
    local args = T{...}
    local cmd = (args[1] or ''):lower()

    if cmd == 'volume' then
        local v = tonumber(args[2])
        if v == nil then
            windower.add_to_chat(207, '[Audible] Usage: //aud volume 0-4 (0=Muted,1=Soft,2=Normal,3=Loud,4=Maximum)')
            return
        end
        local np = normalize_volume_input(v)
        persist({ VolumePercent = np })
        print_status()
        return
    end

    if cmd == 'status' then
        print_status()
        return
    end

    -- Help
    windower.add_to_chat(207, '[Audible] Commands:')
    windower.add_to_chat(207, '  //aud status')
    windower.add_to_chat(207, '  //aud volume 0-4   -- 0 Muted, 1 Soft, 2 Normal, 3 Loud, 4 Maximum')
end)
