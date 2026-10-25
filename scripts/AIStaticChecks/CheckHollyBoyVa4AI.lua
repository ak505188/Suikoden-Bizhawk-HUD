-- STATIC FINDING (Ghidra decompile, va4.bin @ 0x80010a7c, base 0x80010000, no live capture yet):
-- holly_boy_va4_ai_select_target_and_move: standard front-row-only target scan (formationPos<4,
-- alive, not busy; ~49%-per-candidate RNG2 accept, retry next tick with fresh rolls if nobody
-- accepted). UNLIKE the plain generic template, once a target locks this checks a byte on the
-- LOCKED TARGET's own PersistentStats struct at offset +0xd (classData+0x1c+0xd - see the
-- PersistentStats field list in docs/game_mechanics/Battle_Damage_Formula.md; +0xd is NOT one of
-- the already-catalogued offsets there, so its meaning is still unidentified):
--   if targetPersistentStats[0xd] < 4  -> return -1 (decline -> falls back to plain Attack)
--   else roll again: ((roll)%100) > 0x19(25) (~74%) -> commit to special move (script 0x800766e8,
--                                                       30-tick counter, returns 1)
--                    otherwise (~26%)                -> return -1 (decline -> plain Attack)
-- This is the first monster found in this sweep whose move CHOICE depends on a property of the
-- TARGET (not just a self roll) - worth live-validating +0xd's meaning if a savestate ever exists.
--
-- NO SAVESTATE EXISTS (regular random encounter) - not runnable yet. Once you have a savestate
-- positioned in a battle against a Holly Boy in this area, fill in SAVESTATE/ENEMY_SLOT below and
-- run via scripts/spawn-headless-emuhawk.sh. Checks the live per-instance MonsterRecord this enemy
-- resolves to (pAttackDataTable[bId] chain) against this static finding, AND (if you extend it)
-- could read the locked target's PersistentStats+0xd to help identify that field.
--
-- USAGE (once a savestate exists): edit SAVESTATE and ENEMY_SLOT below, then
--   scripts/spawn-headless-emuhawk.sh scripts/AIStaticChecks/CheckHollyBoyVa4AI.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local Charmap = require "lib.Charmap"

local SAVESTATE = nil -- TODO fill in
local ENEMY_SLOT = nil -- TODO fill in (1-indexed combatant slot)

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckHollyBoyVa4AI.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

if SAVESTATE == nil then
  log("No savestate configured yet - this script only documents the static finding above.")
  log("Static finding: AI @ 0x80010a7c in va4.bin (base 0x80010000), front-row-only target scan,")
  log("then a target-property check (target's PersistentStats+0xd < 4) gates a ~74%-chance")
  log("special move (script 0x800766e8) vs plain Attack.")
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
    log(string.format("Expected aiFunc: 0x80010a7c - match: %s", tostring(aiFuncAddr == 0x80010a7c)))
  end)
  if not ok then log("ERROR: " .. tostring(err)) end
end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
if SAVESTATE ~= nil then client.exit() end
