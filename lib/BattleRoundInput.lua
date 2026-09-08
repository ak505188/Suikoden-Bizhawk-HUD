-- Drives the round-start menu (Fight/Run/Bribe/Free Will) programmatically, then overwrites
-- whatever actions get chosen before the round actually starts - see
-- docs/game_mechanics/Scripted_Battle_Actions.md for the full investigation this is built
-- from, including why a *pure* memory-only bypass (no simulated button press at all) isn't
-- possible: confirm/cancel/cursor-move are read from globals (DAT_8017be4c/DAT_8017c000)
-- recomputed from genuine pad state every frame, faster than any hook available on this core
-- can intercept.
--
-- The optimized recipe (2 taps total, regardless of party size - down from 1 + 2*partyCount
-- + 1 originally): wait for the Fight/Run/Bribe/Free Will prompt to be genuinely ready, pick
-- **Free Will** by writing its choice value directly (skips per-character command/target
-- navigation entirely - Free Will has the AI populate every living party member's
-- ActionType/AbilitySlot/TargetIdx in one shot), confirm once, overwrite any/all combatants'
-- actions with setAction()/setActions() (this sticks the same way it does after manual
-- navigation - the confirm step reads combatant_rec fresh, it doesn't cache selections
-- elsewhere), then confirm once more to actually start the round. Leaving a combatant
-- un-overridden keeps whatever Free Will's AI picked for them - useful for mixed manual/AI
-- control, not just all-or-nothing.

local Address = require "lib.Address"
local Buttons = require "lib.Buttons"
local Gamestate = require "lib.Enums.Gamestate"

local BattleRoundInput = {}

-- battle_menu_fight_run_bribe_freewill, 0x800ea2a8 - see Scripted_Battle_Actions.md. Its own
-- phase(+0x4) reaches 2 as the stable "genuinely waiting for a real confirm" state; phase 1 is
-- only a one-tick transient on the way there and isn't safe to write through (this function's
-- own 1->2 transition unconditionally resets the choice field to 0, so a write timed during
-- that transient gets silently clobbered - confirmed by testing).
local FIGHT_MENU_HANDLER = 0x800ea2a8
local FIGHT_MENU_STABLE_PHASE = 2

local MENU_STATE_PTR_ADDR = 0x179fe8 -- DAT_80179fe8, the menu system's own persistent context
local MENU_COROUTINE_SLOT_ADDR = 0x17da9c -- DAT_8017da90 slot 3 - the menu system's own
                                           -- scheduler slot, separate from
                                           -- battle_advance_turn/battle_dispatch_current_actor_action

-- Values for DAT_80179fe8+8 at the Fight/Run/Bribe/Free Will prompt.
BattleRoundInput.Choice = {
  FIGHT = 0,
  RUN = 1,
  BRIBE = 2,
  FREE_WILL = 3,
}

local function advanceFrames(n)
  for i = 1, n do
    emu.frameadvance()
  end
end

-- Holds `button` for holdFrames, then releases everything for releaseFrames. Needs a
-- multi-frame hold (not a single-frame press) to register reliably against this game's input
-- polling - a bare 1-frame press was unreliable in testing.
local function tap(button, holdFrames, releaseFrames)
  holdFrames = holdFrames or 2
  releaseFrames = releaseFrames or 15
  for i = 1, holdFrames do
    button:press()
    advanceFrames(1)
  end
  Buttons:clear()
  advanceFrames(releaseFrames)
end

-- Returns (menuBase, phase, activeHandler) for the shared menu-system context, or nil if it
-- isn't allocated yet.
local function readMenuState()
  local raw = memory.read_u32_le(MENU_STATE_PTR_ADDR)
  if not Address.isValidPointer(raw) then return nil end
  local base = Address.sanitize(raw)
  local phase = memory.read_u32_le(base + 0x4)
  local activeHandler = memory.read_u32_le(MENU_COROUTINE_SLOT_ADDR)
  return base, phase, activeHandler
end

