-- Enumerates every legal (ActionType, AbilitySlot, TargetIdx) combination for a party member,
-- given the live battle state, plus a lazy generator for combining several characters' own
-- enumerations into full-round combinations (the building block for brute-forcing every
-- variation of a round - see docs/game_mechanics/Scripted_Battle_Actions.md's "Enumerating a
-- character's available actions" section for the full mechanism this implements: the Rune
-- ability-set chain, the 32-entry Unite table, and each item's own target-type field).
--
-- Target-type bit meaning (def+0x16 & 3), confirmed live 2026-09-07 by checking known spells'
-- own values against their real-world targeting: Deadly Fingertips and Judgement (both
-- single-enemy-target attack spells) read `3`; Black Shadow and Hell (both hit-everyone, no
-- specific target) read `1`. So: `0`/`1` = no specific target needed (`1` additionally gates
-- on the shared DAT_8017be3c+0x2c counter, not checked here); `2` = single ally target,
-- validated as-is; `3` = single enemy target, with an automatic reselect
-- (FUN_800f6344) if the original selection became invalid - correcting an initial version of
-- this module that had `2`/`3` backwards (inferred from the wrong direction before checking
-- real values).
--
-- Known limitations (documented, not silently ignored):
-- - Rune: assumes every one of a rune's 4 levels is menu-selectable once equipped - doesn't
--   check `Rune.Locked` (Characters_and_Stats.md's Stats+0x4D), which may further restrict
--   this in ways not yet verified against real gameplay.
-- - Rune slot 4 doesn't account for Magic Unite - two characters both selecting their own
--   slot 4 the same round may combo into a different spell than either's solo pick. This
--   module only reports the SOLO resolution; the actual combo is a cross-character
--   interaction for the round-level brute-forcer to handle, not single-character enumeration.
-- - Unite only checks "is everyone this Unite needs currently alive in the party" - not
--   whether they'll actually also choose the same ActionType/AbilitySlot this round. Same
--   cross-character caveat as Magic Unite: real execution depends on what OTHER characters
--   pick, which this module doesn't know about.
-- - Item: **items can never target an enemy at all in this game** (user-confirmed) - the
--   ally-only restriction isn't visible in `battle_try_special_attack`'s own code (its
--   target-type `2`/`3` branch is generic, no ally/enemy distinction), so it's enforced
--   somewhere else not yet located (the item-select/target-select menu, going by the same
--   pattern already found for Unite's character-pairing filter and Rune's per-level story
--   lock - none of those are visible in their own resolver functions either). This module
--   enumerates only living allies for target-type `2`/`3`, matching real play, rather than
--   both pools as an earlier version incorrectly did.

local Address = require "lib.Address"

local ActionEnumerator = {}

-- All KUSEG-stripped (see Address.lua's own convention, e.g. BATTLE_STATE_PTR=0x17be3c for
-- Ghidra's DAT_8017be3c) - these are static main.exe data tables, resident in live PSX RAM
-- from boot, readable the same way as any other fixed global.
local RUNE_ABILITY_SET_TABLE = 0x16a0e0 -- DAT_8016a0e0, indexed by Rune.Id (0-33)
local SPELL_DEFINITION_TABLE = 0x16d33c -- DAT_8016d33c, indexed by resolved spell id (normal casters)
local ALT_ABILITY_TABLE = 0x16a630      -- DAT_8016a630, indexed the same way, for ability-set+0x16==1
local UNITE_ATTACK_TABLE = 0x16d18c     -- DAT_8016d18c, indexed by AbilitySlot (1-32)
local ITEM_DEFINITION_TABLE = 0x167658  -- LAB_80167658, indexed by item id

local ActionType = { ATTACK = 0, DEFEND = 1, RUNE = 2, ITEM = 3, UNITE = 4 }
ActionEnumerator.ActionType = ActionType

-- Reads the live battle state needed by every enumerator below. Returns nil (+ a reason) if
-- not currently in a valid battle.
function ActionEnumerator:readBattleContext()
  local baseRaw = memory.read_u32_le(Address.BATTLE_STATE_PTR)
  if not Address.isValidPointer(baseRaw) then return nil, "battle struct pointer invalid" end
  local base = Address.sanitize(baseRaw)
  local partyCount = memory.read_u32_le(base + 0x1c)
  local total = memory.read_u32_le(base + 0x24)
  if partyCount < 0 or partyCount > 6 or total < partyCount or total > 16 then
    return nil, "battle struct fields look uninitialized"
  end

  local combatants = {}
  for idx = 1, total do
    local rec = base + 0xb40 + idx * 0x54
    local ed = base + 0x50 + idx * 0x8c
    combatants[idx] = {
      Id = memory.read_u8(ed + 0x0),
      HPCurrent = memory.read_u16_le(rec + 0x12),
      HPMax = memory.read_u16_le(rec + 0x10),
    }
  end

  return {
    Base = base,
    PartyCount = partyCount,
    TotalCombatants = total,
    Combatants = combatants,
  }
end

local function livingEnemies(ctx)
  local out = {}
  for idx = ctx.PartyCount + 1, ctx.TotalCombatants do
    local c = ctx.Combatants[idx]
    if c and c.HPCurrent > 0 then table.insert(out, idx) end
  end
  return out
end

local function livingAllies(ctx)
  local out = {}
  for idx = 1, ctx.PartyCount do
    local c = ctx.Combatants[idx]
    if c and c.HPCurrent > 0 then table.insert(out, idx) end
  end
  return out
end

-- class_ptrs[actor]->+0x1c resolves to that character's own persistent Stats address
-- (confirmed identical to Addresses.lua's own Stats field, live-tested 2026-09-07).
local function getClassPtr0(ctx, actorIdx)
  local classPtrsSlot = ctx.Base + 0xf84 + actorIdx * 0xc
  local classPtr0 = memory.read_u32_le(classPtrsSlot + 0)
  if not Address.isValidPointer(classPtr0) then return nil end
  return Address.sanitize(classPtr0)
end

local function getStatsAddr(ctx, actorIdx)
  local classPtr0 = getClassPtr0(ctx, actorIdx)
  if not classPtr0 then return nil end
  local statsAddr = memory.read_u32_le(classPtr0 + 0x1c)
  if not Address.isValidPointer(statsAddr) then return nil end
  return Address.sanitize(statsAddr)
end

-- Rune.Id off the character's own persistent Stats struct (Characters_and_Stats.md).
local function getRuneId(ctx, actorIdx)
  local statsAddr = getStatsAddr(ctx, actorIdx)
  if not statsAddr then return 0 end
  return memory.read_u8(statsAddr + 0x4c)
end

-- Given a resolved spell id and which table it belongs to, returns the list of legal targets
-- for it (def+0x16 & 3) - both tables share this layout, per battle_select_special_ability's
-- own decompile treating either result identically once resolved. See the module header for
-- what each target-type value means (confirmed against Deadly Fingertips/Judgement/Black
-- Shadow/Hell's own real values).
local function targetsForSpellId(ctx, table, spellId)
  local defPtr = memory.read_u32_le(table + spellId * 4)
  if not Address.isValidPointer(defPtr) then return {} end
  defPtr = Address.sanitize(defPtr)
  local targetType = memory.read_u16_le(defPtr + 0x16) & 3
  if targetType == 2 then
    return livingAllies(ctx)
  elseif targetType == 3 then
    return livingEnemies(ctx)
  else
    return { 0 } -- resource-gated / no specific target needed
  end
end

function ActionEnumerator:enumerateAttack(ctx, actorIdx)
  local actions = {}
  for _, target in ipairs(livingEnemies(ctx)) do
    table.insert(actions, { ActionType.ATTACK, 0, target })
  end
  return actions
end

function ActionEnumerator:enumerateDefend(ctx, actorIdx)
  return { { ActionType.DEFEND, 0, 0 } }
end

-- MP1-4 (Characters_and_Stats.md's Stats+0x09..+0x0C) - one pool per spell level. Confirmed
-- live 2026-09-07 (user): a level is only castable with MP[level] > 0 for that level's own
-- pool - McDohl's own MP4==0 in this savestate directly explains why Judgement (his rune's
-- Lv4 spell) isn't actually selectable despite the ability-set table structurally defining it.
local function getMP(ctx, actorIdx, level)
  local statsAddr = getStatsAddr(ctx, actorIdx)
  if not statsAddr then return 0 end
  return memory.read_u8(statsAddr + 0x08 + level) -- level 1..4 -> +0x09..+0x0C
end

function ActionEnumerator:enumerateRune(ctx, actorIdx, lockedLevels)
  local actions = {}
  local runeId = getRuneId(ctx, actorIdx)
  if runeId == 0 then return actions end -- no rune equipped, Rune unavailable

  local abilitySetPtr = memory.read_u32_le(RUNE_ABILITY_SET_TABLE + runeId * 4)
  if not Address.isValidPointer(abilitySetPtr) then return actions end
  abilitySetPtr = Address.sanitize(abilitySetPtr)

  -- Mirrors battle_select_special_ability's own branch exactly: +0x16==0 is a normal
  -- spellcaster (SPELL_DEFINITION_TABLE); ==1 uses the alternate ALT_ABILITY_TABLE; any other
  -- value (e.g. Holy Rune reads 2 - it has no spell list at all, confirmed against the
  -- external Runes reference) means Rune isn't selectable at all with this rune equipped, so
  -- report zero actions deliberately rather than by the coincidence of an invalid pointer.
  local casterFlag = memory.read_u8(abilitySetPtr + 0x16)
  if casterFlag ~= 0 and casterFlag ~= 1 then return actions end
  local spellTable = (casterFlag == 0) and SPELL_DEFINITION_TABLE or ALT_ABILITY_TABLE

  for slot = 1, 4 do
    -- MP gating (confirmed) plus an optional story/scenario-progress lock: some runes (Soul
    -- Eater confirmed by the user) additionally gate individual levels behind story flags
    -- that haven't been located in memory yet - `lockedLevels`, an optional
    -- {[level]=true, ...} set passed in by the caller, is the practical stand-in for that
    -- until the real flag storage is found. Not finding it isn't a silent gap: MP alone
    -- would have wrongly allowed McDohl's Lv2/Lv3 in this exact savestate (MP2=2, MP3=1,
    -- both nonzero) despite them being story-locked - a caller with scenario knowledge needs
    -- to supply that until this is solved properly.
    if getMP(ctx, actorIdx, slot) > 0 and not (lockedLevels and lockedLevels[slot]) then
      local spellId = memory.read_u8(abilitySetPtr + 0x1a + slot)
      for _, target in ipairs(targetsForSpellId(ctx, spellTable, spellId)) do
        table.insert(actions, { ActionType.RUNE, slot, target })
      end
    end
  end
  return actions
end

function ActionEnumerator:enumerateItem(ctx, actorIdx)
  local actions = {}
  local statsAddr = getStatsAddr(ctx, actorIdx)
  if not statsAddr then return actions end

  for slot = 0, 8 do
    local entryAddr = statsAddr + 0x20 + slot * 4
    local itemId = memory.read_u16_le(entryAddr + 0x0)
    local quantity = memory.read_u8(entryAddr + 0x3)
    if itemId ~= 0 and quantity > 0 then
      local itemDefPtr = memory.read_u32_le(ITEM_DEFINITION_TABLE + itemId * 4)
      if Address.isValidPointer(itemDefPtr) then
        itemDefPtr = Address.sanitize(itemDefPtr)
        local targetType = memory.read_u16_le(itemDefPtr + 0x1c) & 3
        local targets
        if targetType == 2 or targetType == 3 then
          -- Items can never target an enemy (user-confirmed) - ally only, regardless of which
          -- of these two values it is (battle_try_special_attack doesn't distinguish them, see
          -- the module header). Both require the target to be alive
          -- (check_combatant_alive) per that same code, so living allies only, not dead ones.
          targets = livingAllies(ctx)
        else
          targets = { 0 }
        end
        for _, target in ipairs(targets) do
          table.insert(actions, { ActionType.ITEM, slot, target })
        end
      end
    end
  end
  return actions
end

function ActionEnumerator:enumerateUnite(ctx, actorIdx)
  local actions = {}
  local aliveIds = {}
  for idx = 1, ctx.PartyCount do
    local c = ctx.Combatants[idx]
    if c and c.HPCurrent > 0 then aliveIds[c.Id] = true end
  end
  local selfId = ctx.Combatants[actorIdx] and ctx.Combatants[actorIdx].Id

  for slot = 1, 32 do
    local defPtr = memory.read_u32_le(UNITE_ATTACK_TABLE + slot * 4)
    if Address.isValidPointer(defPtr) then
      defPtr = Address.sanitize(defPtr)
      local count = memory.read_u8(defPtr + 0x18)
      local allPresent = true
      local selfIncluded = false
      for i = 0, count - 1 do
        local reqId = memory.read_u8(defPtr + 0x1a + i)
        if not aliveIds[reqId] then allPresent = false end
        if reqId == selfId then selfIncluded = true end
      end
      if allPresent and selfIncluded then
        local targetType = memory.read_u16_le(defPtr + 0x16) & 3
        local targets = (targetType == 1) and { 0 } or livingEnemies(ctx)
        for _, target in ipairs(targets) do
          table.insert(actions, { ActionType.UNITE, slot, target })
        end
      end
    end
  end
  return actions
end

-- Full enumeration for one party member: every legal (ActionType, AbilitySlot, TargetIdx).
-- `lockedLevels` is an optional {[runeLevel]=true, ...} set - see enumerateRune's own comment
-- on why this exists (story/scenario-progress rune-level locks, not yet found in memory).
-- See the module header for the Magic Unite / physical Unite cross-character caveats.
function ActionEnumerator:enumerateAll(actorIdx, ctx, lockedLevels)
  ctx = ctx or self:readBattleContext()
  if not ctx then return nil, "not in a valid battle" end
  if actorIdx < 1 or actorIdx > ctx.PartyCount then
    return nil, "actorIdx is not a living party slot"
  end

  local actions = {}
  for _, a in ipairs(self:enumerateAttack(ctx, actorIdx)) do table.insert(actions, a) end
  for _, a in ipairs(self:enumerateDefend(ctx, actorIdx)) do table.insert(actions, a) end
  for _, a in ipairs(self:enumerateRune(ctx, actorIdx, lockedLevels)) do table.insert(actions, a) end
  for _, a in ipairs(self:enumerateItem(ctx, actorIdx)) do table.insert(actions, a) end
  for _, a in ipairs(self:enumerateUnite(ctx, actorIdx)) do table.insert(actions, a) end
  return actions
end

-- Enumerates every living party member's own action list in one call - the per-turn input to
-- combineRoundActions() below. Returns { [actorIdx] = { {actionType,slot,target}, ... }, ... }.
-- `lockedLevelsByActor` is an optional { [actorIdx] = {[runeLevel]=true, ...}, ... } map, for
-- the same story-lock reason as enumerateAll/enumerateRune.
function ActionEnumerator:enumerateRound(lockedLevelsByActor)
  local ctx = self:readBattleContext()
  if not ctx then return nil, "not in a valid battle" end
  local perActor = {}
  for idx = 1, ctx.PartyCount do
    local c = ctx.Combatants[idx]
    if c and c.HPCurrent > 0 then
      perActor[idx] = self:enumerateAll(idx, ctx, lockedLevelsByActor and lockedLevelsByActor[idx])
    end
  end
  return perActor, ctx
end

-- Lazily yields every full-round combination (one action per living party member) as a Lua
-- coroutine iterator - `for combo in ActionEnumerator.combineRoundActions(perActor) do ... end`,
-- where combo = { [actorIdx] = {actionType, slot, target}, ... }. Lazy on purpose: a full
-- cartesian product across 6 characters' own action lists can be huge (this is the intended
-- brute-force search space), so nothing here builds the whole list in memory up front - only
-- combineRoundActions() consumes it, one combination per resume, or CountRoundActions() below
-- to size the search space without materializing it.
function ActionEnumerator.combineRoundActions(perActor)
  local actorIds = {}
  for actorIdx in pairs(perActor) do table.insert(actorIds, actorIdx) end
  table.sort(actorIds)

  return coroutine.wrap(function()
    local function recurse(i, combo)
      if i > #actorIds then
        coroutine.yield(combo)
        return
      end
      local actorIdx = actorIds[i]
      for _, action in ipairs(perActor[actorIdx]) do
        combo[actorIdx] = action
        recurse(i + 1, combo)
      end
      combo[actorIdx] = nil
    end
    recurse(1, {})
  end)
end

-- Size of the full round's search space without generating it - product of each living party
-- member's own action count.
function ActionEnumerator.countRoundActions(perActor)
  local count = 1
  for _, actions in pairs(perActor) do
    count = count * #actions
  end
  return count
end

return ActionEnumerator
