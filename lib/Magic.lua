local RNGLib = require "lib.RNG"
local CharmArrowGridHex = require "lib.CharmArrowGrid"

-- Validated against 21 real captured casts, 0 discrepancies - see
-- docs/game_mechanics/Battle_Damage_Formula.md's "How spells call RNG" section for the
-- full derivation. Exact simulation of
-- spell_earthquake_vfx_setup + spell_earthquake_tick_state_machine's RNG consumption:
--   - setup: exactly 100 rand() calls (fixed; the values themselves don't matter here)
--   - phase0: 64 ticks, no RNG
--   - phase1: 64 ticks, no RNG
--   - phase2: 128 ticks - particle i (i=0..19) activates at phase2-tick == i*2 (its
--     "stagger"), via FUN_80122eb4(particle,100,400): rand() sets its initial X position
--     (x = (rand()%198 + 1) - 100), a second rand() sets the other two axes (doesn't
--     affect X), then the particle is marked active.
--   - shared epilogue (every tick, all phases): each ACTIVE particle costs exactly 1
--     rand() (a jitter roll that doesn't affect its trajectory), then its X position
--     decreases by the fixed constant 27306/4096 per tick; it deactivates once its
--     position drops below -500.
--   - phase3: up to 64 more ticks, epilogue only (no new activations, damage application
--     itself has no RNG) - a hard cutoff regardless of any particles still active.
local EarthquakeConstants = {
  SETUP_CALLS = 100,
  PARTICLE_COUNT = 20,
  PHASE2_TICKS = 128,
  PHASE3_TICKS = 64,
  DECAY = -27306,   -- 0xffff9556 as signed 32-bit, in 1/4096ths per tick
  THRESHOLD = -500, -- real units; deactivates once position/4096 drops below this
}

-- simulateEarthquake(startSeed) -> totalRandCalls
-- startSeed is the RNG's raw 32-bit state (Address.RNG) the instant before the cast
-- begins resolving (i.e. the frame the game would make its first of the 100 setup calls).
local function simulateEarthquake(startSeed)
  local C = EarthquakeConstants
  local seed = startSeed
  local calls = 0

  local function rand()
    seed = RNGLib.nextRNG(seed)
    calls = calls + 1
    return RNGLib.getRNG2(seed)
  end

  for _ = 1, C.SETUP_CALLS do
    rand()
  end

  local particles = {}
  for i = 0, C.PARTICLE_COUNT - 1 do
    particles[i] = { stagger = i * 2, active = false, x = 0 }
  end

  local function runEpilogue()
    local anyActive = false
    for i = 0, C.PARTICLE_COUNT - 1 do
      local p = particles[i]
      if p.active then
        anyActive = true
        rand() -- jitter, doesn't affect trajectory
        p.x = p.x + C.DECAY
        -- floor division matches the game's arithmetic (sign-extending) right shift by
        -- 12 bits, unlike Lua's native ">>" which shifts logically/unsigned
        if math.floor(p.x / 4096) < C.THRESHOLD then
          p.active = false
        end
      end
    end
    return anyActive
  end

  -- phase 0: 64 ticks, no RNG, no particle activity
  -- phase 1: 64 ticks, no RNG, no particle activity
  -- phase 2: 128 ticks - staggered particle activation
  for t = 0, C.PHASE2_TICKS - 1 do
    for i = 0, C.PARTICLE_COUNT - 1 do
      local p = particles[i]
      if (not p.active) and p.stagger == t then
        local r1 = rand()
        local xInt = (r1 % 198 + 1) - 100 -- -99..98
        p.x = xInt * 4096
        rand() -- second axis, doesn't affect X
        p.active = true
      end
    end
    runEpilogue()
  end

  -- phase 3: up to 64 ticks, epilogue only, hard cutoff
  for _ = 1, C.PHASE3_TICKS do
    if not runEpilogue() then
      break
    end
  end

  return calls
end

-- Validated against a live capture matching all 64 real per-tick call counts exactly,
-- plus 20 more injected seeds - see docs/game_mechanics/Battle_Damage_Formula.md's
-- "Charm Arrow" section for the full derivation. Exact simulation of
-- spell_charmarrow_tick_state_machine's case-3 RNG
-- consumption - the only RNG-consuming phase of the cast (cases 0/1/2, 160 ticks combined,
-- have no RNG at all):
--   - 64 ticks total (case3's own counter starts at 64, decrements first thing each tick,
--     so ticks run with post-decrement values 63 downto 0 inclusive).
--   - each tick: repeatedly draw idx = rand() % 16384 and inspect grid[idx]:
--       - if 1 <= grid[idx] < 16: set it to 0 (a "success" - decays that cell)
--       - if grid[idx] >= 16: mask it to its low nibble (also a "success")
--       - if grid[idx] == 0 already: no-op, retry (a wasted draw)
--     repeat until exactly 160 successes land this tick.
--   - on the final tick (post-decrement counter == 0): damage applies
--     (apply_elemental_multiplier(4, 5, target, attacker, 500) - confirms Charm Arrow's
--     documented params exactly), no RNG in that step.
-- Since successes remove grid occupancy over time, later ticks need more retries (more
-- rand() calls) to find 160 still-nonzero cells - this is the exact mechanism behind the
-- steadily ramping per-tick call count observed live (286 calls on tick 1, climbing to
-- 608 by tick 64).
--
-- NOTE: a further handful of calls typically follow immediately after this phase in a
-- real capture. CONFIRMED 2026-09-05 these are NOT part of the spell at all: a fixed
-- 10-call block (battle_select_enemy_target cycling through a shrinking pool of eligible
-- combatants, one fewer per roll as each one - set to Defend, no RNG - resolves and drops
-- out) followed by a genuinely variable few calls from whichever action the final roll's
-- winner queues up next (which itself depends on the RNG stream, hence variable). Neither
-- is modeled here.
local CharmArrowConstants = {
  TOTAL_TICKS = 64,
  GRID_SIZE = 16384,
  SUCCESSES_PER_TICK = 0xa0, -- 160
}

local function hexToByteArray(hex)
  local bytes = {}
  for i = 1, #hex, 2 do
    bytes[(i + 1) / 2] = tonumber(hex:sub(i, i + 1), 16)
  end
  return bytes
end

-- simulateCharmArrow(startSeed) -> totalRandCalls
-- startSeed is the RNG's raw 32-bit state (Address.RNG) the instant before case 3's first
-- rand() call (i.e. the frame the game would make its first grid-decay draw).
local function simulateCharmArrow(startSeed)
  local C = CharmArrowConstants
  local seed = startSeed
  local calls = 0

  local function rand()
    seed = RNGLib.nextRNG(seed)
    calls = calls + 1
    return RNGLib.getRNG2(seed)
  end

  local grid = hexToByteArray(CharmArrowGridHex) -- 1-indexed, GRID_SIZE entries

  for _ = 1, C.TOTAL_TICKS do
    local successes = 0
    while successes ~= C.SUCCESSES_PER_TICK do
      local idx = rand() % C.GRID_SIZE
      local b = grid[idx + 1]
      if b < 0x10 then
        if b ~= 0 then
          grid[idx + 1] = 0
          successes = successes + 1
        end
        -- else: already empty, wasted draw, retry
      else
        grid[idx + 1] = b & 0xF
        successes = successes + 1
      end
    end
  end

  return calls
end

-- Validated against a live 95-tick per-tick capture matching exactly, plus 20 more
-- injected seeds matching exact totals - see docs/game_mechanics/Battle_Damage_Formula.md's
-- "Flaming Arrow" section for the full derivation. Exact simulation of
-- spell_flamingarrow_tick_state_machine's
-- phase-1 RNG consumption - the only RNG-consuming phase of the cast. 20 discrete "arrow"
-- particles, all starting inactive. Every tick for 96 ticks straight:
--   - any currently-inactive particle is respawned via spell_flamingarrow_spawn_particle
--     (4 rand() calls each).
--   - EXCEPT on the 96th (final) tick: the phase ends immediately after that tick's spawn
--     step, force-deactivating every particle regardless of position/lifetime - no decay
--     step runs on tick 96.
--   - on ticks 1-95: each active particle then despawns if EITHER its lifetime drops
--     below 1, OR its trail_x position (right-shifted 12 bits, discarding the fractional
--     low 12 bits) has magnitude < 5 - otherwise it decrements lifetime by 1 and advances
--     trail_x by its (randomized, per-particle) velocity. Both conditions are genuinely
--     exercised in live data (confirmed via a full particle-array dump at several
--     checkpoint ticks).
local FlamingArrowConstants = {
  PARTICLE_COUNT = 20,
  TOTAL_TICKS = 96, -- phase1's tick counter runs from 0; the phase ends once it (post-
                    -- increment) reaches 0x60 (96) - see spell_flamingarrow_tick_state_machine
  RADIUS = 100,
}

-- The low 12 bits of each particle's trail_x field (spell_flamingarrow_spawn_particle only
-- ever writes `field = field & 0xfff | (new_high_bits << 12)`, preserving whatever was
-- already in the low 12 bits) are stale leftover memory from whatever last used these 20
-- VFX particle-pool slots before this cast - NOT derived from the RNG stream at all.
-- Confirmed via a raw memory dump of FlamingArrow.State before any tick runs: slots 0-16
-- share a common zeroed template (residual 0), while slots 17-19 carry distinct nonzero
-- garbage. This is a fixed property of this savestate, like Charm Arrow's baked grid -
-- every seed tested against FlamingArrow.State needs this same table.
local FlamingArrowResidualLow12 = {
  [0]=0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 78, 2868, 99,
}

