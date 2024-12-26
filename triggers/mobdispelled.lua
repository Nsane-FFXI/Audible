--[[
    Entries here trigger when you or a party/alliance member(if enabled) cast a spell that removes buffs from a monster.
    This is intended for spells that explicitly state the buff, such as 'Player casts dispel.  Mob's haste effect disappears!'.
    Status effects can be listed by ID or by name.  If both are present, ID takes priority.
]]--

return {
    [33] = 'MobDispelled/Haste.wav',
};