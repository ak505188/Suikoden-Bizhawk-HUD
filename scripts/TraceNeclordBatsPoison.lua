-- Live capture: event.onmemorywrite doesn't fire reliably on this PSX core (matches this
-- project's own earlier finding re: event.onmemoryexecute on calc_damage), so instead poll
-- the target's own enemy_data fields every frame - pScriptCursor (+12), state (+0x42),
-- combatant_rec's own status byte (+0x4a) - to build a fine timeline and see exactly which
-- script address is executing on the target the moment poison lands.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"

local SAVESTATE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/NeclordBats.State"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/TraceNeclordBatsPoison2.txt"
local COMBATANT_BASE = 0xb94
local ENEMY_DATA_BASE = 0x50
local TARGET_SLOT = 1 -- confirmed via the earlier run: this is who got poisoned
local MAX_FRAMES = 700

local log = {}
local function out(s) table.insert(log, s); console.log(s) end

savestate.load(SAVESTATE)
local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))
out(string.format("battle base = 0x%x, initial RNG = 0x%08x", base, mainmemory.read_u32_le(Address.RNG)))

local edAddr = base + ENEMY_DATA_BASE + TARGET_SLOT * 0x8c
local statusAddr = base + COMBATANT_BASE + TARGET_SLOT * 0x54 + 0x4a

local lastCursor, lastState, lastStatus, lastBusy

for frame = 0, MAX_FRAMES do
  local cursor = mainmemory.read_u32_le(edAddr + 12)
  local state = mainmemory.read_u16_le(edAddr + 0x42)
  local status = mainmemory.read_u8(statusAddr)
  local busy = mainmemory.read_u8(edAddr + 5)
  if cursor ~= lastCursor or state ~= lastState or status ~= lastStatus or busy ~= lastBusy then
    out(string.format("frame=%d cursor=0x%08x state=%d busy=%d status=%d",
      frame, cursor, state, busy, status))
    lastCursor, lastState, lastStatus, lastBusy = cursor, state, status, busy
  end
  emu.frameadvance()
end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(log, "\n") .. "\n"); file:close() end
client.exit()