-- Waits until `expectedHandler` is the menu system's active coroutine handler and its own
-- phase equals `stablePhase`, held for 3 consecutive frames (a single-frame match can be a
-- one-tick transition between phases, not the real "waiting for input" state). Returns the
-- menu-state base address, or nil on timeout.
function BattleRoundInput:waitForMenuReady(expectedHandler, stablePhase, maxFrames)
  maxFrames = maxFrames or 600
  local stableCount = 0
  for i = 1, maxFrames do
    local base, phase, activeHandler = readMenuState()
    if base and activeHandler == expectedHandler and phase == stablePhase then
      stableCount = stableCount + 1
      if stableCount >= 3 then return base end
    else
      stableCount = 0
    end
    emu.frameadvance()
  end
  return nil
end

-- Waits for the Fight/Run/Bribe/Free Will prompt (from any point before it, e.g. right after
-- loading a savestate positioned at the start of a battle), selects `choice`
-- (BattleRoundInput.Choice.*) by writing it directly - no cursor navigation needed - and
-- confirms it. Returns the sanitized battle-state base address (Address.BATTLE_STATE_PTR) on
-- success, or nil if the prompt never became ready within the frame budget.
function BattleRoundInput:chooseRoundOption(choice)
  local menuBase = self:waitForMenuReady(FIGHT_MENU_HANDLER, FIGHT_MENU_STABLE_PHASE)
  if not menuBase then return nil end
  memory.write_u32_le(menuBase + 8, choice)
  tap(Buttons.Cross)
  local baseRaw = memory.read_u32_le(Address.BATTLE_STATE_PTR)
  if not Address.isValidPointer(baseRaw) then return nil end
  return Address.sanitize(baseRaw)
end

-- Overwrites party member `idx`'s (1-indexed actor number) queued action directly in the live
-- battle struct - the same combatant_rec+0x47/0x48/0x49 fields
-- modules/RNG/submodules/Combat/ActionEditMenu.lua edits live. Call after chooseRoundOption()
-- and before confirmRound(). Leaving a combatant un-set keeps whatever Free Will's AI (or the
-- default Attack, for the other Choice values) already picked for them.
function BattleRoundInput:setAction(idx, actionType, abilitySlot, target)
  local baseRaw = memory.read_u32_le(Address.BATTLE_STATE_PTR)
  if not Address.isValidPointer(baseRaw) then return false end
  local base = Address.sanitize(baseRaw)
  local rec = base + 0xb40 + idx * 0x54
  memory.write_u8(rec + 0x47, actionType)
  memory.write_u8(rec + 0x48, abilitySlot or 0)
  memory.write_u8(rec + 0x49, target or 0)
  return true
end

-- Convenience wrapper: actions is a 1-indexed array of {actionType, abilitySlot, target}
-- (nil entries are skipped, so a sparse array only overrides the slots given).
function BattleRoundInput:setActions(actions)
  for idx, action in ipairs(actions) do
    if action then
      self:setAction(idx, action[1], action[2], action[3])
    end
  end
end

-- Confirms the round with whatever's currently in every combatant's action fields, starting
-- execution. A small settle pad (rather than tapping instantly) gave more reliable results in
-- testing than confirming the same frame as the last setAction() write.
function BattleRoundInput:confirmRound()
  advanceFrames(10)
  tap(Buttons.Cross)
end

local function isInBattle()
  return memory.read_u8(Address.GAMESTATE) == Gamestate.BATTLE
end

-- Every combatant's HP, keyed by 1-indexed actor number (same convention as combatant_rec
-- throughout this project).
local function captureHP(base, total)
  local hp = {}
  for idx = 1, total do
    local rec = base + 0xb40 + idx * 0x54
    hp[idx] = {
      HPCurrent = memory.read_u16_le(rec + 0x12),
      HPMax = memory.read_u16_le(rec + 0x10),
    }
  end
  return hp
end

