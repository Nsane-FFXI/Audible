_addon.name    = 'Audible'
_addon.author  = 'Thorny, concept and sounds by Nsane';
_addon.version = '1.0'

local message  = require('messagedat');
local packets  = require('packets');
local res      = require('resources');
local wildcard = require('wildcard');
local settings = {
    Debug = false,
    DetectParty = true,
    DetectAlliance = true
};


local triggers = {
    AllText = require('triggers.alltext'),
    Chat = require('triggers.chat'),
    ChatMon = require('triggers.chatmon'),
    DebuffedByStatus = require('triggers.debuffedbystatus'),
    DebuffingByStatus = require('triggers.debuffingbystatus'),
    DebuffedBySpell = require('triggers.debuffedbyspell'),
    DebuffingBySpell = require('triggers.debuffingbyspell'),
    LostBuff = require('triggers.lostbuff'),
    LostDebuff = require('triggers.lostdebuff'),
    MessageDat = require('triggers.messagedat'),
    MiscActions = require('triggers.miscactions'),
    MobDispelled = require('triggers.mobdispelled'),
    MobReadies = require('triggers.mobreadies'),
    MobUses = require('triggers.mobuses'),
    TreasureHunterUpgrade = require('triggers.treasurehunterupgrade'),
};

local function BuildPattern(entry, name)
    if (entry.Wildcard ~= nil) then
        if entry.CaseSensitive ~= true then
            entry.ProcessedWildcard = wildcard:Convert(string.gsub(string.lower(entry.Wildcard), '%$name', string.lower(name)));
        else
            entry.ProcessedWildcard = wildcard:Convert(string.gsub(entry.Wildcard, '%$name', name));
        end
    end
    if (entry.Pattern ~= nil) then
        if entry.CaseSensitive ~= true then
            entry.ProcessedPattern = string.gsub(string.lower(entry.Pattern), '%$name', string.lower(name));
        else
            entry.ProcessedPattern = string.gsub(entry.Pattern, '%$name', name);
        end
    end
    if type(entry.Mode) == 'table' then
        entry.Mode = T(entry.Mode);
    end
end

local function BuildPatterns(name)
    for _,entry in ipairs(triggers.Chat) do
        BuildPattern(entry, name);
    end
    for _,entry in ipairs(triggers.AllText) do
        BuildPattern(entry, name);
    end
end
local currentName;
do
    local player = windower.ffxi.get_player();
    currentName = player and string.lower(player.name) or '$name';
    BuildPatterns(currentName);
end

local function ParseActionPacket(data)
    local bitData = data;
    local bitOffset = 40;
    local function UnpackBits(length)
        local value = bitData:unpack('b' .. length, (bitOffset / 8):floor() + 1, bitOffset % 8 + 1);
        bitOffset = bitOffset + length;
        return value;
    end

    local actionPacket = T {};
    actionPacket.UserId = UnpackBits(32);
    local targetCount = UnpackBits(6);
    bitOffset = bitOffset + 4;
    actionPacket.Type = UnpackBits(4);
    actionPacket.Id = UnpackBits(17);
    bitOffset = bitOffset + 15;
    actionPacket.Recast = UnpackBits(32);

    actionPacket.Targets = T {};
    for i = 1, targetCount do
        local target = T {};
        target.Id = UnpackBits(32);
        local actionCount = UnpackBits(4);
        target.Actions = T {};
        for j = 1, actionCount do
            local action = T {};
            action.Reaction = UnpackBits(5);
            action.Animation = UnpackBits(12);
            action.SpecialEffect = UnpackBits(7);
            action.Knockback = UnpackBits(3);
            action.Param = UnpackBits(17);
            action.Message = UnpackBits(10);
            action.Flags = UnpackBits(31);

            local hasAdditionalEffect = (UnpackBits(1) == 1);
            if hasAdditionalEffect then
                local additionalEffect = T {};
                additionalEffect.Damage = UnpackBits(10);
                additionalEffect.Param = UnpackBits(17);
                additionalEffect.Message = UnpackBits(10);
                action.AdditionalEffect = additionalEffect;
            end

            local hasSpikesEffect = (UnpackBits(1) == 1);
            if hasSpikesEffect then
                local spikesEffect = T {};
                spikesEffect.Damage = UnpackBits(10);
                spikesEffect.Param = UnpackBits(14);
                spikesEffect.Message = UnpackBits(10);
                action.SpikesEffect = spikesEffect;
            end

            target.Actions:append(action);
        end
        actionPacket.Targets:append(target);
    end

    return actionPacket;
