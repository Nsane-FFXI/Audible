addon.name      = 'Audible';
addon.author    = 'Thorny, concept and sounds by Nsane';
addon.version   = '1.00';
addon.desc      = 'Plays audio cues based on predefined events.';
addon.link      = 'https://ashitaxi.com/';

require('common');

local settings = {
    DetectParty = false,
    DetectAlliance = false
};

local triggers = {
    DebuffedByStatus = require('triggers.debuffedbystatus'),
    DebuffingByStatus = require('triggers.debuffingbystatus'),
    DebuffedBySpell = require('triggers.debuffedbyspell'),
    DebuffingBySpell = require('triggers.debuffingbyspell'),
    LostBuff = require('triggers.lostbuff'),
    MiscActions = require('triggers.miscactions'),
    MobReadies = require('triggers.mobreadies'),
    MobUses = require('triggers.mobuses'),
    TreasureHunterUpgrade = require('triggers.treasurehunterupgrade'),
};

local function ParseActionPacket(e)
    local bitData;
    local bitOffset;
    local function UnpackBits(length)
        local value = ashita.bits.unpack_be(bitData, 0, bitOffset, length);
        bitOffset = bitOffset + length;
        return value;
    end

    local actionPacket = T{};
    bitData = e.data_raw;
    bitOffset = 40;
    actionPacket.UserId = UnpackBits(32);
    local targetCount = UnpackBits(6);
    bitOffset = bitOffset + 4;
    actionPacket.Type = UnpackBits(4);
    actionPacket.Id = UnpackBits(17);
    bitOffset = bitOffset + 15;
    actionPacket.Recast = UnpackBits(32);
    
    actionPacket.Targets = T{};
    for i = 1,targetCount do
        local target = T{};
        target.Id = UnpackBits(32);
        local actionCount = UnpackBits(4);
        target.Actions = T{};
        for j = 1,actionCount do
            local action = {};
            action.Reaction = UnpackBits(5);
            action.Animation = UnpackBits(12);
            action.SpecialEffect = UnpackBits(7);
            action.Knockback = UnpackBits(3);
            action.Param = UnpackBits(17);
            action.Message = UnpackBits(10);
            action.Flags = UnpackBits(31);

            local hasAdditionalEffect = (UnpackBits(1) == 1);
            if hasAdditionalEffect then
                local additionalEffect = {};
                additionalEffect.Damage = UnpackBits(10);
                additionalEffect.Param = UnpackBits(17);
                additionalEffect.Message = UnpackBits(10);
                action.AdditionalEffect = additionalEffect;
            end

            local hasSpikesEffect = (UnpackBits(1) == 1);
            if hasSpikesEffect then
                local spikesEffect = {};
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
        windower.play_sound(windower.addon_path .. "FFaudio/" .. trigger);
        return true;
    end
end


ashita.events.register('packet_in', 'HandleIncomingPacket', function (e)
    if (e.id == 0x28) then
        local packet = ParseActionPacket(e);
        
        local ids = GetTriggerIds();

        --Action is being used by a monster
        if (packet.UserId > 1000000) then
            for _, target in ipairs(packet.Targets) do
                local targetsSelf = target.Id == ids[1];

                for _, action in ipairs(target.Actions) do
                    local messageId = action.Message;

                    --Monster is readying skill..
                    if (T { 43, 675 }:contains(messageId)) then
                        local skillData = res.monster_skills[action.Param];
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
                    elseif (T { 100, 119, 734, 738 }:contains(messageId)) then
                        local abilityData = res.job_abilities[action.Param];
                        if abilityData then
                            EvaluateTriggers("MobUses", abilityData.en);
                        end

                        --Monster uses weaponskill..
                    elseif (T { 101, 135 }:contains(messageId)) then
                        local wsData = res.weapon_skills[action.Param];
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
    
    if e.id == 0x029 then
        local action_message = packets.parse('incoming', data);
        local ids = GetTriggerIds();
        if (action_message['Actor'] == ids[1]) and T{64, 204, 206, 321, 322, 341, 342, 343, 344, 350, 351, 378, 531, 647}:contains(action_message.Message) then
            if EvaluateTriggers("LostBuff", action_message['Param 1']) == false then
                local buffData = res.buffs[action_message['Param 1']];
                if buffData then
                    EvaluateTriggers("LostBuff", buffData.en);
                end
            end
        else
            EvaluateTriggers('MiscActions', action_message.Message);
        end
    end
end);

