if AshitaCore then
    require('ashita4');
elseif ashita then
    require('ashita3');
elseif windower then
    require('windower4');
else
    print('Could not detect platform.');
end