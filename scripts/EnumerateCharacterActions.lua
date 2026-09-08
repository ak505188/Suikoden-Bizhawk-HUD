-- Validation/demo for lib/ActionEnumerator.lua: loads a savestate positioned inside an active
-- battle, enumerates every living party member's full legal action list, prints each one
-- (decoded to readable form where possible), and reports the size of the full round's
-- combined search space (lib.ActionEnumerator.combineRoundActions/countRoundActions) - the
-- number this project's eventual brute-forcer will actually have to work through for turn 1.
--
-- USAGE: edit BASE_SAVE below, run via
--   scripts/spawn-headless-emuhawk.sh scripts/EnumerateCharacterActions.lua
--
-- See docs/game_mechanics/Scripted_Battle_Actions.md's "Enumerating a character's available
-- actions" section for the mechanism this exercises.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path

local ActionEnumerator = require "lib.ActionEnumerator"
local CharAddresses = require "lib.Characters.Addresses"
local Names = require "lib.Characters.NamesList"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/ZombieDragonStart.State"
local OUT = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/EnumerateCharacterActions.txt"

local lines = {}
local function log(s) table.insert(lines, s) end

local ActionTypeNames = { [0] = "Attack", [1] = "Defend", [2] = "Rune", [3] = "Item", [4] = "Unite" }

-- Ally roster Id -> character name, built from the authoritative per-character static-address
-- table (lib/Characters/Addresses.lua) rather than hand-typed/half-remembered, since that was
-- the actual source of a prior mislabeling bug - the underlying memory reads were correct all
-- along, only the printed names were wrong. NOTE: this table is ally-only - do not use it to
-- name enemy combatants (enemy_data+0x0 indexes attack_data_table, a separate id space that
-- can coincidentally collide with an ally roster Id).
local idToName = {}
for _, name in ipairs(Names) do
  local rec = CharAddresses[name]
  if rec and rec.Id then idToName[rec.Id] = name end
end

local ok, err = pcall(function()
  savestate.load(BASE_SAVE)
  for i = 1, 200 do emu.frameadvance() end -- into BATTLE gamestate, struct populated

  -- McDohl (actor 3, Soul Eater equipped) has only his Lv1 spell (Deadly Fingertips) story-
  -- unlocked in this specific battle - Lv2/Lv3 (Black Shadow/Hell) are still story-locked
  -- despite having nonzero MP, per user-confirmed ground truth for this savestate (the real
  -- flag storage isn't located yet - see lib/ActionEnumerator.lua's enumerateRune comment).
  -- Lv4 (Judgement) is already excluded on its own by MP4==0, no override needed for it.
  local lockedLevelsByActor = { [3] = { [2] = true, [3] = true } }
  local perActor, ctx = ActionEnumerator:enumerateRound(lockedLevelsByActor)
  if not perActor then
    log("ERROR: " .. tostring(ctx))
    return
  end

  for actorIdx = 1, ctx.PartyCount do
    local actions = perActor[actorIdx]
    if actions then
      local c = ctx.Combatants[actorIdx]
      log(string.format("=== actor%d %s (Id=%d, HP=%d/%d): %d legal actions ===",
        actorIdx, idToName[c.Id] or "???", c.Id, c.HPCurrent, c.HPMax, #actions))
      for _, a in ipairs(actions) do
        local actionType, slot, target = a[1], a[2], a[3]
        log(string.format("  %-6s slot=%-2d target=%d", ActionTypeNames[actionType], slot, target))
      end
    else
      log(string.format("=== actor%d: dead/absent, no actions ===", actorIdx))
    end
  end

  local total = ActionEnumerator.countRoundActions(perActor)
  log(string.format("\nFull round-1 search space (cartesian product across all living party members): %d combinations", total))

  -- Sample the first few combinations to prove combineRoundActions() actually works, without
  -- materializing the whole (potentially huge) space.
  log("First 3 combinations from combineRoundActions():")
  local count = 0
  for combo in ActionEnumerator.combineRoundActions(perActor) do
    count = count + 1
    local parts = {}
    for actorIdx, action in pairs(combo) do
      table.insert(parts, string.format("a%d:%s(%d->%d)", actorIdx,
        ActionTypeNames[action[1]], action[2], action[3]))
    end
    table.sort(parts)
    log("  " .. table.concat(parts, " "))
    if count >= 3 then break end
  end
end)

if not ok then
  log("ERROR: " .. tostring(err))
end

local f = io.open(OUT, "w")
f:write(table.concat(lines, "\n"))
f:close()

client.exit()