-- Raw bytes read directly from Ghidra at SquareRoot0's lookup table (0x8017242c), 192
-- int16 entries. SquareRoot0 is a standard PSX SDK library routine (GTE-hardware
-- leading-zero-count + table lookup), not part of the spell logic itself - reproduced
-- here bit-for-bit because spell_flamingarrow_spawn_particle calls it directly.
local Sqrt0TableHex = "00101f103f105e107e109c10bb10da10f8101611341152116f118c11a911c611e31100121c123812541270128c12a712c212de12f91214132e13491364137e139813b213cc13e6130014191432144c1465147e149714b014c814e114f91412152a1542155a1572158a15a215b915d115e815001617162e1645165c1673168916a016b716cd16e416fa16101726173c17521768177e179417aa17bf17d517ea17001815182a183f18541869187e189318a818bd18d118e618fa180f19231938194c196019741988199c19b019c419d819ec19001a131a271a3a1a4e1a611a751a881a9b1aae1ac21ad51ae81afb1a0e1b211b331b461b591b6c1b7e1b911ba31bb61bc81bdb1bed1b001c121c241c361c481c5a1c6c1c7e1c901ca21cb41cc61cd81ce91cfb1c0d1d1e1d301d411d531d641d761d871d981daa1dbb1dcc1ddd1dee1d001e111e221e331e431e541e651e761e871e981ea81eb91eca1eda1eeb1efb1e0c1f1c1f2d1f3d1f4e1f5e1f6e1f7e1f8f1f9f1faf1fbf1fcf1fdf1fef1f"

