local Charmap = require "lib.Charmap"
local Address = require "lib.Address"

local function memoryToStrTbl(address, rows)
  local str_tbl = {}
  local buffer = memory.read_bytes_as_array(Address.sanitize(address), 16 * rows)

  for i = 1, rows do
    local mem_hex = {}
    local mem_char = {}
    for j = 1, 16 do
      local pos = ((i - 1) * 16) + j
      local val = buffer[pos]
      table.insert(mem_hex, string.format("%02x", val))
      local char = Charmap.getChar(val)
      if char == nil or #char == 0 then
        char = " "
      end
      table.insert(mem_char, char)
    end

    local str = string.format("%06x %s %s", address + ((i-1)*16), table.concat(mem_hex, " "), table.concat(mem_char))
    table.insert(str_tbl, str)
  end

  return str_tbl
end

return {
  memoryToStrTbl = memoryToStrTbl
}
