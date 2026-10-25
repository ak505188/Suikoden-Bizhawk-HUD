-- STATIC FINDING (Ghidra decompile, vf1.bin @ 0x800149d8, base 0x80010000, no live capture yet):
-- black_elemental_ai_select_target_and_move is a 3RD CONFIRMED "elemental family" instance of the
-- unrestricted-scan exception (alongside Red Elemental - see CheckRedElementalAI.lua): its
-- target-scan loop has NO formationPos<4 front-row gate at all - only alive/not-busy plus the
-- ~49%-per-candidate RNG2 accept, over ALL party slots regardless of row. Once a target locks, it
-- returns -1 unconditionally (AI declines to act specially) - always a plain physical Attack. This
-- makes Black Elemental an 8th confirmed back-row-reaching exception overall.
--
-- NO SAVESTATE EXISTS - not runnable yet. Once you have a savestate positioned in a battle against
-- a Black Elemental (ideally with the party's back row occupied, to test whether it can actually
-- target back-row members), fill in SAVESTATE/ENEMY_SLOT below and run via
-- scripts/spawn-headless-emuhawk.sh. Checks the live per-instance MonsterRecord this enemy
-- resolves to (pAttackDataTable[bId] chain) against this static finding.
--
-- USAGE (once a savestate exists): edit SAVESTATE and ENEMY_SLOT below, then
--   scripts/spawn-headless-emuhawk.sh scripts/AIStaticChecks/CheckBlackElementalAI.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local Charmap = require "lib.Charmap"

local SAVESTATE = nil -- TODO fill in
local ENEMY_SLOT = nil -- TODO fill in (1-indexed combatant slot)

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckBlackElementalAI.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

if SAVESTATE == nil then
  log("No savestate configured yet - this script only documents the static finding above.")
  log("Static finding: AI @ 0x800149d8 in vf1.bin (base 0x80010000). No front-row gate at all -")
  log("unrestricted target scan (any row), always plain Attack once locked.")
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
    log(string.format("Expected aiFunc: 0x800149d8 - match: %s", tostring(aiFuncAddr == 0x800149d8)))
  end)
  if not ok then log("ERROR: " .. tostring(err)) end
end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
if SAVESTATE ~= nil then client.exit() end
