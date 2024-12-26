--[[
    This matches message dat strings.  They need to be added in a specific format, to find a new message dat entry:
        -Get the zone ID for a zone that contains your message (https://github.com/Windower/Resources/blob/master/resources_data/zones.lua is one option for list)
        -Type the command (windower)'//lua c audible dumpdat 3' or (ashita)'/audible dumpdat 3', where 3 would be the zone ID to dump the dat to file.
        -Look at the file, which will be located in 'windower/addons/audible/dumps/3_Manaclipper.txt' or 'ashita/addons/audible/dumps/3_Manaclipper.txt'
        -Use ctrl-f or other method to locate the message.  Avoid searching for parts of the message that vary for the best results, since they can be tokenized.
        -Copy the exact string for the message you want as key.
]]--
return {

};