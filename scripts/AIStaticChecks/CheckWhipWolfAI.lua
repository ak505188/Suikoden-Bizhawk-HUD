-- STATIC FINDING (Ghidra decompile, e_data.bin @ 0x80080194, base 0x80080000, no live capture yet):
-- whip_wolf_ai_select_target_and_move is a 3RD CONFIRMED INSTANCE of the "own row decides
-- everything" pattern (Holly Spirit, Holly Fairy - see CheckHollySpiritAI.lua): checks its OWN
-- formation row FIRST, before anything else:
--   if selfFormationPos < 4 (FRONT row): runs the ordinary front-row-only scan-and-lock template
--     (formationPos<4, alive, not busy - using a slightly different RNG-scaling variant of the
--     same ~49-50% accept check, (roll*100)/0x7fff > 50 instead of roll%100 > 50) and always ends
--     in a plain Attack once a target locks.
--   if selfFormationPos >= 4 (BACK row): skips targeting ENTIRELY and unconditionally plays a
--     self-targeted special move (script 0x8009ed74, next micro-state LAB_80080338), returns 1.
--
-- NO SAVESTATE EXISTS - not runnable yet. Once you have a savestate positioned in a battle against
-- a Whip Wolf (ideally testing BOTH front-row and back-row placement, since behavior is entirely
-- different), fill in SAVESTATE/ENEMY_SLOT below and run via scripts/spawn-headless-emuhawk.sh.
-- Checks the live per-instance MonsterRecord this enemy resolves to (pAttackDataTable[bId] chain)
-- against this static finding.
--
-- USAGE (once a savestate exists): edit SAVESTATE and ENEMY_SLOT below, then
--   scripts/spawn-headless-emuhawk.sh scripts/AIStaticChecks/CheckWhipWolfAI.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local Charmap = require "lib.Charmap"

local SAVESTATE = nil -- TODO fill in
local ENEMY_SLOT = nil -- TODO fill in (1-indexed combatant slot)

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckWhipWolfAI.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

if SAVESTATE == nil then
  log("No savestate configured yet - this script only documents the static finding above.")
  log("Static finding: AI @ 0x80080194 in e_data.bin (base 0x80080000). Own row decides")
  log("everything: front row -> scan+plain Attack; back row -> always self-targeted special")
  log("move (0x8009ed74). Same pattern as Holly Spirit/Holly Fairy.")
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
    log(string.format("Expected aiFunc: 0x80080194 - match: %s", tostring(aiFuncAddr == 0x80080194)))
  end)
  if not ok then log("ERROR: " .. tostring(err)) end
end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
if SAVESTATE ~= nil then client.exit() end
