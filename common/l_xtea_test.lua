local B = require'binary'
local D = require'util'
local xtea = require'xtea'

function enc (key0, key1, data) return B.bin2hex (xtea.encipher (B.hex2bin(data), B.hex2bin(key0..key1)), 4) end
assert (enc ("00000000 00000000", "00000000 00000000", "00000000 00000000") == "d8d4e9de d91e13f7")
assert (enc ("2B020568 06144976", "775D0E26 6C287843", "74657374 206D652E") == "94ebc896 846a49a8")
assert (enc ("09654311 66443925", "513A1610 0A08126E", "6C6F6E67 65725F74") == "3eceae22 6056a89d")
assert (enc ("09654311 66443925", "513A1610 0A08126E", "6573745F 76656374") == "774dd4b4 8724e39a")
function enc2 (data) return enc ("4D763217 053F752C", "5D041636 1572632F", data) end
assert (enc2"54656120 69732067" == "99819f5d 6f4b313a")
assert (enc2"6F6F6420 666F7220" == "86ff6fd0 e3877007")
assert (enc2"796F7521 21212072" == "4db8cff3 9950b3d4")
assert (enc2"65616C6C 79212121" == "73a2fac9 16595d81")
function dec (key0, key1, data) return B.bin2hex (xtea.decipher (B.hex2bin(data), B.hex2bin(key0..key1)), 4) end
assert (dec ("00000000 00000000", "00000000 00000000", "D8D4E9DE D91E13F7") == "00000000 00000000")
assert (dec ("2B020568 06144976", "775D0E26 6C287843", "94EBC896 846A49A8") == "74657374 206d652e")
function dec1 (data) return dec ("09654311 66443925", "513A1610 0A08126E", data) end
assert (dec1"3ECEAE22 6056A89D" == "6c6f6e67 65725f74")
assert (dec1"774DD4B4 8724E39A" == "6573745f 76656374")
function dec2 (data) return dec ("4D763217 053F752C", "5D041636 1572632F", data) end
assert (dec2"99819F5D 6F4B313A" == "54656120 69732067")
assert (dec2"86FF6FD0 E3877007" == "6f6f6420 666f7220")
assert (dec2"4DB8CFF3 9950B3D4" == "796f7521 21212072")
assert (dec2"73A2FAC9 16595D81" == "65616c6c 79212121")
D.green'tests passed'()
