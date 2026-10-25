-- STATIC FINDING (Ghidra decompile, ve2.bin @ 0x80015328, base 0x80010000, no live capture yet):
-- banshee_ai_select_target_and_move: standard front-row-only target scan (formationPos<4, alive,
-- not busy; ~49%-per-candidate RNG2 accept, retry next tick with fresh rolls if nobody accepted).
-- UNLIKE most monsters, once a target locks there is NO move-choice roll at all - a 3RD CONFIRMED
-- INSTANCE of this pattern (alongside Slot man and Nightmare): it unconditionally arms
-- LAB_800154a8 as the next micro-state and returns 1 (committed). Banshee ALWAYS uses its special
-- move once it has a target - it never falls back to a plain physical Attack.
--
-- NO SAVESTATE EXISTS - not runnable yet. Once you have a savestate positioned in a battle against
-- a Banshee, fill in SAVESTATE/ENEMY_SLOT below and run via scripts/spawn-headless-emuhawk.sh.
-- Checks the live per-instance MonsterRecord this enemy resolves to (pAttackDataTable[bId] chain)
-- against this static finding.
--
-- USAGE (once a savestate exists): edit SAVESTATE and ENEMY_SLOT below, then
--   scripts/spawn-headless-emuhawk.sh scripts/AIStaticChecks/CheckBansheeAI.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local Charmap = require "lib.Charmap"

local SAVESTATE = nil -- TODO fill in
local ENEMY_SLOT = nil -- TODO fill in (1-indexed combatant slot)

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckBansheeAI.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

if SAVESTATE == nil then
  log("No savestate configured yet - this script only documents the static finding above.")
  log("Static finding: AI @ 0x80015328 in ve2.bin (base 0x80010000), front-row-only target")
  log("scan, then ALWAYS commits to its special move once locked (no plain-Attack fallback).")
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
    log(string.format("Expected aiFunc: 0x80015328 - match: %s", tostring(aiFuncAddr == 0x80015328)))
  end)
  if not ok then log("ERROR: " .. tostring(err)) end
end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
if SAVESTATE ~= nil then client.exit() end
