-- Extends the opcode-26 (anim_op_set_effect_flags) counter-arming investigation past n=1
-- (Cleo). User-provided savestate CounterRangeTest.State: McDohl + 5 long-range characters.
-- "If there is a different property, you should find it here" - so this doesn't assume the
-- reach-category-2 hypothesis, it checks each character's own weapon reach category AND own
-- opcode-26 target argument independently and reports both.
--
-- CORRECTED APPROACH (first attempt used pAttackDataTable[bId], the same lookup enemies use
-- for elemental compatibility - WRONG for this purpose: Cleo's roster Id (1) and Kirkis's (4)
-- collide with real monster species Ids (Killer Rabbit=1, Roc=4) in that SHARED numeric space
-- - lib/BattleSnapshot.lua's own header comment already warns about this exact collision risk.
-- Querying pAttackDataTable[1] at read-time returns whichever row owns Id 1 (the monster, if
-- one does) - it can't disambiguate "this Id belongs to a monster" from "this Id belongs to a
-- party member" after the fact. The FIX, confirmed by decompiling battle_execute_enemy_attack
-- (0x800f491c): it reads the ATTACKER's own script via `EnemyDataArray[attacker].
-- pActionScriptTable` directly - a PER-COMBATANT-INSTANCE pointer cached on EnemyData itself
-- (offset +0x08, confirmed via get_struct_layout) at battle load time, not re-derived from a
-- shared species-indexed table on every read. This is collision-proof and is what this script
-- now uses.
--
-- anim_op_set_effect_flags (0x800e4fd8, opcode 26 in the 45-entry PTR_LAB_8016babc table)
-- encoding, 6 bytes: [opcode:u16=26(0x1A)] [target:u16] [mask:u16]
-- target==1 -> OR'd into the TARGET's (bAnimTargetIdx) enemy_data+0x40 wEffectFlags.
-- target!=1 (0 in every sample so far) -> OR'd into the CASTER'S OWN enemy_data+0x40.
-- The counter-arm bit is mask bit 0x0001 (enemy_data+0x40 bit 0). A script can call opcode 26
-- more than once for unrelated effect flags, so this scans for ALL calls and flags which (if
-- any) touch bit 0x0001.
--
-- Weapon reach category: DAT_80165890[weaponType]+0x56 (confirmed this session):
--   2 = long-range (any row targetable), 1 = short/restricted, other = default front-row-only.
-- weaponType is read from the character's own PersistentStats+0x44 (bWeaponReachIndex).
--
-- USAGE: scripts/spawn-headless-emuhawk.sh scripts/CheckCounterRangeTest.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local CharAddresses = require "lib.Characters.Addresses"
local Names = require "lib.Characters.NamesList"

local SAVESTATE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/CounterRangeTest.State"
local WEAPON_CLASS_TABLE = 0x165890 -- DAT_80165890, pointer table indexed by weaponType*4

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckCounterRangeTest.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

-- Ally roster Id -> character name (same construction as lib/BattleSnapshot.lua's idToName).
local idToName = {}
for _, name in ipairs(Names) do
  local rec = CharAddresses[name]
  if rec and rec.Id then idToName[rec.Id] = name end
end

-- Charmap: 0x10=space, 0x11-0x2a=lowercase a-z, 0x2b+=uppercase A-Z, 0x45+=digits 0-9
local function decodeName(addr, maxLen)
  local out = {}
  for i = 0, (maxLen or 15) do
    local b = mainmemory.read_u8(Address.sanitize(addr + i))
    if b == 0 then break end
    local c
    if b == 0x10 then c = ' '
    elseif b >= 0x11 and b <= 0x2a then c = string.char(string.byte('a') + (b - 0x11))
    elseif b >= 0x2b and b <= 0x44 then c = string.char(string.byte('A') + (b - 0x2b))
    elseif b >= 0x45 and b <= 0x4e then c = string.char(string.byte('0') + (b - 0x45))
    else c = '?' end
    table.insert(out, c)
  end
  return table.concat(out)
end

local function findOpcode26Calls(scriptAddr, maxBytes)
  local hits = {}
  local addr = Address.sanitize(scriptAddr)
  for off = 0, maxBytes - 6 do
    local b0 = mainmemory.read_u8(addr + off)
    local b1 = mainmemory.read_u8(addr + off + 1)
    if b0 == 0x1A and b1 == 0x00 then
      local target = mainmemory.read_u16_le(addr + off + 2)
      local mask = mainmemory.read_u16_le(addr + off + 4)
      table.insert(hits, { offset = off, target = target, mask = mask })
    end
  end
  return hits
end

local function getStatsAddr(base, actorIdx)
  local classPtrsSlot = base + 0xf84 + actorIdx * 0xc
  local classPtr0raw = mainmemory.read_u32_le(classPtrsSlot + 0)
  if not Address.isValidPointer(classPtr0raw) then return nil end
  local classPtr0 = Address.sanitize(classPtr0raw)
  local statsRaw = mainmemory.read_u32_le(classPtr0 + 0x1c)
  if not Address.isValidPointer(statsRaw) then return nil end
  return Address.sanitize(statsRaw)
end

local ok, err = pcall(function()
  savestate.load(SAVESTATE)
  for i = 1, 100 do emu.frameadvance() end -- settle, per project convention

  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))
  local partyCount = mainmemory.read_u32_le(base + 0x1c)
  local totalCombatants = mainmemory.read_u32_le(base + 0x24)
  log(string.format("BattleState base=0x%06x partyCount=%d total=%d",
    base, partyCount, totalCombatants))

  for idx = 1, partyCount do
    local enemyDataAddr = base + 0x50 + idx * 0x8c
    local bId = mainmemory.read_u8(enemyDataAddr)
    local charName = idToName[bId] or "UNKNOWN"

    local statsAddr = getStatsAddr(base, idx)
    local weaponType, reachCategory, weaponName = nil, nil, "?"
    if statsAddr then
      weaponType = mainmemory.read_u8(statsAddr + 0x44)
      local weaponEntryRaw = mainmemory.read_u32_le(WEAPON_CLASS_TABLE + weaponType * 4)
      if Address.isValidPointer(weaponEntryRaw) then
        local weaponEntry = Address.sanitize(weaponEntryRaw)
        reachCategory = mainmemory.read_u8(weaponEntry + 0x56)
        weaponName = decodeName(weaponEntryRaw)
      end
    end

    -- Per-instance cached script table pointer (EnemyData+0x08), NOT pAttackDataTable[bId] -
    -- collision-proof, see header comment.
    local pAttackScriptTable = Address.sanitize(mainmemory.read_u32_le(enemyDataAddr + 0x08))
    local primaryScript = mainmemory.read_u32_le(pAttackScriptTable + 0x04)
    local hitScript = mainmemory.read_u32_le(pAttackScriptTable + 0x08)

    log(string.format(
      "idx=%d bId=%d name=%s weaponType=%s reach=%s weapon=%q statsAddr=0x%06x pAttackScriptTable=0x%08x",
      idx, bId, charName, tostring(weaponType), tostring(reachCategory), weaponName,
      statsAddr or 0, pAttackScriptTable))
    log(string.format("  primaryScript=0x%08x hitScript=0x%08x", primaryScript, hitScript))

    for _, label in ipairs({ { "primary", primaryScript }, { "hit", hitScript } }) do
      local name, addr = label[1], label[2]
      if Address.isValidPointer(addr) then
        local hits = findOpcode26Calls(addr, 200)
        if #hits == 0 then
          log(string.format("  %s script: no opcode-26 calls found in first 200 bytes", name))
        end
        for _, h in ipairs(hits) do
          local counterArm = (h.mask & 0x0001) ~= 0
          log(string.format(
            "  %s script +0x%02x: opcode26 target=%d mask=0x%04x%s",
            name, h.offset, h.target, h.mask,
            counterArm and " <-- COUNTER-ARM BIT (0x0001)" or ""))
        end
      else
        log(string.format("  %s script: invalid pointer 0x%08x, skipped", name, addr))
      end
    end
  end
end)
if not ok then log("ERROR: " .. tostring(err)) end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
client.exit()
