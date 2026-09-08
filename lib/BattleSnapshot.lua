-- Extracts a complete, engine-agnostic snapshot of the live in-battle state: everything a
-- pure-code battle simulator needs to reproduce a round without touching the emulator, plus
-- everything an emulator-side harness needs to confirm it started from the exact same state.
-- This is the shared "InitialState" contract between the two - see
-- docs/game_mechanics/Scripted_Battle_Actions.md's brute-force interface design section.
--
-- WHEN TO CAPTURE: only valid once the battle struct is stably populated (confirmed live 2026-09
-- to settle by frame ~50 after savestate.load() and stay unchanged for 3000+ frames - no
-- initialization race), and, for the snapshot to be a genuine "turn start" reference point,
-- BEFORE the round-start Fight/Run/Bribe/Free Will menu's confirm is ever tapped - no RNG should
-- have been consumed for the round yet. ZombieDragonStart.State satisfies both.
--
-- Field sourcing (every offset here is traced to a specific decompiled function, not guessed -
-- see docs/game_mechanics/Battle_Damage_Formula.md and Turn_Order.md for the full derivations):
--   - RNGSeed: Address.RNG (0x9010) - the live 32-bit LCG state. Fully determines every future
--     roll, so this single value is what lets a simulator run reproduce an emulator run bit-for-
--     bit, and what lets a chained multi-turn TurnResult hand off to the next turn's snapshot.
--   - RoundNumber: battle_base+0x4, a genuine round counter (0-indexed) - see its own inline
--     comment below for how this was confirmed. Lets a caller chaining multiple turns label
--     each snapshot with which round it actually is, without tracking it separately.
--   - Per-combatant SKL/SPD/MGC/LUK: read directly from the live per-battle combatant array
--     (base+0xb40, stride 0x54) at +0x26/+0x2a/+0x2c/+0x2e - confirmed live 2026-09 to already be
--     correct and stable at this pre-confirm snapshot point (cross-checked exactly against each
--     character's persistent Stats bytes at +0x11/+0x13/+0x14/+0x15 for all 6 party members).
--   - Per-combatant ATK/DEF: **NOT read from the live combatant array** - confirmed live 2026-09
--     that combatant_rec+0x30/+0x32 (where calc_damage itself reads them from) hold stale/garbage
--     values for EVERY party member until the round actually starts (all 6 changed value on the
--     very first tick after the round-start confirm, in the same tick the turn-order RNG roll
--     already fired - there is no observable window where they're both valid and RNG-untouched).
--     Traced the actual populate code (FUN_800f6ea0, calling FUN_800d4ec0 once per party member)
--     and replicated its formula exactly instead: base PWR/SKL/DEF/SPD/MGC/LUK from the
--     persistent Stats struct (+0x10..+0x15), a Gale Rune (id 0x13) SPD-double, an equipped
--     stat-boosting accessory's flat bonuses (item def +0x1c bit 0x80, applied only if the
--     item's own Equipped byte is set), plus a weapon-type/weapon-level power-table lookup
--     (DAT_80165890 -> +0x54 class byte, then PTR_DAT_801659cc[level*2 + class*0x20 + 2]).
--     Verified to match the real post-confirm ATK/DEF EXACTLY for all 6 party members in
--     ZombieDragonStart.State. For enemies, by contrast, combatant_rec+0x14/+0x18 (not +0x30/
--     +0x32) already hold the correct final value pre-confirm (monsters have no equipment
--     system, so their stats are set up once at battle/monster load, not recomputed at round
--     start) - used directly for enemies instead of replicating any formula.
--   - Id/Busy: enemy_data[] (base+0x50, stride 0x8c). Id indexes attack_data_table for elemental
--     compatibility and, for party members, matches lib/Characters/Addresses.lua's roster Id
--     exactly.
--   - Ally-only RuneId/MP/Items/Weapon bytes: read from each character's own persistent Stats
--     struct (resolved via the classPtrs table at base+0xf84, exactly as
--     lib/ActionEnumerator.lua's getStatsAddr does) - these don't exist for enemies at all.
--
-- NOT included here (deliberately out of scope for a per-battle snapshot): static, unchanging
-- game-data tables that are identical across every battle/savestate - the Rune ability-set table
-- (DAT_8016a0e0), spell definitions (DAT_8016d33c), the Unite table (DAT_8016d18c), item
-- definitions (LAB_80167658), and attack_data_table's elemental compatibility rows. A simulator
-- needs these too, but they should be extracted ONCE as a separate static reference dump, not
-- re-captured in every snapshot.

local Address = require "lib.Address"
local CharAddresses = require "lib.Characters.Addresses"
local Names = require "lib.Characters.NamesList"

local BattleSnapshot = {}

local ITEM_DEFINITION_TABLE = 0x167658 -- LAB_80167658, same table lib/ActionEnumerator.lua uses
local WEAPON_CLASS_TABLE = 0x165890    -- DAT_80165890, pointer table indexed by WeaponType*4
local WEAPON_POWER_TABLE = 0x1659cc    -- PTR_DAT_801659cc, used as a raw i16 table base directly
                                       -- (not dereferenced) - see FUN_800d4ec0's own decompile.

local function toS8(v) if v >= 0x80 then return v - 0x100 else return v end end
local function toS16(v) if v >= 0x8000 then return v - 0x10000 else return v end end

-- Ally roster Id -> character name, built from the authoritative per-character static-address
-- table rather than hand-typed - a prior mislabeling bug here (this session) came from guessing
-- names instead of reading this table. Ally-only: enemy_data[i]+0x0 for an ENEMY indexes
-- attack_data_table, a separate id space that can coincidentally collide with an ally roster Id.
local idToName = {}
for _, name in ipairs(Names) do
  local rec = CharAddresses[name]
  if rec and rec.Id then idToName[rec.Id] = name end
end

-- classPtrs[actor]->+0x1c resolves to that character's own persistent Stats address (identical
-- resolution path as lib/ActionEnumerator.lua's getStatsAddr/getClassPtr0, kept independent here
-- so this module has no dependency on ActionEnumerator).
local function getStatsAddr(base, actorIdx)
  local classPtrsSlot = base + 0xf84 + actorIdx * 0xc
  local classPtr0raw = memory.read_u32_le(classPtrsSlot + 0)
  if not Address.isValidPointer(classPtr0raw) then return nil end
  local classPtr0 = Address.sanitize(classPtr0raw)
  local statsRaw = memory.read_u32_le(classPtr0 + 0x1c)
  if not Address.isValidPointer(statsRaw) then return nil end
  return Address.sanitize(statsRaw)
end

-- Replicates FUN_800d4ec0 exactly (see module header) - the only way to get a party member's
-- true ATK/DEF pre-round-confirm, since the live combatant array's own +0x30/+0x32 aren't valid
-- yet at that point. Returns computed ATK, DEF.
local function computeAllyATKDEF(statsAddr)
  local pwr = memory.read_u8(statsAddr + 0x10)
  local def = memory.read_u8(statsAddr + 0x12)

  local runeId = memory.read_u8(statsAddr + 0x4c)
  -- Gale Rune (id 0x13) doubles SPD in FUN_800d4ec0, but SPD doesn't feed ATK/DEF - only kept
  -- here for parity with the source function's own field order, no effect on the two outputs.

  -- switch(statsAddr+0x46): case 3 bumps DEF, case 5 bumps SKL - neither feeds ATK/DEF's own
  -- accumulator paths below except through `def`, so only the case-3 branch matters here.
  local switchByte = memory.read_u8(statsAddr + 0x46)
  if switchByte == 3 then
    def = def + memory.read_u8(statsAddr + 0x49) * 3
  end

  -- FUN_800d4ec0's item-bonus loop adds an 8-byte per-item bonus array to ALL 8 output slots,
  -- not just index0(PWR)/index2(DEF) - index6/index7 (the ATK-final/DEF-final accumulators,
  -- both starting at 0) can ALSO receive a DIRECT bonus independent of PWR/DEF, e.g. a generic
  -- "+N ATK"/"+N DEF" accessory rather than a "+N PWR"/"+N DEF-stat" one. Confirmed live 2026-09:
  -- Viktor's two equipped accessories in ZombieDragonStart.State both bonus index7 only (+4,+3),
  -- landing in finalDef (85 base + 7 = 92, matching the real post-confirm value) rather than
  -- index2 - missing this the first time silently undercounted DEF for every character with a
  -- "flat DEF/ATK" accessory (as opposed to a "flat PWR/base-DEF-stat" one).
  local bonus0, bonus2, bonus6, bonus7 = 0, 0, 0, 0
  local itemCount = memory.read_u8(statsAddr + 0x1f)
  for slot = 0, itemCount - 1 do
    local entry = statsAddr + slot * 4
    local itemId = memory.read_u16_le(entry + 0x20)
    local equipped = memory.read_u8(entry + 0x22)
    if itemId ~= 0 and equipped ~= 0 then
      local defPtrRaw = memory.read_u32_le(ITEM_DEFINITION_TABLE + itemId * 4)
      if Address.isValidPointer(defPtrRaw) then
        local defPtr = Address.sanitize(defPtrRaw)
        local flags = memory.read_u16_le(defPtr + 0x1c)
        if (flags & 0x80) ~= 0 then
          bonus0 = bonus0 + toS8(memory.read_u8(defPtr + 0x20 + 0))
          bonus2 = bonus2 + toS8(memory.read_u8(defPtr + 0x20 + 2))
          bonus6 = bonus6 + toS8(memory.read_u8(defPtr + 0x20 + 6))
          bonus7 = bonus7 + toS8(memory.read_u8(defPtr + 0x20 + 7))
        end
      end
    end
  end

  local atk = bonus6 + pwr + bonus0
  local finalDef = bonus7 + def + bonus2

  local weaponType = memory.read_u8(statsAddr + 0x44)
  local weaponLevel = memory.read_u8(statsAddr + 0x45)
  local classPtrRaw = memory.read_u32_le(WEAPON_CLASS_TABLE + weaponType * 4)
  if Address.isValidPointer(classPtrRaw) then
    local classPtr = Address.sanitize(classPtrRaw)
    local classByte = memory.read_u8(classPtr + 0x54)
    local powerAddr = WEAPON_POWER_TABLE + weaponLevel * 2 + classByte * 0x20 + 2
    atk = atk + toS16(memory.read_u16_le(powerAddr))
  end

  return atk, finalDef
end

-- Returns nil (+ a reason) if not currently in a valid, stably-populated battle.
function BattleSnapshot:extract()
  local baseRaw = memory.read_u32_le(Address.BATTLE_STATE_PTR)
  if not Address.isValidPointer(baseRaw) then return nil, "battle struct pointer invalid" end
  local base = Address.sanitize(baseRaw)
  local partyCount = memory.read_u32_le(base + 0x1c)
  local total = memory.read_u32_le(base + 0x24)
  if partyCount < 1 or partyCount > 6 or total < partyCount or total > 16 then
    return nil, "battle struct fields look uninitialized"
  end

  local snapshot = {
    RNGSeed = memory.read_u32_le(Address.RNG),
    -- battle_base+0x4 - CONFIRMED live 2026-09-06 (diffed the whole battle struct across 3
    -- consecutive rounds) to be a genuine round counter, not the boolean "confirmed" flag it
    -- was first taken for: 0 -> 1 -> 2 -> 3, and the only offset in a 0x4000-byte scan with
    -- that consistent per-round delta. A full 32-bit value (upper 3 bytes stay 0).
    -- CORRECTED 2026-09-06: increments the INSTANT a round is confirmed/starts (frame+1 after
    -- confirm), NOT when it finishes - real combat/HP changes continue for hundreds more frames
    -- after this already moved (found while building lib/BattleRoundInput.lua's runTurn(), see
    -- that function's own comments - do NOT use this field to detect "has this round finished
    -- yet"). Still exactly correct for THIS module's own purpose, though: BattleSnapshot only
    -- ever captures pre-confirm (see the module header), so at capture time this correctly
    -- reads "how many rounds have already fully happened before now" - the very next confirm
    -- hasn't occurred yet.
    RoundNumber = memory.read_u32_le(base + 0x4),
    PartyCount = partyCount,
    TotalCombatants = total,
    Combatants = {},
  }

  for idx = 1, total do
    local rec = base + 0xb40 + idx * 0x54
    local ed = base + 0x50 + idx * 0x8c
    local isAlly = idx <= partyCount

    local c = {
      Idx = idx,
      IsAlly = isAlly,
      Id = memory.read_u8(ed + 0x0),
      Busy = memory.read_u8(ed + 0x5),
      HPCurrent = memory.read_u16_le(rec + 0x12),
      HPMax = memory.read_u16_le(rec + 0x10),
      SKL = memory.read_u16_le(rec + 0x26),
      SPD = memory.read_u16_le(rec + 0x2a),
      MGC = memory.read_u16_le(rec + 0x2c),
      LUK = memory.read_u16_le(rec + 0x2e),
      ActionType = memory.read_u8(rec + 0x47),
    }

    if isAlly then
      c.Name = idToName[c.Id]
      local statsAddr = getStatsAddr(base, idx)
      if statsAddr then
        c.ATK, c.DEF = computeAllyATKDEF(statsAddr)
        c.RuneId = memory.read_u8(statsAddr + 0x4c)
        c.MP = {
          memory.read_u8(statsAddr + 0x09),
          memory.read_u8(statsAddr + 0x0a),
          memory.read_u8(statsAddr + 0x0b),
          memory.read_u8(statsAddr + 0x0c),
        }

        -- calc_damage's weapon-elemental-bonus fields, traced directly to its own decompile
        -- (not Characters.lua's named Weapon sub-fields - that file's own "offset by 1" comment
        -- makes its exact byte alignment ambiguous, so this reads calc_damage's confirmed loads
        -- directly instead): WeaponType = statsAddr+0x46; if type is 1 or 3 (the two mastery-
        -- bonus types), calc_damage adds a bonus read from statsAddr+WeaponType+0x46 (a single
        -- derived byte, not a byte range - only meaningful for those two types).
        c.WeaponType = memory.read_u8(statsAddr + 0x46)
        if c.WeaponType == 1 or c.WeaponType == 3 then
          c.WeaponMastery = memory.read_u8(statsAddr + c.WeaponType + 0x46)
        end

        c.Items = {}
        for slot = 0, 8 do
          local entryAddr = statsAddr + 0x20 + slot * 4
          local itemId = memory.read_u16_le(entryAddr + 0x0)
          local quantity = memory.read_u8(entryAddr + 0x3)
          if itemId ~= 0 and quantity > 0 then
            table.insert(c.Items, { Slot = slot, Id = itemId, Quantity = quantity })
          end
        end
      end
    else
      -- Enemies have no equipment system - their final ATK/DEF are set up once at battle/
      -- monster load, not recomputed at round start, and (unlike party members) are already
      -- correct pre-confirm - but at +0x14/+0x18, not +0x30/+0x32 (which stay stale/0 for
      -- enemies too until the round actually starts - confirmed live 2026-09).
      c.ATK = memory.read_u16_le(rec + 0x14)
      c.DEF = memory.read_u16_le(rec + 0x18)
    end

    snapshot.Combatants[idx] = c
  end

  return snapshot
end

return BattleSnapshot
