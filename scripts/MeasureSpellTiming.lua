-- Generic live spell-duration measurement (plan approved by the user 2026-10-06).
-- Per CASES entry: load the savestate, set the caster to Rune / slot on the first enemy, run RUNS
-- seeds, and log only the marker frames (relative to T0) rather than the full per-frame dump:
--   battle+0x14 is a general handler pointer (never 0). A cast shows as the transition sequence
--   cast entry (T0) -> 0x80120660 (T0+1) -> setup (+15) -> tick machine (+16) -> end handler.
--   T0      the frame of the transition before 0x80120660 while the actor (battle+0x8) is the caster
--   machine end handler frame - tick machine frame (the spell's own length)
--   dmg     first frame >= T0 any combatant's HP changes
--   next    first frame after the machine that battle+0x8 is a different actor
--   rand    rand() calls in [T0, next)
-- The full handler trail ("h@+N", relative to T0) is logged so a wrong guess is visible. CASES'
-- first five entries are the regression set: the known live-measured spells (machine lengths 294,
-- 433, 493, 831, 681 - Battle_Damage_Formula.md "Cast timing").
--
-- USAGE: scripts/spawn-headless-emuhawk.sh \
--          /home/alex/Projects/Suikoden-Bizhawk-HUD/scripts/MeasureSpellTiming.lua "" 1800

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local BattleRoundInput = require "lib.BattleRoundInput"

local DIR = "/home/alex/Projects/Suikoden-Bizhawk-HUD/"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/MeasureSpellTiming.txt"
local RUNS = 3
local SOUL_EATER_ONLY = false
local SWEEP_ONLY = false
local UNITE_ONLY = true
local ALL = false
local PASSIVE_ONLY = false                             -- false = the Cleo regression set
local MAX_FRAMES = 3000
local NEXT_LAG = 3                                    -- next actor is picked 3 frames after the machine ends
local INTRO = 0x80120660                              -- cast intro state, one frame after the cast entry
local ZD = DIR .. "ZombieDragonStart.State"
-- caster = roster id; setRune/setMp (MP of levels 1-4) optional overrides, as CaptureCleoSpells.lua
local CASES = {
  { name = "Flaming Arrows", state = ZD, caster = 1, rune = 2, slot = 1, expect = 294 },
  { name = "Firestorm",      state = ZD, caster = 1, rune = 2, slot = 2, expect = 433 },
  { name = "Dancing Flames", state = ZD, caster = 1, rune = 2, slot = 3, expect = 493 },
  { name = "Explosion",      state = ZD, caster = 1, rune = 2, slot = 3, setRune = 27, setMp4 = 1, expect = 831 },
  { name = "Final Flame",    state = ZD, caster = 1, rune = 2, slot = 4, setRune = 27, setMp4 = 1, expect = 681 },
}
local CASES_REGRESSION = CASES
-- SpellDuration.State: round prompt, McDohl (roster id 8, formation slot 1) holding the Soul Eater rune
-- (id 1) with the story-locked levels unlocked, MP 8/6/5/1. setRune swaps his rune to test others.
local SD = DIR .. "SpellDuration.State"
local SOUL_EATER = {
  { name = "Soul Eater slot 1", state = SD, caster = 8, rune = 2, slot = 1 },
  { name = "Soul Eater slot 2", state = SD, caster = 8, rune = 2, slot = 2 },
  { name = "Soul Eater slot 3", state = SD, caster = 8, rune = 2, slot = 3 },
  { name = "Soul Eater slot 4", state = SD, caster = 8, rune = 2, slot = 4 },
}
-- Single-spell sweep (user request 2026-10-06): base runes slots 1-4 (Lv1-4; Fire's were already measured
-- via the Cleo regression), then each upgraded rune's slot 4 (its Lv5 spell; its slots 1-3 repeat the base
-- rune's Lv2-4). Rune ids: 3 Water, 4 Wind, 5 Lightning, 6 Earth, 7 Resurrection; 0x1c Flowing, 0x1d Cyclone,
-- 0x1e Mother Earth, 0x1f Thunder. All four MP pools are set to 9 so every level is castable.
local SWEEP = {}
for _, r in ipairs({ { 3, "Water" }, { 4, "Wind" }, { 5, "Lightning" }, { 6, "Earth" }, { 7, "Resurrection" } }) do
  for slot = 1, 4 do
    SWEEP[#SWEEP + 1] = { name = string.format("%s slot %d", r[2], slot), state = SD, caster = 8, rune = 2,
      slot = slot, setRune = r[1], setMpAll = 9 }
  end
end
for _, r in ipairs({ { 0x1c, "Flowing" }, { 0x1d, "Cyclone" }, { 0x1e, "Mother Earth" }, { 0x1f, "Thunder" } }) do
  SWEEP[#SWEEP + 1] = { name = string.format("%s slot 4", r[2]), state = SD, caster = 8, rune = 2, slot = 4,
    setRune = r[1], setMpAll = 9 }
end
-- Rune Unites (user request 2026-10-06): McDohl (id 8) and Luc (id 26) both queue Rune slot 4 (their Lv4) on
-- the enemy; everyone else Defends. Rune cycle Fire 2 > Lightning 5 > Water 3 > Wind 4 > Earth 6 > Fire; each
-- case shifts both runes one step forward. The faster caster triggers the combo and consumes the partner.
local UNITES = {}
do
  local cycle = { { 2, "Fire" }, { 5, "Lightning" }, { 3, "Water" }, { 4, "Wind" }, { 6, "Earth" } }
  local ids = { 36, 37, 38, 35, 34 }               -- Blazing Camp, Thor, Water Dragon, Storm Fang, Scorched Earth
  for n = 1, 5 do
    local a, b2 = cycle[n], cycle[n % 5 + 1]
    UNITES[#UNITES + 1] = { name = string.format("Unite %s+%s", a[2], b2[2]), state = SD, caster = 8, rune = 2,
      slot = 4, setRune = a[1], setMpAll = 9, partner = { caster = 26, setRune = b2[1] }, uniteId = ids[n],
      defendOthers = true }
  end
end
-- passive = savestate already sits just before the cast (no menu input; the first cast seen is measured)
local PASSIVE = {
  { name = "Hell (McDohlHell)",          state = DIR .. "McDohlHell.State", passive = true },
  { name = "Hell (McDohlHellGregminster)", state = DIR .. "McDohlHellGregminster.State", passive = true },
  { name = "Black Shadow (Wind)",        state = DIR .. "BlackShadowWind.State", passive = true },
  { name = "Black Shadow (Bats)",        state = DIR .. "BlackShadowBats.State", passive = true },
}
if PASSIVE_ONLY then CASES = PASSIVE end
if SOUL_EATER_ONLY then CASES = SOUL_EATER end
if SWEEP_ONLY then CASES = SWEEP end
if UNITE_ONLY then CASES = UNITES end
if ALL then CASES = {} for _, l in ipairs({ CASES_REGRESSION, SOUL_EATER, SWEEP }) do for _, c in ipairs(l) do CASES[#CASES + 1] = c end end end

local function lcg(x) return (x * 0x41c64e6d + 0x3039) % 0x100000000 end
local function steps(from, to)
  local x, n = from, 0
  while x ~= to and n < 20000 do x = lcg(x); n = n + 1 end
  return x == to and n or -1
end

local out = {}
local function log(s) out[#out + 1] = s end
local function base() return Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR)) end
local function rec(b, i) return b + 0xb40 + i * 0x54 end
local function ed(b, i) return b + 0x50 + i * 0x8c end

for _, case in ipairs(CASES) do
  local summary = {}
  for run = 1, RUNS do
    savestate.load(case.state)
    local b
    if case.passive then                                -- savestate already sits just before the cast
      for _ = 1, 4 do emu.frameadvance() end
      b = base()
    else
      for attempt = 1, 8 do
        b = BattleRoundInput:chooseRoundOption(BattleRoundInput.Choice.FREE_WILL)
        if b then break end
      end
    end
    if not b then
      log(string.format("%s run %d: round prompt never became ready", case.name, run))
    else
      if run > 1 then mainmemory.write_u32_le(Address.RNG, (0x1234567 * run + 0x89abcdef) % 0x100000000) end
      local party = mainmemory.read_u32_le(b + 0x1c)
      local total = mainmemory.read_u32_le(b + 0x24)
      local casterIdx
      for i = 1, case.passive and 0 or party do
        local rid = mainmemory.read_u8(ed(b, i))
        if case.partner and rid == case.partner.caster then
          -- Unite partner: own rune/MP, Rune slot 4, same enemy target (the combo's target is the first
          -- caster's, so both aim at an enemy whatever their own Lv4 spell would target)
          local c = mainmemory.read_u32_le(b + 0xf84 + i * 0xc)
          local st = Address.sanitize(mainmemory.read_u32_le(Address.sanitize(c) + 0x1c))
          mainmemory.write_u8(st + 0x4c, case.partner.setRune)
          for o = 9, 12 do mainmemory.write_u8(st + o, case.setMpAll or 9) end
          BattleRoundInput:setAction(i, case.rune, case.slot, party + 1)
        elseif case.defendOthers and rid ~= case.caster then
          BattleRoundInput:setAction(i, 1, 0, 0)
        elseif rid == case.caster then
          casterIdx = i
          local c = mainmemory.read_u32_le(b + 0xf84 + i * 0xc)
          local st = Address.sanitize(mainmemory.read_u32_le(Address.sanitize(c) + 0x1c))
          if case.setRune then mainmemory.write_u8(st + 0x4c, case.setRune) end
          if case.setMp4 then mainmemory.write_u8(st + 0xc, case.setMp4) end
          if case.setMpAll then for o = 9, 12 do mainmemory.write_u8(st + o, case.setMpAll) end end
          local runeId = mainmemory.read_u8(st + 0x4c)
          local set = Address.sanitize(mainmemory.read_u32_le(0x16a0e0 + runeId * 4))
          case.spellId = mainmemory.read_u8(set + 0x1a + case.slot)
          local def = Address.sanitize(mainmemory.read_u32_le(0x16d33c + case.spellId * 4))
          local tt = mainmemory.read_u16_le(def + 0x16) & 3      -- 2 = one ally, 3 = one enemy, else none
          local target = tt == 2 and i or (tt == 3 and party + 1 or 0)
          if case.partner then
            target = party + 1
            local udef = Address.sanitize(mainmemory.read_u32_le(0x16d33c + case.uniteId * 4))
            case.spellId, tt = case.uniteId, mainmemory.read_u16_le(udef + 0x16) & 3
          end
          case.targetType = tt
          BattleRoundInput:setAction(i, case.rune, case.slot, target)
        end
      end
      if case.partner then casterIdx = nil end
      if not casterIdx and not case.passive and not case.partner then
        log(string.format("%s run %d: caster %d not in party", case.name, run, case.caster))
      else
        if not case.passive then BattleRoundInput:confirmRound() end
        if case.partner then casterIdx = nil end
        local hp0 = {}
        for i = 1, total do hp0[i] = mainmemory.read_u16_le(rec(b, i) + 0x12) end
        local trans, dmgFrames, actorAt, randAt = {}, {}, {}, {}
        local lastH, lastRng, lastActor = nil, mainmemory.read_u32_le(Address.RNG), nil
        local doneAt
        for n = 1, MAX_FRAMES do
          emu.frameadvance()
          b = base()
          local actor, h = mainmemory.read_u32_le(b + 0x8), mainmemory.read_u32_le(b + 0x14)
          local rng = mainmemory.read_u32_le(Address.RNG)
          if rng ~= lastRng then randAt[n] = steps(lastRng, rng); lastRng = rng end
          if h ~= lastH then trans[#trans + 1] = { n = n, h = h, actor = actor }; lastH = h end
          if actor ~= lastActor then actorAt[#actorAt + 1] = { n = n, actor = actor }; lastActor = actor end
          for i = 1, total do
            local hp = mainmemory.read_u16_le(rec(b, i) + 0x12)
            if hp ~= hp0[i] then dmgFrames[#dmgFrames + 1] = n; hp0[i] = hp end
          end
          -- the cast: entry (T0) -> intro INTRO at T0+1 -> setup -> tick machine; it is over NEXT_LAG
          -- frames before battle+0x8 moves off the caster (a handler transition lands there for most
          -- spells, not Voice of Earth, and some spells have mid-machine handler hops, e.g. Charm Arrow)
          local k
          for j, t in ipairs(trans) do if t.h == INTRO and (not casterIdx or t.actor == casterIdx) then k = j; break end end
          if k and trans[k + 2] then
            for _, a2 in ipairs(actorAt) do
              if a2.n > trans[k].n and a2.actor ~= trans[k].actor then doneAt = doneAt or n; break end
            end
            if doneAt and n - doneAt > 12 then break end
          end
        end
        local k
        for j, t in ipairs(trans) do if t.h == INTRO and (not casterIdx or t.actor == casterIdx) then k = j; break end end
        local nextN
        if k then
          for _, a2 in ipairs(actorAt) do
            if a2.n > trans[k].n and a2.actor ~= trans[k].actor then nextN = a2.n; break end
          end
        end
        if not (k and trans[k + 2] and nextN) then
          local tl = {}
          for _, t in ipairs(trans) do tl[#tl + 1] = string.format("%08x@F%d(actor %d)", t.h, t.n, t.actor) end
          log(string.format("%s run %d: cast sequence not found; transitions: %s", case.name, run, table.concat(tl, " ")))
        else
          local t0 = trans[k].n - 1
          local mStart = trans[k + 2].n
          local mEnd = nextN - NEXT_LAG
          local hasHandler = false
          for _, t in ipairs(trans) do if t.n == mEnd then hasHandler = true end end
          local dmg, rands = nil, 0
          for _, f in ipairs(dmgFrames) do if f >= t0 and f <= nextN then dmg = f - t0; break end end
          for n, c in pairs(randAt) do
            if n >= t0 and n < nextN then rands = rands + c end
          end
          local seq = {}
          for j = k - 1, #trans do
            if trans[j].n >= t0 and trans[j].n <= nextN then
              seq[#seq + 1] = string.format("%08x@+%d", trans[j].h, trans[j].n - t0)
            end
          end
          log(string.format("%s (spell id %s, target type %s) run %d: actor=%d T0=F%d machine=%d (start +%d, end +%d%s) dmg=+%s next=+%d rand=%d  %s",
            case.name, tostring(case.spellId), tostring(case.targetType), run, trans[k].actor, t0, mEnd - mStart, mStart - t0,
            mEnd - t0, hasHandler and "" or " INFERRED, no handler change", tostring(dmg), nextN - t0, rands,
            table.concat(seq, " ")))
          summary[#summary + 1] = string.format("machine=%d dmg=+%s next=+%d", mEnd - mStart, tostring(dmg), nextN - t0)
        end
      end
    end
  end
  log(string.format("== %s (expect machine %s): %s", case.name, tostring(case.expect), table.concat(summary, " | ")))
end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(out, "\n") .. "\n"); file:close() end
client.exit()
