-- STATIC FINDING (Ghidra decompile, vh1.bin @ 0x80010020, base 0x80010000, no live capture yet):
-- Hell Hound (this record) and Elite Soldier share ONE identical AI function. It's the standard
-- generic template already confirmed live for several other monsters: front-row-only target scan
-- (formationPos<4, alive, not busy; ~49%-per-candidate RNG2 accept, retry next tick with fresh
-- rolls if nobody accepted), then returns -1 unconditionally once a target locks (AI declines to
-- act specially) - falls back to battle_execute_player_attack, i.e. both monsters ALWAYS use a
-- plain physical Attack, never a special move. No RNG2 thresholds beyond the already-validated
-- target-scan accept rate. (NOTE: a SEPARATE Hell Hound record exists in e_data.bin, sharing a
-- function with Grave Master there - see CheckHellHoundGraveMasterAI.lua.)
--
-- NO SAVESTATE EXISTS for either - not runnable yet. Once you have a savestate positioned in a
-- battle against a Hell Hound or Elite Soldier in this area, fill in SAVESTATE/ENEMY_SLOT below
-- and run via scripts/spawn-headless-emuhawk.sh. Checks the live per-instance MonsterRecord this
-- enemy resolves to (pAttackDataTable[bId] chain) against this static finding.
--
-- USAGE (once a savestate exists): edit SAVESTATE and ENEMY_SLOT below, then
--   scripts/spawn-headless-emuhawk.sh scripts/AIStaticChecks/CheckHellHoundEliteSoldierAI.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local Charmap = require "lib.Charmap"

local SAVESTATE = nil -- TODO fill in
local ENEMY_SLOT = nil -- TODO fill in (1-indexed combatant slot)

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckHellHoundEliteSoldierAI.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

if SAVESTATE == nil then
  log("No savestate configured yet - this script only documents the static finding above.")
  log("Static finding: shared AI @ 0x80010020 in vh1.bin (base 0x80010000), front-row-only")
  log("target scan, always plain Attack, no special move, for Hell Hound/Elite Soldier.")
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
    log(string.format("Expected aiFunc: 0x80010020 - match: %s", tostring(aiFuncAddr == 0x80010020)))
  end)
  if not ok then log("ERROR: " .. tostring(err)) end
end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
if SAVESTATE ~= nil then client.exit() end