end

local partyKeys = { 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' };
local allyKeys = { 'a10', 'a11', 'a12', 'a13', 'a14', 'a15', 'a20', 'a22', 'a22', 'a23', 'a24', 'a25' }
local function GetTriggerIds()
    local party = windower.ffxi.get_party();
    local ids = T {};

    if (settings.DetectParty) then
        for _, key in ipairs(partyKeys) do
            local val = party[key];
            if val and (val.mob) and (val.mob.id) then
                ids:append(val.mob.id);
            end
        end
    else
        local val = party['p0'];
        if val and (val.mob) and (val.mob.id) then
            ids:append(val.mob.id);
        end
    end

    if (settings.DetectAlliance) then
        for _, key in ipairs(allyKeys) do
            local val = party[key];
            if val and (val.mob) and (val.mob.id) then
                ids:append(val.mob.id);
            end
        end
    end

    return ids;
end

local function EvaluateTriggers(category, key)
    local triggerTable = triggers[category];
    local trigger = triggerTable[key];
    if trigger then
        if settings.Debug then
            print(string.format('Triggered!  Category:%s Param:%s File:%s', category, tostring(key), trigger));
        end
        windower.play_sound(string.format("%sresources/audio/%s", windower.addon_path, trigger));
        return true;
    else
        if settings.Debug then
            print(string.format('Triggered!  Category:%s Param:%s File:None', category, tostring(key)));
        end
        return false;
    end
end

local function EvaluateChatEntry(entry, params)
    local message = (entry.CaseSensitive == true) and params.Message or params.LowerMessage;

    if (entry.ProcessedWildcard ~= nil) then
        if not string.match(message, entry.ProcessedWildcard) then
            return false;
        end
    end
    if (entry.ProcessedPattern ~= nil) then
        if not string.match(message, entry.ProcessedPattern) then
            return false;
        end
    end

    if (entry.Mode ~= nil) then
        if type(entry.Mode) == 'table' then
            if (entry.Mode:contains(params.Mode) == false) then
                return false;
            end
        elseif (entry.Mode ~= params.Mode) then
            return false;
        end
    end

    if (entry.Sender ~= nil) and (string.lower(entry.Sender) ~= params.Sender) then
        return false;
    end

    return true;
end
local function EvaluateChat(params)
    for _,entry in ipairs(triggers.Chat) do
        if EvaluateChatEntry(entry, params) and type(entry.Sound) == 'string' then
            windower.play_sound(string.format("%sresources/audio/%s", windower.addon_path, entry.Sound));
            if settings.Debug then
                print(string.format('Triggered!  Category:Chat Param:%s File:%s', params.Message, entry.Sound));
            end
        end
    end
end

windower.register_event('incoming chunk', function(id, data)
    if (id == 0x00A) then
        local packet = packets.parse('incoming', data);
        local name = packet['Player Name'];
        if name ~= currentName then
            BuildPatterns(name);
            currentName = name;
        end
    end
    if (id == 0x017) then
        local player = (windower.ffxi.get_player() or {});
        local packet = packets.parse('incoming', data);
        if (packet.Mode == 12) then
            EvaluateTriggers('ChatMon', 'GM');
        end
        if (packet.Mode == 3) and (packet['Sender Name'] ~= player.name) then
            EvaluateTriggers('ChatMon', 'Tell');
        end
        if (player.name ~= nil) and (packet.Message:lower():contains(player.name:lower())) then
            EvaluateTriggers('ChatMon', 'Talk');
        end
        local parsed = windower.convert_auto_trans(packet.Message);
        local params = {
            Message = parsed,
            LowerMessage = string.lower(parsed),
            Mode = res.chat[packet.Mode].en,
            Sender = packet['Sender Name'],
        };
        EvaluateChat(params);
    end
    if (id == 0x28) then
        local packet = ParseActionPacket(data);
        local ids = GetTriggerIds();

        --Action is being used by a monster
        if (packet.UserId > 1000000) then
            for _, target in ipairs(packet.Targets) do
                local targetsSelf = target.Id == ids[1];

                for _, action in ipairs(target.Actions) do
                    local messageId = action.Message;
                    if (T { 43, 675 }:contains(messageId)) then
                        local param = action.Param;
                        local skillData = param < 256 and res.weapon_skills[param] or res.monster_abilities[param];
                        if skillData then
                            EvaluateTriggers("MobReadies", skillData.en);
                        end

                        --Monster is readying ability..
                    elseif (messageId == 326) then
                        local abilData = res.job_abilities[action.Param];
                        if abilData then
                            EvaluateTriggers("MobReadies", abilData.en);
                        end

                        --Monster starts casting spell..
                    elseif (T { 3, 327 }:contains(messageId)) then
                        local spellData = res.spells[action.Param];
                        if spellData then
                            EvaluateTriggers("MobReadies", spellData.en);
                        end

                        --Monster starts casting weaponskill..
                    elseif (messageId == 716) then
                        local wsData = res.weapon_skills[action.Param];
                        if wsData then
                            EvaluateTriggers("MobReadies", wsData.en);
                        end

                        --Monster uses ability..
                    elseif (T { 100, 102, 108, 110, 119, 122, 734, 738 }:contains(messageId)) then
                        local abilityData = res.job_abilities[packet.Id];
                        if abilityData then
                            EvaluateTriggers("MobUses", abilityData.en);
                        end

                        --Monster uses weaponskill..
                    elseif (T { 101, 135 }:contains(messageId)) then
                        local wsData = res.monster_abilities[packet.Id];
                        if wsData then
                            EvaluateTriggers("MobUses", wsData.en);
                        end
                    end

                    --Action targets self..
                    if (targetsSelf) then
                        --Debuff applied by id..
                        if T { 82, 127, 141, 160, 164, 203, 236, 237, 242, 243, 267, 268, 269, 270, 271, 272, 277, 278, 279, 320, 374, 375, 412, 645, 754, 755, 804 }:contains(messageId) then
                            if EvaluateTriggers("DebuffedByStatus", action.Param) == false then
                                local buffData = res.buffs[action.Param];
                                if buffData then
                                    EvaluateTriggers("DebuffedByStatus", buffData.en);
                                end
                            end

                            --Spell damage taken..
                        elseif T { 2, 7, 252 }:contains(messageId) then
                            if EvaluateTriggers("DebuffedBySpell", packet.Id) == false then
                                local spellData = res.spells[packet.Id];
                                if spellData then
                                    EvaluateTriggers("DebuffedBySpell", spellData.en);
                                end
                            end
                        end
                    end
                end
            end
        end

        --User is self..
        if (packet.UserId == ids[1]) then
            for _, target in ipairs(packet.Targets) do
                for _, action in ipairs(target.Actions) do
                    local messageId = action.Message;
                    EvaluateTriggers('MiscActions', messageId);
                end
            end
        end

        --Action is being used by someone who fits settings..
        if (ids:contains(packet.UserId)) then
            for _, target in ipairs(packet.Targets) do
                for _, action in ipairs(target.Actions) do
                    local messageId = action.Message;

                    --Debuff applied by id..
                    if T { 82, 127, 141, 160, 164, 203, 236, 237, 242, 243, 267, 268, 269, 270, 271, 272, 277, 278, 279, 320, 374, 375, 412, 645, 754, 755, 804 }:contains(messageId) then
                        if EvaluateTriggers("DebuffingByStatus", action.Param) == false then
                            local buffData = res.buffs[action.Param];
                            if buffData then
                                EvaluateTriggers("DebuffingByStatus", buffData.en);
                            end
                        end

                        --Spell damage taken..
                    elseif T { 2, 7, 252 }:contains(messageId) then
                        if EvaluateTriggers("DebuffingBySpell", packet.Id) == false then
                            local spellData = res.spells[packet.Id];
                            if spellData then
                                EvaluateTriggers("DebuffingBySpell", spellData.en);
                            end
                        end
                    elseif (T { 603, 608 }:contains(messageId)) then
                        EvaluateTriggers("TreasureHunterUpgrade", action.Param);
                    end
                end
            end
        end
    end

    if id == 0x029 then
        local action_message = packets.parse('incoming', data);
        local ids = GetTriggerIds();
        if (action_message['Actor'] == ids[1]) then
            if T { 64, 204, 206, 321, 322, 341, 342, 343, 344, 350, 351, 378, 531, 647 }:contains(action_message.Message) then                
                local trigger = (action_message.Target > 1000000) and "LostDebuff" or "LostBuff";
                if EvaluateTriggers(trigger, action_message['Param 1']) == false then
                    local buffData = res.buffs[action_message['Param 1']];
                    if buffData then
                        EvaluateTriggers(trigger, buffData.en);
                    end
                end
            else
                EvaluateTriggers('MiscActions', action_message.Message);
            end
        end
    end

    if id == 0x21 then
        EvaluateTriggers('ChatMon', 'Trade');
    end

    if id == 0x0DC then
        EvaluateTriggers('ChatMon', 'Invite');
    end

		-- -- Can be used, but you may have to update all the ['Message ID']'s
		-- if id == 0x02A then local resting_message = packets.parse('incoming', data)
		-- local zone = windower.ffxi.get_info().zone

				-- if     T{139, 144, 146}:contains (zone) and T{40516, 40747, 40470}:contains (resting_message['Message ID']) then windower.play_sound (windower.addon_path .. "resources/audio/Loud Thud.wav")
				-- elseif T{139, 144, 146}:contains (zone) and T{40517, 40748, 40471}:contains (resting_message['Message ID']) then windower.play_sound (windower.addon_path .. "resources/audio/Thud.wav")
				-- elseif T{139, 144, 146}:contains (zone) and T{40518, 40749, 40472}:contains (resting_message['Message ID']) then windower.play_sound (windower.addon_path .. "resources/audio/Noise.wav")
			-- --Abyssea Vistant
				-- elseif resting_message['Message ID'] == 40107 and resting_message['Param 1'] == 1  then windower.play_sound (windower.addon_path .. "resources/audio/1min.wav")
				-- elseif resting_message['Message ID'] == 40107 and resting_message['Param 1'] == 5  then windower.play_sound (windower.addon_path .. "resources/audio/5min.wav")
				-- elseif resting_message['Message ID'] == 40107 and resting_message['Param 1'] == 10 then windower.play_sound (windower.addon_path .. "resources/audio/10min.wav")
				-- elseif resting_message['Message ID'] == 40107 and resting_message['Param 1'] == 30 then windower.play_sound (windower.addon_path .. "resources/audio/30min.wav")
				-- end
		-- end

		-- if id == 0x027 then local string_message = packets.parse('incoming', data)
		-- local zone = windower.ffxi.get_info().zone

			-- --Nyzul Time
			-- if zone == 77 then
				-- if     string_message['Message ID'] == 40128 then windower.play_sound (windower.addon_path .. "resources/audio/Activated.wav")
				-- elseif string_message['Message ID'] == 40088 and string_message['Param 1'] == 1  then windower.play_sound (windower.addon_path .. "resources/audio/1min.wav")
				-- elseif string_message['Message ID'] == 40088 and string_message['Param 1'] == 5  then windower.play_sound (windower.addon_path .. "resources/audio/5min.wav")
				-- elseif string_message['Message ID'] == 40088 and string_message['Param 1'] == 10 then windower.play_sound (windower.addon_path .. "resources/audio/10min.wav")
				-- end
			-- end
		-- end

		-- if id == 0x036 then local npc_chat = packets.parse('incoming', data)
		-- local zone = windower.ffxi.get_info().zone

			-- --Nyzul objectives
			-- if zone == 77 then
				-- if     npc_chat['Message ID'] == 7372 then windower.play_sound (windower.addon_path .. "resources/audio/Boss.wav")
				-- elseif npc_chat['Message ID'] == 7373 then windower.play_sound (windower.addon_path .. "resources/audio/Leader.wav")
				-- elseif npc_chat['Message ID'] == 7374 then windower.play_sound (windower.addon_path .. "resources/audio/Family.wav")
				-- elseif npc_chat['Message ID'] == 7375 then windower.play_sound (windower.addon_path .. "resources/audio/Lamps.wav")
				-- elseif npc_chat['Message ID'] == 7376 then windower.play_sound (windower.addon_path .. "resources/audio/SpecEnemy.wav")
				-- elseif npc_chat['Message ID'] == 7377 then windower.play_sound (windower.addon_path .. "resources/audio/All.wav")
				-- elseif npc_chat['Message ID'] == 7378 then coroutine.sleep(1.45) windower.play_sound (windower.addon_path .. "resources/audio/Avoid Discovery.wav")
				-- elseif npc_chat['Message ID'] == 7379 then coroutine.sleep(1.45) windower.play_sound (windower.addon_path .. "resources/audio/Dont Destroy.wav")
				-- end
			-- end
		-- end

end);

local function EvaluateText(params)
    for _,entry in ipairs(triggers.AllText) do
        if EvaluateChatEntry(entry, params) and type(entry.Sound) == 'string' then
            windower.play_sound(string.format("%sresources/audio/%s", windower.addon_path, entry.Sound));
            if settings.Debug then
                print(string.format('Triggered!  Category:Text Param:%s File:%s', params.Message, entry.Sound));
            end
        end
    end
end

windower.register_event('emote', function(emote_id,sender_id,target_id)
    local myId = (windower.ffxi.get_player() or {}).id;
    if target_id == myId and sender_id ~= myId then
        EvaluateTriggers('ChatMon', 'Emote');
    end
end)

windower.register_event('examined', function(sender_name,sender_index)
    local myName = (windower.ffxi.get_player() or {}).name;
    if sender_name ~= myName then
        EvaluateTriggers('ChatMon', 'Examine');
    end
end)

windower.register_event('incoming text', function(original,modified,mode)
    local parsed = windower.convert_auto_trans(original);
    local params = {
        Message = parsed,
        LowerMessage = string.lower(parsed),
        Mode = mode,
    };
    EvaluateText(params);
end)

windower.register_event('addon command', function(...)
    local args = T{...};
    if args[1] == 'dumpdat' then
        local zoneId = tonumber(args[2]);
        if zoneId then
            local zoneData = res.zones[zoneId];
            local folderPath = "C:/Windower/addons/dumps";--string.format("%sdumps/", windower.addon_path);
            windower.create_dir(folderPath);
            local filePath = string.format("%s%u_%s.txt", folderPath, zoneId, zoneData and zoneData.en or "Unknown");
            print(filePath);
            --message:DumpToFile(zoneId, filePath);
        end
    end
end);
