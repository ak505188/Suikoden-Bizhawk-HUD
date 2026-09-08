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

-- Unlike Earthquake/Charm Arrow/Flaming Arrow, Dancing Flames' RNG consumption is a FIXED
-- constant, not seed-derived: spell_dancingflames_vfx_setup positions 15 ember particles (2
-- rand() calls each = 30, all in one setup frame), then
-- spell_dancingflames_tick_state_machine's case 4 reactivates all 15 in 4 more waves of 30
-- (via the shared vfx_activate_and_position_particle helper, also used by Earthquake) at a
-- fixed cadence (~55 ticks apart) regardless of what those rand() calls actually return -
-- the RNG stream only ever affects WHERE each ember spawns, never how many calls happen or
-- when phases transition. 5 waves x 30 = 150, confirmed via a live capture (see
-- docs/game_mechanics/Battle_Damage_Formula.md's "Dancing Flames" section). No per-tick
-- simulation needed since there's nothing seed-dependent to simulate.
local function simulateDancingFlames()
  return 150
end

-- Validated bit-for-bit against a live 159-tick per-tick capture on the original savestate
-- seed (0xd7250f7e -> 1302 total rand() calls, 0 mismatches). See
-- docs/game_mechanics/Battle_Damage_Formula.md's "Shining Wind" section for the full
-- derivation and Shining Wind's tick_state_machine plate comment for the mechanism.
-- Four particle pools, all sharing vfx_activate_and_position_particle for their actual
-- spawn-position roll (2 rand() calls), plus their own extra rolls:
--   Pool A (20 objects): schedule-match checked in the SHARED EPILOGUE, i.e. against
--     tick+1 (one tick after Pool B's own-body check) - and NOT gated on "already active",
--     so a decaying countdown (reset to 48 on every fire) can numerically re-cross the
--     ever-increasing tick counter later and spuriously re-trigger an already-active
--     object. This resonance is fully deterministic once modeled correctly, but is the
--     trickiest part of this spell's mechanic - see the tick_state_machine plate comment.
--   Pool B (20 objects): schedule-match checked in case 3's own body (before the tick
--     counter increments) - fires exactly once per object, no re-trigger mechanism.
--   Pool C (30 objects) and Pool D (20 objects): identical to each other - activate
--     whenever inactive (no schedule at all), 6 rand() calls each (height + 2 internal +
--     X velocity + Z velocity + a 0-179 "life" that's rolled but never decremented in
--     practice). Deactivates when life<1 (rare) or the accumulated Z position (checked
--     BEFORE that tick's own update, using the value already stored) crosses above 0.
local ShiningWindConstants = {
  SETUP_CALLS = 120,
  PHASE2_TICKS = 64,
  CASE3_TICKS = 160,
  POOL_A_COUNT = 20,
  POOL_B_COUNT = 20,
  POOL_C_COUNT = 30,
  POOL_D_COUNT = 20,
  POOL_A_RADIUS = 0x50,
  POOL_CD_RADIUS = 300,
}

-- simulateShiningWind(startSeed) -> totalRandCalls
-- startSeed is the RNG's raw 32-bit state the instant before setup's first rand() call.
local function simulateShiningWind(startSeed)
  local C = ShiningWindConstants
  local seed = startSeed
  local calls = 0

  local function rand()
    seed = RNGLib.nextRNG(seed)
    calls = calls + 1
    return RNGLib.getRNG2(seed)
  end

  -- Shared position roll (vfx_activate_and_position_particle): 2 rand() calls. Only the Z
  -- axis matters for Pool C/D's despawn check; Pool A/B never read position at all, so the
  -- exact X/Y/Z values are otherwise unused here - only the call count matters.
  local function activatePos(radius, height, residualLow12)
    local r1 = rand()
    local iVar3 = (radius - 1) * 2
    local iVar5 = (r1 % iVar3 + 1) - radius
    squareRoot0(radius * radius - iVar5 * iVar5)
    rand() -- second internal axis, unused
    return (residualLow12 & 0xfff) | (-height * 4096)
  end

  for _ = 1, C.SETUP_CALLS do
    rand()
  end

  local poolA = {}
  for i = 0, C.POOL_A_COUNT - 1 do
    poolA[i] = { active = false, sched = 2 * i }
  end
  local poolBFired = {}
  for i = 0, C.POOL_B_COUNT - 1 do
    poolBFired[i] = false
  end

  local function makePool(n)
    local pool = {}
    for i = 0, n - 1 do
      pool[i] = { active = false, posZ = 0, velZ = 0, life = 0 }
    end
    return pool
  end
  local poolC = makePool(C.POOL_C_COUNT)
  local poolD = makePool(C.POOL_D_COUNT)

  local function poolCDTick(pool, count, allowActivate)
    if allowActivate then
      for i = 0, count - 1 do
        local p = pool[i]
        if not p.active then
          p.active = true
          local h = rand() % 80 + 160
          local residual = p.posZ & 0xfff
          p.posZ = activatePos(C.POOL_CD_RADIUS, h, residual)
          rand() -- X velocity roll, unused (doesn't affect the Z-only despawn check)
          p.velZ = (rand() % 1024) + 0x1e00
          p.life = rand() % 0xb4
        end
      end
    end
    for i = 0, count - 1 do
      local p = pool[i]
      if p.active then
        -- check BEFORE updating, using the currently-stored position (matches the
        -- decompile's order exactly - not "update then check")
        if p.life < 1 or math.floor(p.posZ / 4096) > 0 then
          p.active = false
        else
          p.posZ = p.posZ + p.velZ
        end
      end
    end
  end

  for _ = 1, C.PHASE2_TICKS do
    poolCDTick(poolC, C.POOL_C_COUNT, true)
    poolCDTick(poolD, C.POOL_D_COUNT, true)
  end

  for tick = 0, C.CASE3_TICKS - 1 do
    -- On case3's OWN final tick, its exit code clears all 3 pool-enable flags (context
    -- +0x6a/+0x6b/+0x6d) BEFORE falling through to the shared epilogue - so no pool gets a
    -- chance to activate anything new that tick, even though the epilogue still runs (and
    -- Pool A/C/D's decay/process steps still apply to whatever was already active).
    local isLastTick = (tick == C.CASE3_TICKS - 1)

    for i = 0, C.POOL_B_COUNT - 1 do
      if (not poolBFired[i]) and tick == 2 * i then
        rand()
        activatePos(C.POOL_A_RADIUS, 0, 0)
        poolBFired[i] = true
      end
    end
    if not isLastTick then
      -- Pool A schedule-match: checked EVERY tick using the CURRENT sched value, regardless
      -- of active state (matches the decompile exactly - this is what allows the resonance
      -- re-trigger). Uses tick+1 since this check lives in the shared epilogue, after case
      -- 3's own body has already incremented the tick counter.
      for i = 0, C.POOL_A_COUNT - 1 do
        local p = poolA[i]
        if (tick + 1) == p.sched then
          rand()
          activatePos(C.POOL_A_RADIUS, 0, 0)
          p.active = true
          p.sched = 0x30
        end
      end
      -- Pool A fallback: inactive AND unscheduled (covers object 0's first fire, since
      -- tick+1==0 is never true, plus every subsequent natural reactivation).
      for i = 0, C.POOL_A_COUNT - 1 do
        local p = poolA[i]
        if (not p.active) and p.sched == 0 then
          rand()
          activatePos(C.POOL_A_RADIUS, 0, 0)
          p.active = true
          p.sched = 0x30
        end
      end
    end
    -- Pool A decay (no rand()): sched counts down from 48, deactivating at 0.
    for i = 0, C.POOL_A_COUNT - 1 do
      local p = poolA[i]
      if p.active then
        p.sched = p.sched - 1
        if p.sched < 1 then
          p.active = false
          p.sched = 0
        end
      end
    end
    poolCDTick(poolC, C.POOL_C_COUNT, not isLastTick)
    poolCDTick(poolD, C.POOL_D_COUNT, not isLastTick)
  end

  return calls
end

-- Storm Fang's entire RNG cost is a fixed constant: spell_stormfang_vfx_setup rolls a
-- random initial height for 38 particles (1 rand() call each, all in the single setup
-- frame), then hands off to a tick-resumable state machine that's entirely deterministic -
-- confirmed via a live capture spanning the spell's whole ~360-frame duration, the RNG
-- value never changes again after that one frame. The seed only ever affects where each
-- particle starts, never how many calls happen - see
-- docs/game_mechanics/Battle_Damage_Formula.md's "Storm Fang" section.
local function simulateStormFang()
  return 38
end

-- Validated bit-for-bit (exact final LCG-seed match) across 20 injected seeds on THREE
-- savestates - TedHell.State (a scripted fight), McDohlHell.State (a random encounter), and
-- McDohlHellGregminster.State (a third, independently-supplied encounter) - all three
-- produced byte-identical final RNG seeds for every seed tested, confirming the mechanism
-- has no camera-position or battle-context dependence (an initial hypothesis this ruled
-- out). See spell_hell_tick_state_machine's plate comment for the full mechanism and
-- docs/game_mechanics/Battle_Damage_Formula.md's "Hell" section for the derivation.
--
-- Hell (Soul Eater)'s case2 phase runs a FIXED 128 ticks regardless of seed. Each tick:
--   1. scaleAccum advances by a fixed 0x20000 (wrapping once its top bits exceed 0x1000) -
--      a deterministic animation-phase value, not RNG-derived.
--   2. any of the 40 particle slots with active==false gets respawned via
--      spell_hell_spawn_particle (4 rand() calls each).
--   3. EVERY slot (not gated on active - matches the decompile exactly) then either
--      deactivates (life<1, or |REF_X - posX>>12| < 5) or survives: posX advances by
--      velocity, life decrements, and - the key subtlety that blocked this for a long time -
--      the slot's "scale" field gets OVERWRITTEN with the CURRENT scaleAccum. A particle's
--      scale field only holds its original per-slot constant (SlotScaleTable below) up until
--      it first survives one tick; every later respawn (after deactivating and being picked
--      up again by step 2) spawns using whatever scaleAccum was frozen into it on its last
--      surviving tick, not the original constant.
local HellConstants = {
  TICKS = 128,
  SLOT_COUNT = 40,
  RADIUS = 180,
  REF_X = -178,       -- ctx+0x4; also reused as the spawn offset (both spawn AND despawn
                      -- reference the same fixed point)
  SCALE_INIT = 4096,
  SCALE_INCREMENT = 131072,
}

-- Fixed per-slot "scale" constants (offset 0x30 in each particle slot), 1-indexed to match
-- slot numbering. Confirmed byte-identical across TedHell.State, McDohlHell.State, and
-- McDohlHellGregminster.State - this is baked into the spell's own static data, not derived
-- from prior gameplay (unlike Flaming
-- Arrow's residual-low-12-bits, which IS per-savestate garbage). Interpreted as raw signed
-- 32-bit values >>12 in the spawn formula - most are far from a "1.0-ish" 4096, several look
-- like large/negative bit patterns, which is expected and intentional (not corruption).
local HellSlotScale = {
  4096, 2147483648, 4096, 2147516416, 5648, 2147516416, 69632,
  2147516416, 4276092913, 2147483648, 0, 2147516416, 0,
  2147516416, 2863311530, 4096, 0, 4096, 2147516416,
  4096, 2147516416, 4096, 2147516416, 1048576, 2147516416,
  27, 2684328959, 4096, 2684329983, 0, 4096, 0,
  2684329983, 2684289024, 0, 2684329983, 4096, 2684329983,
  0, 2684329983,
}

-- Stale low-12-bit residue in each slot's initial posX field (captured at frame0, before any
-- tick has run) - same "leftover memory from whatever last used these VFX pool slots" pattern
-- as Flaming Arrow's residual table, fixed per savestate. All 40 slots start inactive.
local HellInitialResidualLow12 = {
  0, 0, 544, 0, 0, 0, 0, 0, 510, 0, 272, 0,
  0, 0, 29, 0, 0, 0, 2458, 1536, 2457, 0,
  0, 0, 0, 0, 4095, 0, 4095, 0, 4000, 0,
  4095, 0, 4095, 0, 4095, 0, 0, 3071,
}

-- simulateHell(startSeed) -> totalRandCalls
-- startSeed is the RNG's raw 32-bit state the instant before case2's first rand() call
-- (i.e. the frame the game would make its first particle-spawn draw).
local function simulateHell(startSeed)
  local C = HellConstants
  local seed = startSeed
  local calls = 0

  local function rand()
    seed = RNGLib.nextRNG(seed)
    calls = calls + 1
    return RNGLib.getRNG2(seed)
  end

  -- C's `/` truncates toward zero; Lua's `//` floors toward -infinity - replicate C's
  -- truncation exactly (same fix as Flaming Arrow's velocity/position division).
  local function cDiv(num, den)
    local q = math.abs(num) // math.abs(den)
    if (num < 0) ~= (den < 0) then q = -q end
    return q
  end

  local function signed32(v)
    v = v & 0xFFFFFFFF
    if v >= 0x80000000 then v = v - 0x100000000 end
    return v
  end

  -- Exact port of spell_hell_spawn_particle. r2 (Z-axis roll) is consumed but never read by
  -- anything the despawn check needs, same as Flaming Arrow/Shining Wind's unused axis rolls.
  local function spawn(scale, residualLow12)
    local r1 = rand()
    local rangeN = (C.RADIUS - 1) * 2
    local xInt = (r1 % rangeN + 1) - C.RADIUS
    rand() -- Z-axis roll, unused
    local r3 = rand()
    local velScale = (r3 % 64) + 128
    local velX = -xInt * velScale
    -- arithmetic (floor) shift, not Lua's native logical ">>" - scale is frequently negative
    -- once reinterpreted as signed32 (see HellSlotScale's large entries)
    local scaleShifted = math.floor(signed32(scale) / 4096)
    local finalOff = cDiv(xInt * scaleShifted, 4096)
    local posX = (residualLow12 & 0xfff) | (signed32((finalOff + C.REF_X) * 4096) & 0xFFFFFFFF)
    local r4 = rand()
    local life = r4 % 120
    return { active = true, posX = signed32(posX), velX = velX, life = life, scale = scale }
  end

  local particles = {}
  for i = 1, C.SLOT_COUNT do
    particles[i] = {
      active = false,
      posX = HellInitialResidualLow12[i],
      velX = 0,
      life = 0,
      scale = HellSlotScale[i],
    }
  end

  local scaleAccum = C.SCALE_INIT
  for _ = 1, C.TICKS do
    scaleAccum = (scaleAccum + C.SCALE_INCREMENT) & 0xFFFFFFFF
    if (scaleAccum >> 12) > 0x1000 then
      scaleAccum = (scaleAccum & 0xfff) | 0x1000000
    end

    for i = 1, C.SLOT_COUNT do
      local p = particles[i]
      if not p.active then
        particles[i] = spawn(p.scale, p.posX & 0xfff)
      end
    end

    for i = 1, C.SLOT_COUNT do
      local p = particles[i]
      -- arithmetic (floor) shift, not Lua's native logical ">>" - posX is frequently negative
      if p.life < 1 or math.abs(C.REF_X - math.floor(p.posX / 4096)) < 5 then
        p.active = false
      else
        p.posX = signed32(p.posX + p.velX)
        p.scale = scaleAccum
        p.life = p.life - 1
      end
    end
  end

  return calls
end

-- Black Shadow (Soul Eater family) reuses Hell's exact particle-spawn formula
-- (spell_hell_spawn_particle, called directly - not a coincidence, confirmed via decompile)
-- inside spell_blackshadow_tick_state_machine's own case2, with different constants: 80
-- ticks (not 128), radius 200 (not 180), despawn/spawn reference point -128 (not -178), and
-- a scaleAccum that advances by a hardcoded 0x19999/tick (not a ctx-configurable 0x20000)
-- with no wraparound needed (80 ticks never reaches the threshold Hell's version wraps at).
-- See spell_blackshadow_tick_state_machine's plate comment for the full mechanism and
-- docs/game_mechanics/Battle_Damage_Formula.md's "Black Shadow" section for the derivation.
--
-- CRITICAL DIFFERENCE FROM HELL: the 40-slot "scale" table and each slot's initial posX
-- low-12-bit residue are NOT a fixed spell-wide constant here - they're genuine
-- PER-SAVESTATE stale VFX-pool memory (same category as Flaming Arrow's residual bits, not
-- Hell's baked table). Confirmed by comparing BlackShadowWind.State and BlackShadowBats.State
-- (two savestates on the same turn-2 cast, following two different Neclord turn-1 attacks):
-- their 40-slot scale tables are completely different patterns. This - not camera position,
-- which the user suspected going in - is what produces the user-observed "consistent ~5800
-- total after a Wind/Lightning attack vs ~9500 after a Bats attack": different turn-1 attacks
-- leave different leftover garbage in this shared particle-pool memory, and this spell's
-- spawn formula reads that garbage on every particle's first-ever spawn. This means, unlike
-- every other spell simulated in this file, Black Shadow's total rand() cost is NOT a pure
-- function of the starting seed alone - it also depends on this savestate-specific state,
-- which must be captured fresh for any new battle context (see simulateBlackShadowWind/Bats
-- below for the two currently-known captures).
local BlackShadowConstants = {
  TICKS = 80,
  SLOT_COUNT = 40,
  RADIUS = 200,
  REF_X = -128,
  SCALE_INCREMENT = 0x19999,
}

-- Captured from BlackShadowWind.State (Neclord used Wind turn 1) at frame 0, before any
-- tick - the 40-slot scale field (offset 0x30) and posX low-12-bit residue (offset 0x1c),
-- 1-indexed to match slot numbering. scaleAccum's own starting value in this savestate was
-- 8191 (vs. the more common 4096 seen in Bats/Hell) - also just whatever was left over.
local BlackShadowWindSlotScale = {
  2147516416, 8191, 2147516416, 0, 2147516416, 908748, 8191, 2147483648,
  8191, 2147516416, 4352, 2147516416, 1118208, 2147516416, 3418152703, 2147483648,
  0, 2147516416, 2952790016, 2147516416, 2576980377, 8191, 10, 0,
  2147516416, 113681, 2684329983, 8191, 2684328959, 0, 2684329983, 0,
  2684328959, 3439329280, 2684329983, 0, 2684328959, 0, 2684329983, 2684289024,
}
local BlackShadowWindSlotResidual = {
  0, 256, 0, 3566, 0, 0, 0, 0,
  3904, 0, 0, 0, 0, 0, 2986, 0,
  17, 0, 0, 0, 443, 0, 0, 0,
  2458, 0, 2457, 4095, 0, 0, 4095, 0,
  4095, 0, 4095, 3840, 0, 0, 4095, 0,
}
local BlackShadowWindScaleInit = 8191

-- Captured from BlackShadowBats.State (Neclord used Bats turn 1) the same way - notice this
-- table is mostly a uniform 4096 (i.e. "no scaling", spawning right at the reference point -
-- see spell_hell_spawn_particle's plate comment) with only a handful of large outliers,
-- compared to Wind's much more chaotic table - directly explaining why Bats' particles cycle
-- through roughly twice as fast (higher per-tick reactivation rate) as Wind's.
local BlackShadowBatsSlotScale = {
  4096, 4096, 4096, 4294791168, 4096, 4291624881, 1, 4096,
  4096, 4096, 4096, 504, 4096, 4096, 0, 2149064704,
  4096, 2148132048, 4096, 4290510762, 4096, 2149064704, 4096, 2149124192,
  4096, 4096, 4096, 4290314155, 4096, 4096, 4096, 2149124688,
  42, 0, 4096, 671617024, 0, 2149124856, 2149120640, 4096,
}
local BlackShadowBatsSlotResidual = {
  3329, 0, 3017, 127, 504, 3967, 3467, 0,
  4032, 0, 1232, 0, 3235, 4031, 0, 2300,
  1776, 1, 0, 155, 1810, 988, 0, 127,
  2144, 104, 1024, 6, 2304, 0, 824, 127,
  2448, 0, 1708, 8, 0, 0, 3928, 146,
}
local BlackShadowBatsScaleInit = 4096

-- simulateBlackShadow(startSeed, slotScale, slotResidual, scaleInit) -> totalRandCalls
-- startSeed is the RNG's raw 32-bit state the instant before case2's first rand() call.
-- slotScale/slotResidual are the 40-entry per-savestate tables above; scaleInit is that
-- savestate's own starting scaleAccum value. Use simulateBlackShadowWind/Bats below unless
-- simulating a new, not-yet-captured battle context.
local function simulateBlackShadow(startSeed, slotScale, slotResidual, scaleInit)
  local C = BlackShadowConstants
  local seed = startSeed
  local calls = 0

  local function rand()
    seed = RNGLib.nextRNG(seed)
    calls = calls + 1
    return RNGLib.getRNG2(seed)
  end

  local function cDiv(num, den)
    local q = math.abs(num) // math.abs(den)
    if (num < 0) ~= (den < 0) then q = -q end
    return q
  end

  local function signed32(v)
    v = v & 0xFFFFFFFF
    if v >= 0x80000000 then v = v - 0x100000000 end
    return v
  end

  -- Exact port of spell_hell_spawn_particle, identical to simulateHell's copy - see its
  -- comment there for the per-roll breakdown.
  local function spawn(scale, residualLow12)
    local r1 = rand()
    local rangeN = (C.RADIUS - 1) * 2
    local xInt = (r1 % rangeN + 1) - C.RADIUS
    rand() -- Z-axis roll, unused
    local r3 = rand()
    local velScale = (r3 % 64) + 128
    local velX = -xInt * velScale
    local scaleShifted = math.floor(signed32(scale) / 4096)
    local finalOff = cDiv(xInt * scaleShifted, 4096)
    local posX = (residualLow12 & 0xfff) | (signed32((finalOff + C.REF_X) * 4096) & 0xFFFFFFFF)
    local r4 = rand()
    local life = r4 % 120
    return { active = true, posX = signed32(posX), velX = velX, life = life, scale = scale }
  end

  local particles = {}
  for i = 1, C.SLOT_COUNT do
    particles[i] = {
      active = false,
      posX = slotResidual[i],
      velX = 0,
      life = 0,
      scale = slotScale[i],
    }
  end

  local scaleAccum = scaleInit
  for _ = 1, C.TICKS do
    scaleAccum = (scaleAccum + C.SCALE_INCREMENT) & 0xFFFFFFFF

    for i = 1, C.SLOT_COUNT do
      local p = particles[i]
      if not p.active then
        particles[i] = spawn(p.scale, p.posX & 0xfff)
      end
    end

    for i = 1, C.SLOT_COUNT do
      local p = particles[i]
      if p.life < 1 or math.abs(C.REF_X - math.floor(p.posX / 4096)) < 5 then
        p.active = false
      else
        p.posX = signed32(p.posX + p.velX)
        p.scale = scaleAccum
        p.life = p.life - 1
      end
    end
  end

  return calls
end

local function simulateBlackShadowWind(startSeed)
  return simulateBlackShadow(startSeed, BlackShadowWindSlotScale, BlackShadowWindSlotResidual,
    BlackShadowWindScaleInit)
end

local function simulateBlackShadowBats(startSeed)
  return simulateBlackShadow(startSeed, BlackShadowBatsSlotScale, BlackShadowBatsSlotResidual,
    BlackShadowBatsScaleInit)
end

return {
  simulateEarthquake = simulateEarthquake,
  simulateCharmArrow = simulateCharmArrow,
  simulateFlamingArrow = simulateFlamingArrow,
  simulateDancingFlames = simulateDancingFlames,
  simulateStormFang = simulateStormFang,
  simulateShiningWind = simulateShiningWind,
  simulateHell = simulateHell,
  simulateBlackShadow = simulateBlackShadow,
  simulateBlackShadowWind = simulateBlackShadowWind,
  simulateBlackShadowBats = simulateBlackShadowBats,
}
