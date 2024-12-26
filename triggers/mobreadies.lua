--[[
    This triggers when a mob begins casting a spell or readies a weaponskill or job ability.
    If any of the listed abilities are present, the matching sound will be played.
    You must use names not IDs, since all actions are converted to text prior to this check [Abilities, WS, and Spells all have different IDs.]
]]--

return {
    --Aita
    ["Fulminous Smash"] = "Fulminous Smash.wav",
    ["Flaming Kick"]= "Flaming Kick.wav",
    ["Icy Grasp"] = "Icy Grasp.wav",
    ["Flashflood"] = "Flashflood.wav",
    ["Eroding Flesh"] = "Eroding Flesh.wav",
    ["Vivisection"] = "Vivisection.wav",

    --Aminon
    ["Demonfire"] = "Demonfire.wav",
    ["Frozen Blood"] = "Frozen Blood.wav",
    ["Blast of Reticence"] = "Blast of Reticence.wav",
    ["Ensepulcher"] = "Ensepulcher.wav",
    ["Ceaseless Surge"] = "Ceaseless Surge.wav",
    ["Torrential Pain"] = "Torrential Pain.wav",

    --Dhartok
    ["Cesspool"] = "Cesspool.wav",

    --Gartell
    ["Shrieking Gale"] = "Shrieking Gale.wav",
    ["Undulating Shockwave"] = "Undulating Shockwave.wav",

    ['Dread Spikes'] = 'Mob Dread Spikes.wav',
};