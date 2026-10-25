-- STATIC FINDING (Ghidra decompile, f_data.bin @ 0x800823d8, base 0x80080000, no live capture yet):
-- shadow_man_ai_select_target_and_move: standard front-row-only target scan (formationPos<4,
-- alive, not busy; ~49%-per-candidate RNG2 accept, retry next tick with fresh rolls if nobody
-- accepted). UNLIKE most monsters, once a target locks there is NO move-choice roll at all - a 4TH
-- CONFIRMED INSTANCE of this pattern (alongside Slot man, Nightmare, Banshee): it unconditionally
-- commits to its special move (script 0x800a2b40, next micro-state LAB_80082280, returns 1). It
-- ALSO does extra bookkeeping the other 3 don't: clears a 2-byte field on itself
-- (selfIdx*0x8c+0x90) and sets a flag on the shared AI struct itself (param_1+0x44=1, NOT a
-- per-actor field like the others - this is on the struct base, meaning it could affect every
-- actor's next decision, not just Shadow Man's own) - meaning not yet identified, worth
-- investigating if a live capture becomes available.
--
-- NO SAVESTATE EXISTS - not runnable yet. Once you have a savestate positioned in a battle against
-- a Shadow Man, fill in SAVESTATE/ENEMY_SLOT below and run via scripts/spawn-headless-emuhawk.sh.
-- Checks the live per-instance MonsterRecord this enemy resolves to (pAttackDataTable[bId] chain)
-- against this static finding.
--
-- USAGE (once a savestate exists): edit SAVESTATE and ENEMY_SLOT below, then
--   scripts/spawn-headless-emuhawk.sh scripts/AIStaticChecks/CheckShadowManAI.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local Charmap = require "lib.Charmap"

local SAVESTATE = nil -- TODO fill in
local ENEMY_SLOT = nil -- TODO fill in (1-indexed combatant slot)

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckShadowManAI.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

if SAVESTATE == nil then
  log("No savestate configured yet - this script only documents the static finding above.")
  log("Static finding: AI @ 0x800823d8 in f_data.bin (base 0x80080000), front-row-only target")
  log("scan, then ALWAYS commits to its special move once locked, plus extra bookkeeping")
  log("(clears a self field, sets a flag on the shared AI struct itself).")
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
    log(string.format("Expected aiFunc: 0x800823d8 - match: %s", tostring(aiFuncAddr == 0x800823d8)))
  end)
  if not ok then log("ERROR: " .. tostring(err)) end
end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
if SAVESTATE ~= nil then client.exit() end
