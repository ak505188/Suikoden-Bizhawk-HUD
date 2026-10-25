-- STATIC FINDING (Ghidra decompile, h_data.bin @ 0x80082c18, base 0x80080000, no live capture yet):
-- earth_golem_ai_select_target_and_move: standard front-row-only target scan (formationPos<4,
-- alive, not busy; ~49%-per-candidate RNG2 accept, retry next tick with fresh rolls if nobody
-- accepted). Once a target locks, rolls again:
--   (roll*100)/0x7fff < 0x47(71)  -> return -1 (decline -> plain Attack) [~71%]
--   otherwise                     -> commit to special move (next micro-state LAB_80083a2c,
--                                     returns 1) [~29%]
-- Same threshold shape as Clay Doll/Rock Buster.
--
-- NO SAVESTATE EXISTS - not runnable yet. Once you have a savestate positioned in a battle against
-- an Earth Golem, fill in SAVESTATE/ENEMY_SLOT below and run via scripts/spawn-headless-emuhawk.sh.
-- Checks the live per-instance MonsterRecord this enemy resolves to (pAttackDataTable[bId] chain)
-- against this static finding.
--
-- USAGE (once a savestate exists): edit SAVESTATE and ENEMY_SLOT below, then
--   scripts/spawn-headless-emuhawk.sh scripts/AIStaticChecks/CheckEarthGolemAI.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local Charmap = require "lib.Charmap"

local SAVESTATE = nil -- TODO fill in
local ENEMY_SLOT = nil -- TODO fill in (1-indexed combatant slot)

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckEarthGolemAI.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

if SAVESTATE == nil then
  log("No savestate configured yet - this script only documents the static finding above.")
  log("Static finding: AI @ 0x80082c18 in h_data.bin (base 0x80080000), front-row-only target")
  log("scan, then ~71% Attack / ~29% special move.")
else
  local ok, err = pcall(function()
    savestate.load(SAVESTATE)
    for i = 1, 10 do emu.frameadvance() end

    local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))
    local rowArray = Address.sanitize(mainmemory.read_u32_le(base + 0x1344))
    local enemyDataAddr = base + 0x50 + ENEMY_SLOT * 0x8c
    local bId = mainmemory.read_u8(enemyDataAddr)
    local recordAddr = Address.sanitize(mainmemory.read_u32_le(rowArray + bId * 4))
    local name = Charmap.readStringFromMemory(recordAddr, 16)
    local aiFuncAddr = mainmemory.read_u32_le(recordAddr + 0x30)

    log(string.format("slot %d: bId=%d name=%q record=0x%08x aiFunc=0x%08x",
      ENEMY_SLOT, bId, name, recordAddr, aiFuncAddr))
    log(string.format("Expected aiFunc: 0x80082c18 - match: %s", tostring(aiFuncAddr == 0x80082c18)))
  end)
  if not ok then log("ERROR: " .. tostring(err)) end
end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
if SAVESTATE ~= nil then client.exit() end
