-- STATIC FINDING (Ghidra decompile, a_data.bin @ 0x80080004, base 0x80080000, no live capture yet):
-- FurFur, BonBon, and Mosquito share ONE identical AI function. It's the standard generic
-- template already confirmed live for several other monsters (CrimsonDwarf/Colossus/GiantSnail/
-- Zombie Dragon/etc.): scan party members in formation order, skip anyone not in the front row
-- (formationPos>=4), dead, or busy; roll RNG2 per eligible candidate, accept if roll%100>50; retry
-- next tick (fresh rolls) if no candidate accepted. Once a target locks, the function returns -1
-- unconditionally (AI declines to act specially) - per battle_dispatch_current_actor_action's
-- convention this falls back to battle_execute_player_attack, i.e. these 3 monsters ALWAYS use a
-- plain physical Attack, never a special move. No RNG2 thresholds to characterize beyond the
-- target-scan's own ~49%-per-candidate accept rate (already validated live for other monsters
-- using this exact template).
--
-- NO SAVESTATE EXISTS for any of these 3 (all regular Gregminster Area 1 random encounters, no
-- boss/scripted fight) - this script is not runnable yet. Once you have a savestate positioned in
-- a battle against FurFur, BonBon, or Mosquito, fill in SAVESTATE below and run via
-- scripts/spawn-headless-emuhawk.sh. What it checks: (1) the live per-instance MonsterRecord this
-- enemy resolves to (via the pAttackDataTable[bId] pointer chain - see CheckMonsterRecordAddresses.lua
-- for the original version of this pattern) matches this static finding's address/stats, and
-- (2) the AI function address read live matches 0x80080004 exactly (confirming the file really
-- loads at runtime base 0x80080000 as assumed).
--
-- USAGE (once a savestate exists): edit SAVESTATE and ENEMY_SLOT below, then
--   scripts/spawn-headless-emuhawk.sh scripts/AIStaticChecks/CheckFurFurBonBonMosquitoAI.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local Charmap = require "lib.Charmap"

local SAVESTATE = nil -- e.g. "/home/alex/Projects/Suikoden-Bizhawk-HUD/FurFur.State" - TODO fill in
local ENEMY_SLOT = nil -- 1-indexed combatant slot this enemy occupies in that savestate - TODO fill in

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckFurFurBonBonMosquitoAI.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

if SAVESTATE == nil then
  log("No savestate configured yet - this script only documents the static finding above.")
  log("Static finding: shared AI @ 0x80080004 in a_data.bin (base 0x80080000), front-row-only")
  log("target scan, always plain Attack, no special move, for FurFur/BonBon/Mosquito.")
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
    log(string.format("Expected aiFunc: 0x80080004 - match: %s", tostring(aiFuncAddr == 0x80080004)))
  end)
  if not ok then log("ERROR: " .. tostring(err)) end
end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
if SAVESTATE ~= nil then client.exit() end
