-- STATIC FINDING (Ghidra decompile, a_data.bin @ 0x80080adc, base 0x80080000, no live capture yet):
-- red_soldier_ant_ai_select_target_and_move: standard front-row-only target scan (formationPos<4,
-- alive, not busy; ~49%-per-candidate RNG2 accept, retry next tick with fresh rolls if nobody
-- accepted). BUT unlike the plain generic template, once a target locks this one does NOT just
-- return -1 unconditionally - it rolls AGAIN and branches on a move-choice threshold:
--   ((roll*100)/0x7fff)%100 < 0x4d (77)  -> return -1 (decline -> falls back to plain Attack)
--   otherwise (~23%)                     -> commit to DoubleStrike (script 0x800a5460, arms
--                                           LAB_80080950 as next micro-state, returns 1)
-- This is the EXACT SAME formula and threshold as the regular Soldier Ant's already-confirmed-live
-- DoubleStrike branch (~77.002% Attack / ~22.998% DoubleStrike) - see the Soldier Ant section of
-- docs/game_mechanics/Battle_Damage_Formula.md. Red Solider Ant [sic - preserving the ROM's own
-- transposed-letter typo in the name field, same convention as outputs/Bestiary.json] shares its
-- bigger cousin's exact move logic, just with different base stats.
--
-- NO SAVESTATE EXISTS (Red Solider Ant is a regular random encounter, no boss/scripted fight) -
-- not runnable yet. Once you have a savestate positioned in a battle against a Red Solider Ant,
-- fill in SAVESTATE/ENEMY_SLOT below and run via scripts/spawn-headless-emuhawk.sh. Checks the live
-- per-instance MonsterRecord this enemy resolves to (pAttackDataTable[bId] chain) against this
-- static finding.
--
-- USAGE (once a savestate exists): edit SAVESTATE and ENEMY_SLOT below, then
--   scripts/spawn-headless-emuhawk.sh scripts/AIStaticChecks/CheckRedSoliderAntAI.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local Charmap = require "lib.Charmap"

local SAVESTATE = nil -- TODO fill in
local ENEMY_SLOT = nil -- TODO fill in (1-indexed combatant slot)

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckRedSoliderAntAI.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

if SAVESTATE == nil then
  log("No savestate configured yet - this script only documents the static finding above.")
  log("Static finding: AI @ 0x80080adc in a_data.bin (base 0x80080000), front-row-only target")
  log("scan, then ~77% Attack / ~23% DoubleStrike (same formula/threshold as regular Soldier Ant).")
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
    log(string.format("Expected aiFunc: 0x80080adc - match: %s", tostring(aiFuncAddr == 0x80080adc)))
  end)
  if not ok then log("ERROR: " .. tostring(err)) end
end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
if SAVESTATE ~= nil then client.exit() end
