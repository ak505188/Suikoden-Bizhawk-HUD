-- STATIC FINDING (Ghidra decompile, vb6.bin @ 0x80010330, base 0x80010000, no live capture yet):
-- holly_spirit_ai_select_target_and_move is a STRUCTURAL EXCEPTION: it checks its OWN formation
-- row FIRST, before doing anything else - unlike Sydonia (who checks the TARGET's row, only after
-- locking one) or Beast Commander/Ghost Armor (who scan allies/party first).
--   if selfFormationPos < 4 (FRONT row): runs the ordinary front-row-only scan-and-lock template
--     (formationPos<4, alive, not busy, ~49%-per-candidate RNG2 accept, retry if nobody accepted)
--     and always ends in a plain Attack once a target locks (no special-move roll at all here).
--   if selfFormationPos >= 4 (BACK row): skips targeting ENTIRELY and unconditionally plays a
--     self-targeted special move (script 0x8006f554, next micro-state LAB_800104dc), returns 1.
-- This makes Holly Spirit a 5th confirmed back-row-reaching exception (alongside Killer Rabbit,
-- Slasher Rabbit, Sydonia, Ghost Armor) - and the first one where the monster's OWN formation
-- position (not the target's, not an ally's) is what decides everything.
--
-- NO SAVESTATE EXISTS - not runnable yet. Once you have a savestate positioned in a battle against
-- a Holly Spirit (ideally testing BOTH front-row and back-row placement, since behavior is
-- entirely different), fill in SAVESTATE/ENEMY_SLOT below and run via
-- scripts/spawn-headless-emuhawk.sh. Checks the live per-instance MonsterRecord this enemy
-- resolves to (pAttackDataTable[bId] chain) against this static finding.
--
-- USAGE (once a savestate exists): edit SAVESTATE and ENEMY_SLOT below, then
--   scripts/spawn-headless-emuhawk.sh scripts/AIStaticChecks/CheckHollySpiritAI.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local Charmap = require "lib.Charmap"

local SAVESTATE = nil -- TODO fill in
local ENEMY_SLOT = nil -- TODO fill in (1-indexed combatant slot)

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckHollySpiritAI.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

if SAVESTATE == nil then
  log("No savestate configured yet - this script only documents the static finding above.")
  log("Static finding: AI @ 0x80010330 in vb6.bin (base 0x80010000). Own row decides everything:")
  log("front row -> scan+plain Attack; back row -> always self-targeted special move (0x8006f554).")
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
    log(string.format("Expected aiFunc: 0x80010330 - match: %s", tostring(aiFuncAddr == 0x80010330)))
  end)
  if not ok then log("ERROR: " .. tostring(err)) end
end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
if SAVESTATE ~= nil then client.exit() end
