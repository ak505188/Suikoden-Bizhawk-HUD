local charmap = {
	[0x00]='',
	[0x01]='',
	[0x02]='',
	[0x03]='',
	[0x04]='',
	[0x05]='',
	[0x06]='',
	[0x07]='',
	[0x08]='',
	[0x09]='',
	[0x0a]='',
	[0x0b]='',
	[0x0c]='',
	[0x0d]='',
	[0x0e]='',
	[0x0f]='',
	[0x10]=' ',
	[0x11]='a',
	[0x12]='b',
	[0x13]='c',
	[0x14]='d',
	[0x15]='e',
	[0x16]='f',
	[0x17]='g',
	[0x18]='h',
	[0x19]='i',
	[0x1a]='j',
	[0x1b]='k',
	[0x1c]='l',
	[0x1d]='m',
	[0x1e]='n',
	[0x1f]='o',
	[0x20]='p',
	[0x21]='q',
	[0x22]='r',
	[0x23]='s',
	[0x24]='t',
	[0x25]='u',
	[0x26]='v',
	[0x27]='w',
	[0x28]='x',
	[0x29]='y',
	[0x2a]='z',
	[0x2b]='A',
	[0x2c]='B',
	[0x2d]='C',
	[0x2e]='D',
	[0x2f]='E',
	[0x30]='F',
	[0x31]='G',
	[0x32]='H',
	[0x33]='I',
	[0x34]='J',
	[0x35]='K',
	[0x36]='L',
	[0x37]='M',
	[0x38]='N',
	[0x39]='O',
	[0x3a]='P',
	[0x3b]='Q',
	[0x3c]='R',
	[0x3d]='S',
	[0x3e]='T',
	[0x3f]='U',
	[0x40]='V',
	[0x41]='W',
	[0x42]='X',
	[0x43]='Y',
	[0x44]='Z',
	[0x45]='0',
	[0x46]='1',
	[0x47]='2',
	[0x48]='3',
	[0x49]='4',
	[0x4a]='5',
	[0x4b]='6',
	[0x4c]='7',
	[0x4d]='8',
	[0x4e]='9',
	[0x4f]=':',
	[0x50]=';',
	[0x51]='"',
	[0x52]='\'',
	[0x53]='\'',
	[0x54]='&',
	[0x55]=',',
	[0x56]='.',
	[0x57]='!',
	[0x58]='?',
	[0x59]='(',
	[0x5a]=')',
	[0x5b]='+',
	[0x5c]='-',
}

local reverseCharmap = {
	[' ']=0x10,
	['a']=0x11,
	['b']=0x12,
	['c']=0x13,
	['d']=0x14,
	['e']=0x15,
	['f']=0x16,
	['g']=0x17,
	['h']=0x18,
	['i']=0x19,
	['j']=0x1a,
	['k']=0x1b,
	['l']=0x1c,
	['m']=0x1d,
	['n']=0x1e,
	['o']=0x1f,
	['p']=0x20,
	['q']=0x21,
	['r']=0x22,
	['s']=0x23,
	['t']=0x24,
	['u']=0x25,
	['v']=0x26,
	['w']=0x27,
	['x']=0x28,
	['y']=0x29,
	['z']=0x2a,
	['A']=0x2b,
	['B']=0x2c,
	['C']=0x2d,
	['D']=0x2e,
	['E']=0x2f,
	['F']=0x30,
	['G']=0x31,
	['H']=0x32,
	['I']=0x33,
	['J']=0x34,
	['K']=0x35,
	['L']=0x36,
	['M']=0x37,
	['N']=0x38,
	['O']=0x39,
	['P']=0x3a,
	['Q']=0x3b,
	['R']=0x3c,
	['S']=0x3d,
	['T']=0x3e,
	['U']=0x3f,
	['V']=0x40,
	['W']=0x41,
	['X']=0x42,
	['Y']=0x43,
	['Z']=0x44,
	['0']=0x45,
	['1']=0x46,
	['2']=0x47,
	['3']=0x48,
	['4']=0x49,
	['5']=0x4a,
	['6']=0x4b,
	['7']=0x4c,
	['8']=0x4d,
	['9']=0x4e,
	[':']=0x4f,
	[';']=0x50,
	['"']=0x51,
	['\'']=0x52,
	-- ['\'']=0x53,
	['&']=0x54,
	[',']=0x55,
	['.']=0x56,
	['!']=0x57,
	['?']=0x58,
	['(']=0x59,
	[')']=0x5a,
	['+']=0x5b,
	['-']=0x5c,
}

local function getChar(num)
	return charmap[num]
end

local function getStr(list)
	local str = ""
	for i=1,#list do
		str = str .. getChar(list[i])
	end
	return str
end

local function strToHex(str)
	local list = {}
	for i=0,#str do
		list[i] = reverseCharmap[str:sub(i,i)]
	end
	return list
end

local function readStringFromList(list, startOfStr, endOfStr)
  startOfStr = startOfStr or 1
  endOfStr = endOfStr or #list
  local str = ""
  for i = 1,endOfStr,1 do
    local code = list[i]
    if code == 0 then return str end
    local char = getChar(code)
    if char == nil then return end
    str = str .. char
  end
  return str
end

local function readStringFromMemory(address, length)
  length = length or 16
  local str = ""
  for i = 0, length-1 do
    local code = memory.read_u8(address + i)
    if code == 0 then return str end
    local char = getChar(code)
    str = str .. char
  end
  return str
end

return {
  charmap = charmap,
  reverseCharmap = reverseCharmap,
  getChar = getChar,
  getStr = getStr,
  strToHex = strToHex,
  readStringFromList = readStringFromList,
  readStringFromMemory = readStringFromMemory
}
