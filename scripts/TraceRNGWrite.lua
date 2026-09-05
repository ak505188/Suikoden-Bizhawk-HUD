local RNG = 0x9010
local SAVESTATE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/TurnOrderRNGCall.State"
local OUTPUT_DIR = '/tmp/claude-1000/-home-alex-Projects-Suikoden-Bizhawk-HUD/2d239eb6-5108-43f2-9462-38fdcd17de5a/scratchpad/'

local log = {}

local function tryRegisters()
  local names = {"pc", "PC", "cpu.pc", "R15", "Pc"}
  for _, n in ipairs(names) do
    local ok, val = pcall(function() return emu.getregister(n) end)
    log[#log+1] = string.format("getregister(%s) -> ok=%s val=%s", n, tostring(ok), tostring(val))
  end
  local ok, regs = pcall(function() return emu.getregisters() end)
  if ok then
    for k, v in pairs(regs) do
      log[#log+1] = string.format("register %s = 0x%x", k, v)
    end
  else
    log[#log+1] = "emu.getregisters() failed: " .. tostring(regs)
  end
end

local hitcount = 0
local function onRNGWrite(addr, val)
  hitcount = hitcount + 1
  local ok, pc = pcall(function() return emu.getregister("pc") end)
  log[#log+1] = string.format("WRITE #%d to 0x%x value=0x%x pc_ok=%s pc=%s", hitcount, addr, val or -1, tostring(ok), tostring(pc))
end

savestate.load(SAVESTATE)
tryRegisters()

local regOk, regErr = pcall(function()
  memory.registerwrite(RNG, onRNGWrite)
end)
log[#log+1] = string.format("registerwrite ok=%s err=%s", tostring(regOk), tostring(regErr))

for i = 1, 20 do
  emu.frameadvance()
end

local f = io.open(OUTPUT_DIR .. "trace_rng_write.txt", "w")
f:write(table.concat(log, "\n"))
f:close()

print("done, hits=" .. hitcount)
client.exit()
