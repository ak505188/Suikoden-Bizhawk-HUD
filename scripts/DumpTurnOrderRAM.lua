local RNG = 0x9010

local SAVESTATE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/TurnOrderRNGCall.State"
local OUTPUT_DIR = '/tmp/claude-1000/-home-alex-Projects-Suikoden-Bizhawk-HUD/2d239eb6-5108-43f2-9462-38fdcd17de5a/scratchpad/'

local function dumpRAM()
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
  return table.concat(pieces)
end

local function writeFile(name, content)
  local f = io.open(OUTPUT_DIR .. name, "wb")
  f:write(content)
  f:close()
end

-- Standard 32-bit LCG matching the documented RNG algorithm
local function nextRNG(x)
  -- emulate 32-bit unsigned multiply+add using Lua integer math (BizHawk Lua 5.4 has 64-bit ints)
  return (x * 0x41c64e6d + 0x3039) & 0xFFFFFFFF
end

local N_FRAMES = 10

-- Run C: unmodified (expect Viktor/slot2 first)
savestate.load(SAVESTATE)
local rngC0 = mainmemory.read_u32_le(RNG)
writeFile("C_pre.bin", dumpRAM())
for i = 1, N_FRAMES do emu.frameadvance() end
local rngC1 = mainmemory.read_u32_le(RNG)
writeFile("C_post.bin", dumpRAM())
client.screenshot(OUTPUT_DIR .. "C_screenshot.png")

-- Run D: RNG pushed forward by 1 step before the calls happen (expect Any/slot1 first)
savestate.load(SAVESTATE)
local rngD0 = mainmemory.read_u32_le(RNG)
local pushed = nextRNG(rngD0)
mainmemory.write_u32_le(RNG, pushed)
writeFile("D_pre.bin", dumpRAM())
for i = 1, N_FRAMES do emu.frameadvance() end
local rngD1 = mainmemory.read_u32_le(RNG)
writeFile("D_post.bin", dumpRAM())
client.screenshot(OUTPUT_DIR .. "D_screenshot.png")

print(string.format("RunC: rng0=0x%08x -> rng1=0x%08x", rngC0, rngC1))
print(string.format("RunD: rng0=0x%08x (pushed from 0x%08x) -> rng1=0x%08x", pushed, rngD0, rngD1))
print("done")
client.exit()
