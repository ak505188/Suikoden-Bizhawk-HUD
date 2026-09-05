-- Hardcoded to avoid depending on package.path / require resolution,
-- which varies depending on how EmuHawk was launched (cwd-relative).
local GAMESTATE = 0x1B9BBC
local ENEMY_GROUP_PTR = 0x197F10
local ENCOUNTER_TABLE_PTR = 0x197F14

local SAVESTATE_DIR = '/home/alex/Local/BizHawk-2.10-linux-x64/PSX/State/Suikoden/Simulations/'
local BASE_SAVE = SAVESTATE_DIR .. 'NeclordBS.State'
local OUTPUT_DIR = '/tmp/claude-1000/-home-alex-Projects-Suikoden-Bizhawk-HUD/2d239eb6-5108-43f2-9462-38fdcd17de5a/scratchpad/'

savestate.load(BASE_SAVE)
emu.frameadvance()

local gamestate = mainmemory.read_u8(GAMESTATE)
local enemy_group_ptr = mainmemory.read_u32_le(ENEMY_GROUP_PTR)
local encounter_table_ptr = mainmemory.read_u32_le(ENCOUNTER_TABLE_PTR)

print(string.format("gamestate=%d enemy_group_ptr=0x%x encounter_table_ptr=0x%x", gamestate, enemy_group_ptr, encounter_table_ptr))

local CHUNK = 4096
local RAM_SIZE = 0x200000
local pieces = {}
for offset = 0, RAM_SIZE - 1, CHUNK do
  local bytes = memory.read_bytes_as_array(offset, CHUNK)
  local chars = {}
  for i = 1, #bytes do
    chars[i] = string.char(bytes[i])
  end
  pieces[#pieces + 1] = table.concat(chars)
end
local ram = table.concat(pieces)

local f = io.open(OUTPUT_DIR .. "neclord_battle_ram.bin", "wb")
f:write(ram)
f:close()

print(string.format("dumped %d bytes to %sneclord_battle_ram.bin", #ram, OUTPUT_DIR))

client.screenshot(OUTPUT_DIR .. "neclord_battle_screenshot.png")

print("done")
client.exit()
