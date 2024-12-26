local bit = require('bit');
require('pack');
require('table');

local cache = true;
local installPath = windower.ffxi_path;
local messageDatData = {};

local function GetDatPath(datId)
    for i = 1,10 do
        local vTablePath;
        if i == 1 then
            vTablePath = string.format('%sVTABLE.DAT', installPath);
        else
            vTablePath = string.format('%sROM%u\\VTABLE%u.DAT', installPath, i, i);
        end
        local vTable = io.open(vTablePath, 'rb');
        if vTable then
            vTable:seek('set', datId);
            local temp = vTable:read(1):unpack('C');
            if temp == i then
                local fTablePath;
                if i == 1 then
                    fTablePath = string.format('%sFTABLE.DAT', installPath);
                else
                    fTablePath = string.format('%sROM%u\\FTABLE%u.DAT', installPath, i, i);
                end
                local fTable = io.open(fTablePath, 'rb');

                if fTable then
                    fTable:seek('set', datId * 2);
                    local path = fTable:read(2):unpack('H');
                    if i == 1 then
                        return string.format('%sROM\\%u\\%u.DAT', installPath, bit.rshift(path, 7), bit.band(path, 0x7F));
                    else
                        return string.format('%sROM%u\\%u\\%u.DAT', installPath, i, bit.rshift(path, 7), bit.band(path, 0x7F));                        
                    end
                end
            end
        end
    end
    return nil;
end

local conversionMap = {};
for i = 0,255 do
    local key = string.char(i);
    local val = string.char(bit.bxor(i, 0x80));
    conversionMap[key] = val;
end
local function LoadMessageDatByPath(datPath)
    local dat = io.open(datPath, 'rb');
    if not dat then return; end

    local realSize = dat:seek('end');
    dat:seek('set');
    local datSize = dat:read(4):unpack('I') - 0x10000000;
    if (datSize ~= realSize - 4) then return; end
    
    local offsets = T{ bit.bxor(dat:read(4):unpack('I'), 0x80808080) };
    local count = (offsets[1] - 4)/4;
    for i = 1,count do
        offsets:append(bit.bxor(dat:read(4):unpack('I'), 0x80808080));
    end
    offsets:append(datSize);
    
    local outputTable = {};
    for i = 1,#offsets-1 do
        local len = (offsets[i + 1] - offsets[i]);
        local message = dat:read(len);
        message = string.gsub(message, '(.)', function(a) return conversionMap[a] end);
        outputTable[i-1] = { Id = i-1, Text = message };
    end
    dat:close();

    return outputTable;
end

local function LoadMessageDat(zone)
    if cache == false then
        messageDatData = {};
    end

    local datId;
    if (zone < 256) then
        datId = zone + 6420;
    elseif (zone < 1000) then
        datId = zone + 85335;
    else
        datId = zone + 67511;
    end
    if not datId then return false; end

    local datPath = GetDatPath(datId);
    if not datPath then return false; end
    
    local output = LoadMessageDatByPath(datPath);
    if (output == nil) then return false; end

    messageDatData[zone] = output;
    return true;
end


local function GetZoneMessage(self, zoneId, messageId)
    if messageDatData[zoneId] == nil then
        if not LoadMessageDat(zoneId) then
            return;
        end
    end

    local message = messageDatData[zoneId][bit.band(messageId, 0x7FFF)];
    if message then
        return message;
    end
end

local function DumpToFile(self, zoneId, fileName)
    print('Trying dump');
    local buffer = T{};

    for i = 1,0x7FFF do
        local msg = GetZoneMessage(self, zoneId, i);
        if msg then
            buffer:append(msg.Text);
        end
    end

    local outFile = io.open(fileName, 'w');
    if outFile then
        print('File open');
        for _,entry in ipairs(buffer) do
            outFile:write(string.format('%q\n\n', entry));
        end
        outFile:close();
    end
end

local exports = {
    DumpToFile = DumpToFile,
    GetZoneMessage = GetZoneMessage,
};

return exports;