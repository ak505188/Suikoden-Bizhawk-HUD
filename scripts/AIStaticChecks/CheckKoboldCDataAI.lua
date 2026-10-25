-- STATIC FINDING (Ghidra decompile, c_data.bin @ 0x80080490, base 0x80080000, no live capture yet):
-- This Kobold record (level 20, HP 50/PWR 100/SKL 70/DEF 40/SPD 60/MGC 130/LUK 37 - an "elite"
-- story/mini-boss stat block, not the regular random-encounter Kobold from vb6.bin) uses
-- dragon_move_confirm_or_override_to_fire_breath - the EXACT SAME function already documented in
-- docs/game_mechanics/Battle_Damage_Formula.md's Dragon section, where it was proven to be DEAD
-- CODE for Dragon (Dragon's real move-confirm happens in dragon_special_move_real_frame_callback,
-- dragon_overlay.bin @ 0x800123b8). That section's own plate comment speculated this code was
-- "possibly for a different monster sharing this same c_data.bin" - THIS Kobold record confirms
-- that speculation: the function is genuinely live, active AI here, just dead for Dragon
-- specifically (both monsters' data live in the same 06_area.c/c_data.bin file).
--
-- Behavior (standard front-row-only target scan, then a move-choice roll):
--   front-row-only scan (formationPos<4, alive, not busy; ~49%-per-candidate RNG2 accept, retry
--   if nobody accepted), then once locked: (roll*100)/0x7fff < 0x33(51) -> decline (~51% Attack),
--   otherwise (~49%) -> commit to a special move (continuation currently named
--   dragon_fire_breath_windup, a leftover name from the original Dragon context - NOT a claim that
--   this Kobold's special move literally animates as fire breath; what it actually does for THIS
--   monster hasn't been traced).
--
-- NO SAVESTATE EXISTS - not runnable yet. Once you have a savestate positioned in a battle against
-- this specific (elite/story) Kobold, fill in SAVESTATE/ENEMY_SLOT below and run via
-- scripts/spawn-headless-emuhawk.sh. Checks the live per-instance MonsterRecord this enemy
-- resolves to (pAttackDataTable[bId] chain) against this static finding.
--
-- USAGE (once a savestate exists): edit SAVESTATE and ENEMY_SLOT below, then
--   scripts/spawn-headless-emuhawk.sh scripts/AIStaticChecks/CheckKoboldCDataAI.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local Charmap = require "lib.Charmap"

local SAVESTATE = nil -- TODO fill in
local ENEMY_SLOT = nil -- TODO fill in (1-indexed combatant slot)

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckKoboldCDataAI.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

if SAVESTATE == nil then
  log("No savestate configured yet - this script only documents the static finding above.")
  log("Static finding: AI @ 0x80080490 in c_data.bin (base 0x80080000) - shared with Dragon's")
  log("dead-code dragon_move_confirm_or_override_to_fire_breath, but LIVE for this Kobold.")
  log("front-row-only scan, then ~51% Attack / ~49% special move.")
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
    log(string.format("Expected aiFunc: 0x80080490 - match: %s", tostring(aiFuncAddr == 0x80080490)))
  end)
  if not ok then log("ERROR: " .. tostring(err)) end
end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
if SAVESTATE ~= nil then client.exit() end
