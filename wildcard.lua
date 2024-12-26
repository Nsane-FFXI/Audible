local swapTable = {
    ['('] ="%(",
    [')'] ="%)",
    ['.'] ="%.",
    ['%'] ="%%",
    ['+'] ="%+",
    ['-'] ="%-",
    ['*'] =".*",
    ['?'] ="%?",
    ['['] ='%[',
    [']'] ='%]',
    ['^'] ='%^',
    ['$'] ='%$',
};

local WildcardToPattern = function(self, wildcard)
    local newString = string.gsub(wildcard, '(.)', function(char)
        local swap = swapTable[char];
        if swap then
            return swap;
        else
            return char;
        end
    end);
    return '^' .. newString .. '$';
end

local exports = {
    Convert = WildcardToPattern;
};
return exports;