local function loadSqrt0Table()
  local bytes = hexToByteArray(Sqrt0TableHex)
  local table16 = {}
  for i = 0, (#Sqrt0TableHex / 4) - 1 do
    local lo, hi = bytes[i * 2 + 1], bytes[i * 2 + 2]
    local v = lo | (hi << 8)
    if v >= 0x8000 then v = v - 0x10000 end
    table16[i] = v
  end
  return table16
end

local Sqrt0Table = loadSqrt0Table()

local function clz32(a)
  a = a & 0xFFFFFFFF
  if a == 0 then return 32 end
  local n = 0
  local mask = 0x80000000
  while (a & mask) == 0 do
    n = n + 1
    mask = mask >> 1
  end
  return n
end

-- Exact port of the decompiled SquareRoot0 (PSX GTE-based fast integer sqrt).
local function squareRoot0(a)
  local clz = clz32(a)
  if clz == 0x20 then return 0 end
  local uVar1 = clz & 0xFFFFFFFE
  local shiftVal
  if (uVar1 - 0x18) < 0 then
    shiftVal = a >> ((0x18 - uVar1) & 0x1f)
  else
    shiftVal = (a << ((uVar1 - 0x18) & 0x1f)) & 0xFFFFFFFF
  end
  local idx = shiftVal - 0x40
  local tableVal = Sqrt0Table[idx]
  local shiftAmt = ((0x1f - uVar1) >> 1) & 0x1f
  local result = (tableVal << shiftAmt) & 0xFFFFFFFF
  -- arithmetic right shift by 12, treating result as signed 32-bit
  if result >= 0x80000000 then result = result - 0x100000000 end
  return result >> 12 -- result is now non-negative post sign-adjustment path used here
end

-- simulateFlamingArrow(startSeed) -> totalRandCalls
-- startSeed is the RNG's raw 32-bit state (Address.RNG) the instant before phase1's first
-- rand() call (i.e. the frame the game would make its first particle-spawn draw).
local function simulateFlamingArrow(startSeed)
  local C = FlamingArrowConstants
  local seed = startSeed
  local calls = 0

  local function rand()
    seed = RNGLib.nextRNG(seed)
    calls = calls + 1
    return RNGLib.getRNG2(seed)
  end

  -- Exact port of spell_flamingarrow_spawn_particle (0x80123b68). Picks a uniformly random
  -- point within a sphere of the given radius (X and Z axes matter for gameplay; Y is
  -- computed too but never read by the tick loop's despawn check, so it's skipped here -
  -- it costs no extra rand() calls either way), a random velocity SCALE factor (unlike
  -- Earthquake, where velocity is a fixed constant, Flaming Arrow's is randomized), and a
  -- random lifetime - 4 rand() calls total.
  local function spawn(residualLow12)
    local r1 = rand()
    local iVar3 = (C.RADIUS - 1) * 2
    local iVar5 = (r1 % iVar3 + 1) - C.RADIUS
    local lVar2 = squareRoot0(C.RADIUS * C.RADIUS - iVar5 * iVar5)
    rand() -- Z coordinate, not modeled (doesn't affect despawn timing)
    local r3 = rand()
    local iVar1 = (r3 % 64) + 128
    local velX = -iVar5 * iVar1
    -- C's `/` truncates toward zero for negative operands, unlike Lua's `//` which
    -- floors toward -infinity - replicate C's truncation exactly (see simulateEarthquake's
    -- analogous note on the mismatched shift/division semantics)
    local num, den = iVar5 * 5, 6
    local q = (num < 0) == (den < 0) and (math.abs(num) // math.abs(den)) or -(math.abs(num) // math.abs(den))
    local trailX = (residualLow12 & 0xfff) | (q * 4096)
    local r4 = rand()
    local lifetime = r4 % 100
    return { active = true, lifetime = lifetime, trailX = trailX, velX = velX }
  end

  local particles = {}
  for i = 0, C.PARTICLE_COUNT - 1 do
    particles[i] = { active = false, lifetime = 0, trailX = FlamingArrowResidualLow12[i], velX = 0 }
  end

  for tick = 1, C.TOTAL_TICKS do
    for i = 0, C.PARTICLE_COUNT - 1 do
      local p = particles[i]
      if not p.active then
        particles[i] = spawn(p.trailX & 0xfff)
      end
    end

    if tick == C.TOTAL_TICKS then
      break -- phase ends here: all particles force-deactivated, no decay step runs
    end

    for i = 0, C.PARTICLE_COUNT - 1 do
      local p = particles[i]
      if p.active then
        if p.lifetime < 1 then
          p.active = false
        else
          -- floor division matches the game's arithmetic (sign-extending) right shift by
          -- 12 bits, unlike Lua's native ">>" which shifts logically/unsigned (same fix
          -- as simulateEarthquake's decay check)
          local trailXInt = math.floor(p.trailX / 4096)
          if trailXInt < 0 then trailXInt = -trailXInt end
          if trailXInt < 5 then
            p.active = false
          else
            p.lifetime = p.lifetime - 1
            p.trailX = p.trailX + p.velX
          end
        end
      end
    end
  end

  return calls
end

return {
  simulateEarthquake = simulateEarthquake,
  simulateCharmArrow = simulateCharmArrow,
  simulateFlamingArrow = simulateFlamingArrow,
}
