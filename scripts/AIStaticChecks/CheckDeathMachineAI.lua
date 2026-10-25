-- STATIC FINDING (Ghidra decompile, vc3.bin, base 0x80010000, no live capture yet):
-- Death Machine has TWO monster records in this area file, each with its OWN separate (but
-- byte-for-byte identical) AI function:
--   death_machine_a_ai_select_target_and_move @ 0x80010360
--   death_machine_b_ai_select_target_and_move @ 0x80010d0c
-- Both are the standard generic template already confirmed live for several other monsters:
-- front-row-only target scan (formationPos<4, alive, not busy; ~49%-per-candidate RNG2 accept,
-- retry next tick with fresh rolls if nobody accepted), then return -1 unconditionally once a
-- target locks (AI declines to act specially) - falls back to battle_execute_player_attack, i.e.
-- Death Machine ALWAYS uses a plain physical Attack, never a special move, regardless of which of
-- the two records it is. No RNG2 thresholds beyond the already-validated target-scan accept rate.
--
-- NO SAVESTATE EXISTS - not runnable yet. Once you have a savestate positioned in a battle against
-- a Death Machine, fill in SAVESTATE/ENEMY_SLOT/EXPECTED_AI_FUNC below and run via
-- scripts/spawn-headless-emuhawk.sh (EXPECTED_AI_FUNC lets you check whichever of the 2 records
-- you're actually fighting). Checks the live per-instance MonsterRecord this enemy resolves to
-- (pAttackDataTable[bId] chain) against this static finding.
--
-- USAGE (once a savestate exists): edit SAVESTATE, ENEMY_SLOT, EXPECTED_AI_FUNC below, then
--   scripts/spawn-headless-emuhawk.sh scripts/AIStaticChecks/CheckDeathMachineAI.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local Charmap = require "lib.Charmap"

local SAVESTATE = nil -- TODO fill in
local ENEMY_SLOT = nil -- TODO fill in (1-indexed combatant slot)
local EXPECTED_AI_FUNC = 0x80010360 -- TODO: 0x80010360 or 0x80010d0c depending on which record

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckDeathMachineAI.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

if SAVESTATE == nil then
  log("No savestate configured yet - this script only documents the static finding above.")
  log("Static finding: two identical AI functions in vc3.bin (base 0x80010000) at 0x80010360")
  log("and 0x80010d0c, both front-row-only target scan, always plain Attack, no special move.")
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
    log(string.format("Expected aiFunc: 0x%08x - match: %s", EXPECTED_AI_FUNC, tostring(aiFuncAddr == EXPECTED_AI_FUNC)))
  end)
  if not ok then log("ERROR: " .. tostring(err)) end
end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
if SAVESTATE ~= nil then client.exit() end
