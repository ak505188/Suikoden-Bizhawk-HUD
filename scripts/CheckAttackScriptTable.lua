-- User: "what's the attack script table? at 0x28" - MonsterRecord's p1 field (+0x28) was only
-- ever labeled "attack script table pointer" as a GUESS in scripts/ScanMonsterRecords.py's own
-- comment, never verified. Hypothesis: this static value gets copied into the LIVE per-instance
-- EnemyData+8 field at battle setup - the SAME pointer queen_ant_command_all_ants_attack and
-- soldier_ant_ai_select_target_and_move already read as `*(int*)(enemy_data[x]+8)+4/+8/+0x10` for
-- windup/hit/idle scripts (see Battle_Damage_Formula.md's "Queen Ant's full moveset" section).
--
-- Checks: (1) does static MonsterRecord+0x28 match the live EnemyData+8 pointer for the same
-- monster instance? (2) what's actually at that pointer - do the +4/+8/+0x10 slots hold known
-- script addresses (Queen Ant's own 0x8006c108/0x8006c1a0, Soldier Ant's 0x80065124/0x80065214)?
--
-- USAGE: scripts/spawn-headless-emuhawk.sh scripts/CheckAttackScriptTable.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path

local Address = require "lib.Address"

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckAttackScriptTable.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

local ok, err = pcall(function()
  savestate.load("/home/alex/Projects/Suikoden-Bizhawk-HUD/QueenAnt.State")
  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))
  local rowArray = Address.sanitize(mainmemory.read_u32_le(base + 0x1344))

  for _, slot in ipairs({ 6, 9 }) do
    local enemyDataAddr = base + 0x50 + slot * 0x8c
    local bId = mainmemory.read_u8(enemyDataAddr)
    local speciesRow = Address.sanitize(mainmemory.read_u32_le(rowArray + bId * 4))

    local staticP1 = mainmemory.read_u32_le(speciesRow + 0x28)
    local staticP2 = mainmemory.read_u32_le(speciesRow + 0x2c)
    local liveResourcePtr = mainmemory.read_u32_le(enemyDataAddr + 8)

    log(string.format("--- slot %d (bId=%d, MonsterRecord @ 0x%08x) ---", slot, bId, speciesRow))
    log(string.format("  static p1 (record+0x28)        = 0x%08x", staticP1))
    log(string.format("  static p2 (record+0x2c)        = 0x%08x", staticP2))
    log(string.format("  live EnemyData+8 resource ptr  = 0x%08x", liveResourcePtr))
    log(string.format("  p1 == live resource ptr?  %s", staticP1 == liveResourcePtr and "YES" or "no"))
    log(string.format("  p2 == live resource ptr?  %s", staticP2 == liveResourcePtr and "YES" or "no"))

    if Address.isValidPointer(liveResourcePtr) then
      local resTable = Address.sanitize(liveResourcePtr)
      log("  dump of live resource table (+0x00 .. +0x18):")
      for off = 0, 0x18, 4 do
        local val = mainmemory.read_u32_le(resTable + off)
        log(string.format("    +0x%02x = 0x%08x", off, val))
      end
    end
  end
end)

if not ok then log("ERROR: " .. tostring(err)) end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
client.exit()
