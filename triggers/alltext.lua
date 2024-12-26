--[[
    This triggers on all chat going through the chat log.  This is *very* expensive to cpu relative to all other triggers.
    If you have hundreds of entries, you are likely to use slowdown, so try not to use it for things that can fit elsewhere.

    Each entry has multiple possible parameters:
        CaseSensitive (boolean) - If this is set to true, capital letters must match in patterns and wildcards.  Default if not specified is false.
        Pattern (string) - A lua pattern to match against the content of the message.  If specified, the content must match this for the sound to play.
        Wildcard (string) - A wildcard string to match against the content of the message.  If specified, the content must match this for the sound to play.
        Mode (number) - If specified, only examines chat in this mode.  Very helpful for reducing load if you know what mode your chat will be in.
            -A table of multiple options is allowed: Mode = { 2, 4, 5 }
        Sound (string) - The sound file to use.

    WARNING: Due to a common function, if you set the Sender parameter for entries here they will not work.  There is no sender for generic text.  Do not set it.
    This is most likely to happen if you copy/paste your entries from chat to alltext.
]]--

return {};