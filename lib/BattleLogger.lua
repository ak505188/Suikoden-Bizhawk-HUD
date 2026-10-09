-- Per-frame battle event logger. Call BattleLogger:update() once per emulator frame; it prints
-- one console line per event (round start, turn start, action start, HP change, round end):
--
--   R1 t  29 rng  6  McDohl's turn
--   R1 t  31 rng  6  McDohl defends
--   R1 t  34 rng  6  Ted uses Medicine on Pahn
--   R1 t  53 rng  6  Ted heals Pahn for 100 (HP 160)
--   R1 t  96 rng 12  Cleo deals 26 to Golem #1 (HP 274)
--   R1 t 303 rng 40  --- Round 1 ends ---
--
-- State reading and the round tick come from the RNG > Combat worker (Worker:run ->
-- readBattleState / currentTick), so the offsets and tick rules live in one place.
--
-- Column meanings:
--   R    BattleState round number (increments the frame the round starts).
--   t    sim tick since round start (Combat worker's currentTick); "?" until a round start has
--        been seen with every frame observed (see Worker:updateTick).
--   rng  number of RNG advances since the battle was first seen, found by LCG-stepping from last
--        frame's RNG to this frame's (event.onmemorywrite is unreliable on this PSX core).
--
-- Round end: BattleState+0x3428 (battle phase) returns to 0 once the round's actions are over,
-- written by battle_process_round_end_status_and_formation (status decay + front-row backfill).
-- It is armed by seeing a driver phase (>= 4) after the round starts, so the menu/transition
-- phases (0 to 3) between rounds never produce a false end. It doesn't fire while anyone is
-- busy, and a late kill/revive delays it; the Fight/Run prompt comes 50 to 85 frames later.
--
-- Known limits:
--   * Damage attribution is a heuristic: the most recently started action whose Target matches
--     the victim, else the most recent Mag/Unt (area) action, else the most recent action. A "?"
--     means no action in the current round matched (poison, counters, reflect, ...).
--   * An action line prints when the actor's ActionTag flips to 1 (executing). Enemy specials are
--     "Special <slot>" - enemy spell names aren't resolved.
--   * Magic Unites print as the initiator's "casts <combo> with <partner>"; damage goes to the initiator.
--   * Enemy combatant records can be junk until the enemy's first turn (see Combat worker NOTE);
--     an HPMax change or a 0 -> nonzero HPMax is treated as population, not damage.

local Address = require "lib.Address"
local Charmap = require "lib.Charmap"
local RNGLib = require "lib.RNG"
local Battle = require "lib.Battle"
local CharAddresses = require "lib.Characters.Addresses"
local CharNames = require "lib.Characters.NamesList"
local Worker = require "modules.RNG.submodules.Combat.worker"

-- Static main.exe tables, same ones lib/ActionEnumerator.lua indexes.
local RUNE_ABILITY_SET_TABLE = 0x16a0e0
local SPELL_DEFINITION_TABLE = 0x16d33c
local ALT_ABILITY_TABLE = 0x16a630
local UNITE_ATTACK_TABLE = 0x16d18c

local CONTINUATION_OFFSET = 0x0c -- BattleState+0xc: an enemy AI returning non-(-1)/0 installs its move here
local PHASE_OFFSET = 0x3428 -- BattleState battle phase, see Battle_Damage_Formula.md
local DRIVER_PHASE_MIN, DRIVER_PHASE_MAX = 4, 6 -- phases 4-6 only exist while a round is being executed
local MAX_SANE_ROUND = 999 -- the struct reads garbage (e.g. round 21247) on the first frames of a battle

local RNG_FRAMES_MAX = 216000 -- RNGByFrame is reset past this (one hour of frames)
local MAX_RNG_STEPS = 4096 -- per frame; beyond this the RNG count resyncs instead of guessing

local idToName = {}
for _, name in ipairs(CharNames) do
  local rec = CharAddresses[name]
  if rec and rec.Id then idToName[rec.Id] = name end
end

local BattleLogger = {
  Sink = function(line) console.log(line) end,
  InBattle = false,
  LastFrame = nil,
  LastRound = nil,
  LastActor = nil,
  LastHP = nil,      -- idx -> { hp, max }
  LastRNG = nil,
  RNGCount = 0,
  RNGByFrame = {},   -- emu frame -> { rng, count }, so a rewind restores the RNG count
  RNGFrameCount = 0,
  Started = nil,     -- idx -> order the actor's action started this round (ActionTag -> 1)
  StartOrder = 0,
  Area = {},          -- idx -> true when the action is an enemy continuation special (hits several targets)
  TurnLogged = {},    -- idx -> true once "X's turn" was printed this round
  RoundArmed = false, -- a driver phase was seen this round, so phase 0 now means "round ended"
}

local function safeString(addr)
  local ok, s = pcall(Charmap.readStringFromMemory, addr, 16)
  if ok and s then s = s:match("^%s*(.-)%s*$") end -- names are space-padded ("Zombie Dragon ")
  if ok and s and s ~= "" then return s end
  return nil
end

local function ptrString(ptr)
  if not Address.isValidPointer(ptr) then return nil end
  return safeString(Address.sanitize(ptr))
end

local function statsAddr(state, idx)
  local c = memory.read_u32_le(state.Base + 0xf84 + idx * 0xc)
  if not Address.isValidPointer(c) then return nil end
  local p = memory.read_u32_le(Address.sanitize(c) + 0x1c)
  if not Address.isValidPointer(p) then return nil end
  return Address.sanitize(p)
end

-- Allies: roster name. Enemies: species name from enemy_data+8, "#k" appended when several
-- living-or-dead enemies share a name (k = order of appearance in the actor list).
function BattleLogger:label(state, idx)
  local c = state.Combatants[idx]
  if not c then return "#" .. tostring(idx) end
  if idx <= state.PartyCount then return idToName[c.Id] or ("Ally" .. idx) end

  local function nameOf(i)
    -- MonsterRecord via BattleState.pAttackDataTable[Id] (docs Turn_Order.md); name at +0.
    local rows = memory.read_u32_le(state.Base + 0x1344)
    if not Address.isValidPointer(rows) then return "Enemy" .. i end
    local id = state.Combatants[i].Id
    return ptrString(memory.read_u32_le(Address.sanitize(rows) + id * 4)) or ("Enemy" .. i)
  end
  local name = nameOf(idx)
  local same, nth = 0, 0
  for i = state.PartyCount + 1, state.TotalCombatants do
    if nameOf(i) == name then
      same = same + 1
      if i == idx then nth = same end
    end
  end
  return same > 1 and string.format("%s #%d", name, nth) or name
end

-- Spell definition pointer for a party member's Rune slot, or nil. Same lookup the game's
-- battle_select_special_ability does (rune ability set -> spell id -> definition table).
local function spellDefinition(state, idx, slot)
  local st = statsAddr(state, idx)
  if not st then return nil end
  local runeId = memory.read_u8(st + 0x4c)
  local setPtr = memory.read_u32_le(RUNE_ABILITY_SET_TABLE + runeId * 4)
  if runeId == 0 or not Address.isValidPointer(setPtr) then return nil end
  setPtr = Address.sanitize(setPtr)
  local table = memory.read_u8(setPtr + 0x16) == 1 and ALT_ABILITY_TABLE or SPELL_DEFINITION_TABLE
  local spellId = memory.read_u8(setPtr + 0x1a + slot)
  return memory.read_u32_le(table + spellId * 4)
end

-- Lv4 spell id (the slot-4 entry of the rune's ability set), or nil for the alternate table.
local function spellId(state, idx, slot)
  local st = statsAddr(state, idx)
  if not st then return nil end
  local runeId = memory.read_u8(st + 0x4c)
  local setPtr = memory.read_u32_le(RUNE_ABILITY_SET_TABLE + runeId * 4)
  if runeId == 0 or not Address.isValidPointer(setPtr) then return nil end
  setPtr = Address.sanitize(setPtr)
  if memory.read_u8(setPtr + 0x16) == 1 then return nil end
  return memory.read_u8(setPtr + 0x1a + slot)
end

-- Magic Unite combos (battle_check_magic_unite): two Lv4 spell ids -> combo name. The combo structs
-- have no charmap name, so they're named here. Pairs are keyed low*100+high.
local UNITE_SPELLS = {
  [4 * 100 + 24] = "Scorched Earth", -- Explosion + Earthquake
  [16 * 100 + 24] = "Storm Fang", -- Shining Wind + Earthquake
  [4 * 100 + 20] = "Blazing Camp", -- Explosion + Ball of Lightning
  [12 * 100 + 20] = "Thor", -- Rain of Kindness + Ball of Lightning
  [12 * 100 + 16] = "Water Dragon", -- Rain of Kindness + Shining Wind
}
local THOR_KEY = 12 * 100 + 20

local function spellName(state, idx, slot)
  local def = spellDefinition(state, idx, slot)
  return def and ptrString(def)
end

-- The spell's target flags word (definition +0x16): bit 0x8 = ally audience; low 2 bits 0/1 = hits a
-- whole side, 2/3 = one target. See Battle_Damage_Formula.md "+0x16 flags word".
local function spellFlags(state, idx, slot)
  local def = spellDefinition(state, idx, slot)
  if not def or not Address.isValidPointer(def) then return nil end
  return memory.read_u8(Address.sanitize(def) + 0x16)
end

local function itemName(state, idx, slot)
  local st = statsAddr(state, idx)
  if not st then return nil end
  local id = memory.read_u16_le(st + 0x20 + slot * 4)
  if id == 0 then return nil end
  local ok, name = pcall(Battle.getItemName, id)
  return ok and name or nil
end

local function uniteName(slot)
  return ptrString(memory.read_u32_le(UNITE_ATTACK_TABLE + slot * 4))
end

-- The initiator of a Magic Unite is whoever rolled first; the partner is the first other ally with
-- a queued Lv4 cast of a pairing spell, and its ActionTag is set to 1 without it ever being the
-- current actor (so it never gets a turn or action line of its own). Returns partner idx and the
-- combo name, or nil.
function BattleLogger:findUnite(state, idx)
  local mine = spellId(state, idx, 4)
  if not mine then return nil end
  for p = 1, state.PartyCount do
    local c = state.Combatants[p]
    if p ~= idx and c.ActionTag == 1 and not self.Started[p] and c.ActionType == 2 and c.AbilitySlot == 4 then
      local theirs = spellId(state, p, 4)
      local key = theirs and (math.min(mine, theirs) * 100 + math.max(mine, theirs))
      if key and UNITE_SPELLS[key] then return p, UNITE_SPELLS[key], key end
    end
  end
  return nil
end

-- `newCont`: BattleState+0xc on the frame ActionTag flipped. An enemy AI that picks anything other
-- than the plain Attack (returns -1) installs its move's continuation there on that frame, while
-- ActionType stays 0 - so ActionType alone makes every such move look like "attacks" (Ain Gide's
-- AOE special, Zombie Dragon's Fire Breath, ...). The plain Attack path clears it (to 0) on the
-- same frame, so a valid code pointer here means a special, even when the same move repeats and
-- the value is unchanged from the previous turn.
function BattleLogger:describeAction(state, idx, newCont)
  local c = state.Combatants[idx]
  local isAlly = idx <= state.PartyCount
  local target = (c.Target ~= Worker.UnsetValue and c.Target >= 1 and c.Target <= state.TotalCombatants)
    and self:label(state, c.Target) or nil
  local onTarget = target and (" on " .. target) or ""
  local t = c.ActionType
  if not isAlly and t == 0 and newCont and newCont >= 0x80010000 and newCont < 0x80200000 then
    self.Area[idx] = true -- the move's own script decides who gets hit (usually everyone)
    return string.format("uses a special move (continuation %08x)", newCont)
  end
  if t == 0 then return target and ("attacks " .. target) or "attacks" end
  if t == 1 then return "defends" end
  if t == 2 then
    if not isAlly then return string.format("casts Special %d%s", c.AbilitySlot, onTarget) end
    if c.AbilitySlot == 4 then
      local partner, combo, key = self:findUnite(state, idx)
      if partner then
        if key ~= THOR_KEY then self.Area[idx] = true end -- everything but Thor hits a whole side
        return string.format("casts %s with %s%s", combo, self:label(state, partner), onTarget)
      end
    end
    return string.format("casts %s%s", spellName(state, idx, c.AbilitySlot) or ("slot " .. c.AbilitySlot), onTarget)
  end
  if t == 3 then
    return string.format("uses %s%s", itemName(state, idx, c.AbilitySlot) or ("slot " .. c.AbilitySlot), onTarget)
  end
  if t == 4 then
    return string.format("starts %s%s", uniteName(c.AbilitySlot) or ("Unite " .. c.AbilitySlot), onTarget)
  end
  return "does action " .. tostring(t)
end

local function isAlly(state, idx) return idx <= state.PartyCount end

-- Could the already-started action of `idx` have changed `victim`'s HP? Single-target actions need
-- Target == victim. Area actions (AOE spells, Unites, enemy continuation specials) leave Target
-- unset or ignore it, and hit a whole side: the opposite one, or the caster's own for an ally-
-- audience spell. Without the side test an enemy-side Earthquake "hit" the caster's own allies.
function BattleLogger:couldHit(state, idx, victim)
  local c = state.Combatants[idx]
  local explicit = c.Target ~= Worker.UnsetValue and c.Target >= 1 and c.Target <= state.TotalCombatants
  local sameSide, area = false, false
  if self.Area[idx] then
    area = true
  elseif c.ActionType == 4 then
    area = not explicit
  elseif c.ActionType == 2 then
    if isAlly(state, idx) then
      local flags = spellFlags(state, idx, c.AbilitySlot)
      if flags then
        sameSide = (flags & 8) ~= 0
        area = (flags & 3) <= 1
      else
        area = not explicit
      end
    else
      area = not explicit -- enemy "Special N" with no target: whole opposing side
    end
  end
  if explicit and c.Target == victim then return true end
  if area then return (isAlly(state, victim) == isAlly(state, idx)) == sameSide end
  return false
end

-- Picks the actor to blame for a change to `victim`: the most recently started action that could have
-- hit it (couldHit). Else a counterattack: the victim's own started single-target attack makes its
-- target the culprit. Else the most recent action of any kind, flagged unmatched ("?").
-- Returns actor, matched, kind ("counter" for the counterattack case).
function BattleLogger:attributeActor(state, victim)
  local best, bestAny
  for idx, order in pairs(self.Started) do
    if state.Combatants[idx] then
      if self:couldHit(state, idx, victim) and (not best or order > self.Started[best]) then best = idx end
      if not bestAny or order > self.Started[bestAny] then bestAny = idx end
    end
  end
  if best then return best, true end

  local vc = self.Started[victim] and state.Combatants[victim]
  if vc and vc.ActionType == 0 and vc.Target ~= Worker.UnsetValue and vc.Target >= 1
    and vc.Target <= state.TotalCombatants and isAlly(state, vc.Target) ~= isAlly(state, victim) then
    return vc.Target, true, "counter"
  end
  return bestAny, false
end

-- Counts RNG advances since the previous call. Returns false when the new value isn't within
-- MAX_RNG_STEPS of the old one (savestate load, script poke), in which case the count resyncs.
function BattleLogger:trackRNG()
  local rng = memory.read_u32_le(Address.RNG)
  local jumped = false
  if self.LastRNG ~= nil and rng ~= self.LastRNG then
    local cur, steps = self.LastRNG, 0
    while cur ~= rng and steps < MAX_RNG_STEPS do
      cur = RNGLib.nextRNG(cur)
      steps = steps + 1
    end
    if cur == rng then self.RNGCount = self.RNGCount + steps else jumped = true end
  end
  self.LastRNG = rng
  return not jumped
end

-- `tickOverride`: print this tick instead of the worker's (the round marker prints t 0, see below).
function BattleLogger:log(state, text, tickOverride)
  local tick = tickOverride or Worker:currentTick()
  self.Sink(string.format("R%d t%4s rng %3d  %s", state.RoundNumber,
    tick and tostring(tick) or "?", self.RNGCount, text))
end

-- True while the round driver is running a round (phases 4-6). Garbage or out-of-range phase values,
-- and round 0 (the setup state before round 1), never count.
local function inDriverPhase(state)
  local phase = memory.read_u32_le(state.Base + PHASE_OFFSET)
  return state.RoundNumber > 0 and phase >= DRIVER_PHASE_MIN and phase <= DRIVER_PHASE_MAX, phase
end

function BattleLogger:reset()
  self.InBattle = false
  self.LastRound, self.LastActor, self.LastHP, self.LastRNG, self.LastTag = nil, nil, nil, nil, nil
  self.RNGCount = 0
  self.Started, self.StartOrder = {}, 0
  self.RoundArmed, self.Area, self.TurnLogged = false, {}, {}
end

-- Adopts the current state as the baseline without logging anything. The RNG count is restored
-- when this exact frame (same RNG value) was seen before, e.g. after a rewind.
function BattleLogger:resync(state, frame)
  local seen = self.RNGByFrame[frame]
  if seen and seen.rng == self.LastRNG then self.RNGCount = seen.count end
  self.LastRound = state.RoundNumber
  self.LastActor = state.CurrentActor
  self.LastTag, self.Started, self.StartOrder = {}, {}, 0
  self.RoundArmed = (inDriverPhase(state))
  self.Area, self.TurnLogged = {}, {}
  for idx = 1, state.TotalCombatants do
    local c = state.Combatants[idx]
    self.LastTag[idx] = c.ActionTag
    -- Actions already underway keep their attribution order (by actor index; true order is lost).
    if c.ActionTag == 1 and (c.HPCurrent > 0 or idx == state.CurrentActor) then
      self.StartOrder = self.StartOrder + 1
      self.Started[idx] = self.StartOrder
    end
  end
  self:snapshotHP(state)
end

function BattleLogger:snapshotHP(state)
  self.LastHP = {}
  for idx, c in ipairs(state.Combatants) do
    self.LastHP[idx] = { hp = c.HPCurrent, max = c.HPMax }
  end
end

-- Standalone use (scripts/BattleLog.lua): advances the Combat worker itself.
function BattleLogger:update()
  Worker:run()
  self:process()
end

-- Processes the worker's current state. The HUD calls this from Worker:run (after it has read
-- state) so the worker isn't run twice per frame.
function BattleLogger:process()
  local state = Worker.State
  if not Worker.InBattle or not state or state.TotalCombatants == 0 then
    if self.InBattle then self.Sink("--- Battle ended ---") end
    self:reset()
    return
  end

  -- BattleState isn't populated on the first frames of a battle (round reads garbage like 21247):
  -- wait for a sane read before logging anything, so no battle start / round lines come from it.
  if state.RoundNumber > MAX_SANE_ROUND then return end

  local frame = emu.framecount()
  local prevFrame = self.LastFrame
  local continuous = prevFrame ~= nil and frame == prevFrame + 1
  if frame == prevFrame then return end -- paused: nothing advanced
  self.LastFrame = frame

  local rngContinuous = self:trackRNG()
  local wasInBattle = self.InBattle
  if not self.InBattle then
    self.InBattle = true
    self.Sink(string.format("--- Battle start: %d allies vs %d enemies ---", state.PartyCount, state.EnemyCount))
    self.LastRound = nil
  end
  if wasInBattle and (not continuous or not rngContinuous) then
    -- Rewind / savestate load / script-side RNG write: whatever happened between the last frame
    -- we saw and this one isn't replayed as events. Re-baseline from the current state silently;
    -- only a forward gap (frames we never saw) gets a marker line.
    if prevFrame and frame > prevFrame then self.Sink("--- frames skipped: baselines reset ---") end
    self:resync(state, frame)
  end
  if continuous and rngContinuous then
    if self.RNGFrameCount >= RNG_FRAMES_MAX then self.RNGByFrame, self.RNGFrameCount = {}, 0 end
    if not self.RNGByFrame[frame] then self.RNGFrameCount = self.RNGFrameCount + 1 end
    self.RNGByFrame[frame] = { rng = self.LastRNG, count = self.RNGCount }
  end
  if state.RoundNumber ~= self.LastRound then
    self.LastRound = state.RoundNumber
    -- CurrentActor still holds the previous round's last actor until the first turn roll; take it
    -- as the baseline so it isn't reported as a new turn (see the action-start fallback below).
    self.LastActor = state.CurrentActor
    self.Started, self.StartOrder = {}, 0
    self.Area, self.TurnLogged = {}, {}
    self.RoundArmed = false
    -- Round 0 is the battle's setup state, before the first round starts: no line for it.
    if state.RoundNumber > 0 then
      -- The worker's tick is -1 on this frame (the round-start refresh, one frame before the round
      -- driver's tick 0); the marker prints as t 0 so a round's first line starts at tick 0.
      self:log(state, string.format("--- Round %d ---", state.RoundNumber), 0)
    end
  end

  -- Round end: the battle phase drops back to 0 after having been in a driver phase this round.
  local driving, phase = inDriverPhase(state)
  if driving then
    self.RoundArmed = true
  elseif phase == 0 and self.RoundArmed then
    self.RoundArmed = false
    self:log(state, string.format("--- Round %d ends ---", state.RoundNumber))
  end

  -- Turn start: CurrentActor changes to a real combatant.
  local actor = state.CurrentActor
  if actor ~= self.LastActor and actor >= 1 and actor <= state.TotalCombatants then
    self.TurnLogged[actor] = true
    self:log(state, self:label(state, actor) .. "'s turn")
  end
  self.LastActor = actor

  -- Action start: ActionTag 0 -> 1 (a transition, so tags already 1 at battle start / after a
  -- jump / carried over from the previous round aren't reported as new actions).
  local cont = memory.read_u32_le(state.Base + CONTINUATION_OFFSET)
  local lastTag = self.LastTag or {}
  self.LastTag = {}
  for idx = 1, state.TotalCombatants do
    local c = state.Combatants[idx]
    self.LastTag[idx] = c.ActionTag
    -- Only the combatant holding the turn really starts an action. Others get their tag flipped
    -- to 1 as a side effect while someone else acts: killed-before-acting combatants (Krin dead
    -- at t315, tag flipped at t360 with stale Type/Target) and combatants doomed by a pending
    -- HP delta (Hell: every enemy's tag flips mid-cast while their HP still reads full).
    local realAction = idx == state.CurrentActor
    if c.ActionTag == 1 and lastTag[idx] == 0 and not self.Started[idx] and realAction then
      self.StartOrder = self.StartOrder + 1
      self.Started[idx] = self.StartOrder
      -- The round's first actor can equal the previous round's last (CurrentActor never changed),
      -- so its turn line wasn't printed above.
      if not self.TurnLogged[idx] then
        self.TurnLogged[idx] = true
        self:log(state, self:label(state, idx) .. "'s turn")
      end
      self:log(state, string.format("%s %s", self:label(state, idx), self:describeAction(state, idx, cont)))
    end
  end
  -- HP changes.
  if self.LastHP then
    for idx = 1, state.TotalCombatants do
      local c, prev = state.Combatants[idx], self.LastHP[idx]
      if prev and prev.max ~= 0 and prev.max == c.HPMax and prev.hp ~= c.HPCurrent then
        local who = self:label(state, idx)
        local attacker, matched, kind = self:attributeActor(state, idx)
        local name = attacker and (self:label(state, attacker) .. (kind == "counter" and " (counter)" or
          (matched and "" or "?"))) or "?"
        if prev.hp == 0 and c.HPCurrent > 0 and idx > state.PartyCount then
          -- an enemy back from 0 HP is a scripted respawn (Queen Ant's ants), not a heal
          self:log(state, string.format("%s revives (HP %d)", who, c.HPCurrent))
        elseif c.HPCurrent < prev.hp then
          self:log(state, string.format("%s deals %d to %s (HP %d)%s", name, prev.hp - c.HPCurrent, who,
            c.HPCurrent, c.HPCurrent == 0 and " - defeated" or ""))
        else
          self:log(state, string.format("%s heals %s for %d (HP %d)", name, who, c.HPCurrent - prev.hp,
            c.HPCurrent))
        end
      end
    end
  end
  self:snapshotHP(state)
end

return BattleLogger