-- Waits for the round that was just confirmed to actually finish. **NOT** `battle_base+0x4`
-- (the round counter) - confirmed live 2026-09-06 that it increments the INSTANT a round
-- starts (the very first frame after confirm), not when it finishes: real combat/HP changes
-- continued for 900+ more frames after the counter had already moved. Using it as a completion
-- signal returned almost immediately, before any actions had actually resolved - a real bug,
-- caught by testing with a guaranteed-damaging action set and finding HP hadn't moved at all.
--
-- The correct signal is the SAME one used to start a round in the first place: the Fight/Run/
-- Bribe/Free Will prompt becoming ready again (it only reappears once every combatant's action
-- has fully resolved), or the gamestate leaving BATTLE entirely (battle ended - victory or
-- defeat, no next round to wait for). Returns "round_complete", "battle_ended", or nil on
-- timeout.
function BattleRoundInput:waitForRoundComplete(maxFrames)
  maxFrames = maxFrames or 6000
  local stableCount = 0
  for i = 1, maxFrames do
    if not isInBattle() then return "battle_ended" end
    local base, phase, activeHandler = readMenuState()
    if base and activeHandler == FIGHT_MENU_HANDLER and phase == FIGHT_MENU_STABLE_PHASE then
      stableCount = stableCount + 1
      if stableCount >= 3 then return "round_complete" end
    else
      stableCount = 0
    end
    emu.frameadvance()
  end
  return nil
end

-- Runs one full round end-to-end: applies `actions` (same sparse-array shape as setActions -
-- nil entries keep whatever Free Will's AI already picked), confirms, waits for it to actually
-- finish, and captures a TurnResult - the emulator-side half of the shared InitialState/
-- TurnResult contract with the planned pure-code simulator (see
-- docs/game_mechanics/Scripted_Battle_Actions.md's "InitialState snapshot" section - this is
-- its natural counterpart, capturing what a round DID rather than what it started from).
--
-- Returns (result, nil) on success or (nil, reason) on failure. `result` is:
--   {
--     RoundNumber = <the round that just completed, 0-indexed - battle_base+0x4's value BEFORE
--       this round was confirmed, since that field increments at round START, not completion>,
--     Outcome = "ongoing" | "victory" | "defeat",
--     RNGSeedBefore, RNGSeedAfter = <Address.RNG before/after - the whole future roll stream
--       is determined by RNGSeedAfter, so this is what lets a caller chain into the next turn>,
--     Combatants = { [idx] = { HPBefore, HPAfter, HPMax, Alive } },
--   }
--
-- Outcome detection is best-effort and not yet live-validated against a real victory/defeat
-- (only tested against ordinary "battle continues" rounds) - "defeat" is read straight off
-- Gamestate.GAME_OVER (a real, documented enum value), but "victory" is inferred from "gamestate
-- left BATTLE without hitting GAME_OVER first", which hasn't been confirmed against an actual
-- won battle yet.
function BattleRoundInput:runTurn(actions)
  local baseRaw = memory.read_u32_le(Address.BATTLE_STATE_PTR)
  if not Address.isValidPointer(baseRaw) then return nil, "not in battle" end
  local base = Address.sanitize(baseRaw)
  local total = memory.read_u32_le(base + 0x24)
  local roundBefore = memory.read_u32_le(base + 0x4)
  local rngBefore = memory.read_u32_le(Address.RNG)
  local hpBefore = captureHP(base, total)

  local newBase = self:chooseRoundOption(self.Choice.FREE_WILL)
  if not newBase then return nil, "round-start menu never became ready" end
  self:setActions(actions or {})
  self:confirmRound()

  local reason = self:waitForRoundComplete()
  if not reason then return nil, "round never completed within frame budget" end

  local rngAfter = memory.read_u32_le(Address.RNG)
  local gamestate = memory.read_u8(Address.GAMESTATE)
  local outcome = "ongoing"
  if gamestate == Gamestate.GAME_OVER then
    outcome = "defeat"
  elseif reason == "battle_ended" then
    outcome = "victory"
  end

  -- Only re-read HP if the round genuinely continued into a next round with the same battle
  -- struct still live - once the battle's over the struct may no longer be meaningful/valid.
  local hpAfter = hpBefore
  if reason == "round_complete" then
    hpAfter = captureHP(base, total)
  end

  local combatants = {}
  for idx = 1, total do
    combatants[idx] = {
      HPBefore = hpBefore[idx].HPCurrent,
      HPAfter = hpAfter[idx].HPCurrent,
      HPMax = hpBefore[idx].HPMax,
      Alive = hpAfter[idx].HPCurrent > 0,
    }
  end

  return {
    RoundNumber = roundBefore,
    Outcome = outcome,
    RNGSeedBefore = rngBefore,
    RNGSeedAfter = rngAfter,
    Combatants = combatants,
  }
end

return BattleRoundInput
