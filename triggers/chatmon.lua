--[[
    This triggers on events that are commonly handled by chatmon/chatman.
    These are hardcoded and you cannot add new events without modifying the packet code.
]]--

return {
    ['GM'] = 'GM.wav',
    ['Tell'] = "IncomingTell.wav",
    ['Talk'] = "TalkedAbout.wav",
    ['Emote'] = "IncomingEmote.wav",
    ['Invite'] = "PartyInvite.wav",
    ['Examine'] = "Examined.wav",
    ['Trade'] = "TradeOffer.wav",
};