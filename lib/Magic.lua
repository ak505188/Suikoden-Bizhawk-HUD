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
        local xRoll = rand() -- r1
        local xInt = (xRoll % 198 + 1) - 100 -- -99..98
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

-- The Shredding (spell 14), Healing Wind (15), Storm (16) and Voice of Earth (22) cost no rand() at all
-- (verified by the user 2026-10-07, not decompiled here).
local function simulateTheShredding()
  return 0
end

local function simulateHealingWind()
  return 0
end

local function simulateStorm()
  return 0
end

local function simulateVoiceOfEarth()
  return 0
end

-- Scolding (spell 5, Resurrection Lv1, one enemy): zero rand() calls (spell_scolding_*, static decompile
-- 2026-10-06, not live-tested). Setup, the four phases (64+64+32+96 ticks), apply_elemental_multiplier
-- (the double vs undead is deterministic), the hit-reaction script and the end handler all have none.
local function simulateScolding()
  return 0
end

-- Resurrection-rune sparkle pass shared by Yell and Scream (the two tick machines run the same epilogue).
-- Each sparkle has a start tick in particle+0x24. The tick counter is already incremented when the pass runs,
-- so a phase-3 pass of N ticks sees 1..N-1 (the last tick clears the flag first) and start 0 never matches. A match costs
-- 3 rand() (a height roll + vfx_activate_and_position_particle's 2) and sets the field to 0x30; FUN_8012080c then
-- counts it down by 1 on every tick the sparkle is active (inactive below 1), so it re-fires whenever the
-- field again equals the counter: 48-(L-t) = L, i.e. at (48+t)/2 when that is a whole tick.
local function simulateResurrectionSparkles(startTicks, passes)
  local REFIRE_VALUE = 0x30
  local start, active, calls = {}, {}, 0
  for i, tick in ipairs(startTicks) do start[i] = tick end
  for label = 1, passes do
    for i = 1, #start do
      if start[i] == label then
        calls = calls + 3
        start[i], active[i] = REFIRE_VALUE, true
      end
    end
    for i = 1, #start do
      if active[i] then
        start[i] = start[i] - 1
        if start[i] < 1 then active[i] = false end
      end
    end
  end
  return calls
end

-- Yell (spell 6, Resurrection Lv2, one ally): a fixed 33 rand() calls (spell_yell_*, static decompile
-- 2026-10-06, live-validated: 20 seeds, aimed at a live ally). Phase 3 (64 ticks) runs the sparkle pass over 5
-- sparkles with start ticks 0,10,20,30,40: fires 10,20,30,40 -> 29,34,39,44 -> 41,46 -> 47 = 11 activations.
-- Setup, the revive (HPMax/3), the hit script and the end handler have none.
local function simulateYell()
  return simulateResurrectionSparkles({ 0, 10, 20, 30, 40 }, 63)
end

-- Scream (spell 7, Resurrection Lv3, whole party): a fixed 162 rand() calls (spell_scream_*, static decompile
-- 2026-10-06, live-validated: 20 seeds plus the first seed's per-tick counts). Same sparkle pass as Yell, over 20
-- sparkles with start ticks 0,2..38 and phase 3's 60 ticks (counter 1..59): 54 activations x 3. The +300 heal
-- (phase 5), the hit script and the end handler have none.
local function simulateScream()
  local starts = {}
  for i = 0, 19 do starts[i + 1] = i * 2 end
  return simulateResurrectionSparkles(starts, 59)
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
-- already in the low 12 bits) LOOK like stale leftover VFX-pool memory, but are NOT -
-- confirmed fixed, spell-wide constant data (same category as Hell's HellSlotScale, not
-- Black Shadow's genuine per-savestate residue). DAT_8017a030 (Flaming Arrow's own context
-- pointer) IS a genuinely dynamic heap_alloc/heap_free arena, same lifecycle as the Soul
-- Eater family - NOT a permanently-static buffer (spell_flamingarrow_cleanup explicitly
-- heap_free's all 20 particle structs plus the context every cast) - and it's SHARED with
-- Explosion, Dancing Flames, and a newly-found spell "Firestorm" (spell_explosion_vfx_setup
-- and spell_dancingflames_vfx_setup both heap_alloc into this same slot). Despite that
-- genuine reuse, ctx always resolves to the same address (0x191090; particle structs
-- 0x18f5b0-0x18ff30) and these low-12 bits are byte-identical across 4 real savestates:
-- FlamingArrow.State (fresh battle), FlamingArrow2ndCast.State (repeat Flaming Arrow cast -
-- doesn't disturb its own untouched field), FlamingArrowAfterDeadlyFingertips.State (a
-- different attack, but on a DIFFERENT arena - SOUL_EATER_CTX/DAT_8017a060 - so not actually
-- a same-arena test), and FlamingArrowAfterFirestorm.State (the actually decisive test -
-- Firestorm shares this exact arena, and still: identical). Consistent with a simple
-- stack/arena allocator that returns to the same state once the prior occupant fully frees
-- before the next cast. Keeping the "residual" name/shape for continuity even though it's
-- not residue.
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
  local clzEven = clz & 0xFFFFFFFE -- uVar1
  local shiftVal
  if (clzEven - 0x18) < 0 then
    shiftVal = a >> ((0x18 - clzEven) & 0x1f)
  else
    shiftVal = (a << ((clzEven - 0x18) & 0x1f)) & 0xFFFFFFFF
  end
  local idx = shiftVal - 0x40
  local tableVal = Sqrt0Table[idx]
  local shiftAmt = ((0x1f - clzEven) >> 1) & 0x1f
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
    local xRoll = rand() -- r1
    local xRange = (C.RADIUS - 1) * 2 -- iVar3
    local xOffset = (xRoll % xRange + 1) - C.RADIUS -- iVar5
    local yzRadius = squareRoot0(C.RADIUS * C.RADIUS - xOffset * xOffset) -- lVar2
    rand() -- Z coordinate, not modeled (doesn't affect despawn timing)
    local velRoll = rand() -- r3
    local velScale = (velRoll % 64) + 128 -- iVar1
    local velX = -xOffset * velScale
    -- C's `/` truncates toward zero for negative operands, unlike Lua's `//` which
    -- floors toward -infinity - replicate C's truncation exactly (see simulateEarthquake's
    -- analogous note on the mismatched shift/division semantics)
    local num, den = xOffset * 5, 6
    local q = (num < 0) == (den < 0) and (math.abs(num) // math.abs(den)) or -(math.abs(num) // math.abs(den))
    local trailX = (residualLow12 & 0xfff) | (q * 4096)
    local lifetimeRoll = rand() -- r4
    local lifetime = lifetimeRoll % 100
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

local function simulateFirestorm()
  return 0
end

-- Explosion shares DAT_8017a030 with Flaming Arrow/Dancing Flames/Firestorm (see
-- FlamingArrowResidualLow12's comment above) and its own Pool C (case2) calls
-- spell_flamingarrow_spawn_particle directly - the same shared spawn helper as Flaming
-- Arrow. CONFIRMED via extensive live tracing (2026-09-21) across two independently-seeded
-- captures on Explosion.State:
--   setup (spell_explosion_vfx_setup): exactly 70 rand() calls, in an order that matters -
--   Pool A/B's schedules are DERIVED from these same calls, not a captured table:
--     - 20 iterations (Pool B), 2 calls each: first call % 0x48 (72) becomes that object's
--       case3 firing tick; second call is a position roll, consumed but not counted.
--     - 30 iterations (Pool C), 0 calls (FUN_80123a5c takes fixed args).
--     - 15 iterations (Pool A), 2 calls each: first call % 0x60 (96) becomes that object's
--       case3 firing tick; second call likewise consumed but unused for counting.
--   phase 0: 64 ticks, no RNG. phase 1: 32 ticks, no RNG.
--   phase 2 (case2): 128 ticks - Pool C (30 Flaming-Arrow-style particles, radius 150 not
--     100, via spell_flamingarrow_spawn_particle directly - 4 rand() calls/spawn). CONFIRMED
--     LIVE (exact per-tick match, not just total): the spawn gate is OFF only on tick-index 0
--     (0 calls that tick, despite all 30 particles starting inactive) and ON for every
--     remaining tick 1-127 INCLUDING the last one (tick 127 still shows real spawn activity
--     live) - the decompile's own "piVar1[0x53]=0 clears the gate on the transitioning tick"
--     reading does not match observed behavior, and the true cause of the tick-0-only gap
--     was not chased further once the per-tick match was achieved. Decay/despawn runs
--     unconditionally on all 128 ticks (moot on tick 0 either way, since nothing has spawned
--     yet to decay).
--   phase 3 (case3): 96 ticks - a flat 1 rand()/tick camera-shake roll, PLUS Pool A/Pool B
--     each firing at their setup-assigned schedule tick, PLUS a confirmed RE-FIRE: each
--     particle's nested sprite-animation state (*(particle+0x18), driven by the generic,
--     non-spell-specific FUN_800e2a9c/FUN_800e2044/FUN_801238e0 subsystem) finishes its
--     animation cycle a FIXED number of ticks after activation, clears the particle's own
--     "flag" (+0x1c) for exactly one tick, and - since "schedule" is already 0 from the first
--     fire - the idle-refill branch in the decompile (loop2 for Pool A, loop4 for Pool B)
--     immediately re-fires it, if that re-fire tick still falls within the 96-tick window.
--     CONFIRMED EXACT via live tracing (2026-09-21) across two independently-seeded captures,
--     zero mismatches on every single tick: Pool A's cycle is exactly 55 ticks; Pool B's is
--     exactly 60 (both fixed animation-length constants, independent of each object's own
--     schedule value). Pool A's fresh fire costs 2 calls (vfx_activate_and_position_particle
--     only); its re-fire costs 3 (vfx_activate's 2 plus one extra fractional-write roll, per
--     the decompile's loop2 body). Pool B's fresh fire and re-fire both cost 3 (one
--     sound-variant roll + vfx_activate_and_position_particle) - loop3 and loop4 are
--     identical in cost. Neither pool can re-fire a SECOND time within the 96-tick window
--     (max schedule + 2*cycle always exceeds 95 for both pools), so "fire, then at most one
--     re-fire" is exhaustive here.
--
-- Full totals (verified via direct LCG-step count from seed to the settled post-cast RNG
-- value, not just case3 in isolation, AND via an exact tick-by-tick match against live
-- per-tick RNG deltas - not just matching totals): native seed 0x1b65fc6a gives 1220 live,
-- case3 contributing exactly 234 (70 setup + 916 phase2 + 234 phase3 = 1220); fresh seed
-- 0x11111111 gives 1271 live, case3 contributing exactly 249 (70 + 952 + 249 = 1271). Both
-- fully reconciled - this model no longer has an unresolved residual. The earlier "residual"
-- was purely a measurement artifact: this session's live captures sampled memory once per
-- tick, always on the same frame parity, which structurally cannot observe a clear-then-
-- re-fire cycle that completes within a single tick's 2-frame window (Pool B's 60-tick cycle
-- does; Pool A's 55-tick cycle happens to straddle a tick boundary and so WAS directly
-- observable via per-tick sampling, which is why Pool A's re-fire was found first and Pool
-- B's was initially - wrongly - believed not to exist at all).
local ExplosionConstants = {
  SETUP_CALLS = 70, -- 20*2 (Pool B) + 30*0 (Pool C) + 15*2 (Pool A) = 70
  PHASE0_TICKS = 64,
  PHASE1_TICKS = 32,
  PHASE2_TICKS = 128,
  PHASE3_TICKS = 96,
  POOL_A_COUNT = 15,
  POOL_B_COUNT = 20,
  POOL_C_COUNT = 30,
  POOL_C_RADIUS = 150,
  POOL_A_SCHEDULE_MOD = 0x60, -- 96
  POOL_B_SCHEDULE_MOD = 0x48, -- 72
  POOL_A_REFIRE_CYCLE = 55, -- fixed animation-length constant, confirmed exact live
  POOL_B_REFIRE_CYCLE = 60, -- fixed animation-length constant, confirmed exact live
}

-- Pool C's (30 Flaming-Arrow-style particles) initial trail_x low-12-bit residual, captured
-- live right after spell_explosion_vfx_setup runs (frame 0 of Explosion.State is BEFORE
-- vfx_setup actually runs - cast_entry is a one-tick trampoline, same pattern as every other
-- spell here - so the residual was captured 1 tick in, right after vfx_setup's 70 calls).
-- All 30 particles start genuinely inactive (confirmed live), so lifetime/velX/trailX's high
-- bits are irrelevant - only these low 12 bits survive into each particle's first spawn.
local ExplosionPoolCResidualLow12 = {
  [0]=0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  3945,3994,527,8,128,527,8,2,527,10,102,
}

-- simulateExplosion(startSeed) -> totalRandCalls
-- startSeed is the RNG's raw 32-bit state the instant before spell_explosion_vfx_setup's
-- first rand() call (i.e. the frame the game would make its first setup draw). See this
-- function's header comment above for the confirmed exact model (including Pool A/B re-fire).
local function simulateExplosion(startSeed)
  local C = ExplosionConstants
  local seed = startSeed
  local calls = 0

  local function rand()
    seed = RNGLib.nextRNG(seed)
    calls = calls + 1
    return RNGLib.getRNG2(seed)
  end

  -- setup: Pool B (20x2), Pool C (30x0), Pool A (15x2) - exact order matters, since Pool
  -- A/B's schedules are derived from these same calls, not a captured table.
  local poolBSchedule = {}
  for i = 0, C.POOL_B_COUNT - 1 do
    local scheduleRoll = rand()
    rand() -- position roll, unused for counting
    poolBSchedule[i] = scheduleRoll % C.POOL_B_SCHEDULE_MOD
  end
  for _ = 1, C.POOL_C_COUNT do
    -- FUN_80123a5c(0x7f,0x7f,0,0,0) - fixed args, no rand()
  end
  local poolASchedule = {}
  for i = 0, C.POOL_A_COUNT - 1 do
    local scheduleRoll = rand()
    rand() -- position roll, unused for counting
    poolASchedule[i] = scheduleRoll % C.POOL_A_SCHEDULE_MOD
  end

  -- phase 0/1: 64 + 32 ticks, no RNG.

  -- phase 2 (case2): Pool C - exact port of spell_flamingarrow_spawn_particle, radius 150.
  local function spawnPoolC(residualLow12)
    local xRoll = rand()
    local xRange = (C.POOL_C_RADIUS - 1) * 2
    local xOffset = (xRoll % xRange + 1) - C.POOL_C_RADIUS
    squareRoot0(C.POOL_C_RADIUS * C.POOL_C_RADIUS - xOffset * xOffset)
    rand() -- Z coordinate, not modeled (doesn't affect despawn timing)
    local velRoll = rand()
    local velScale = (velRoll % 64) + 128
    local velX = -xOffset * velScale
    local num, den = xOffset * 5, 6
    local q = (num < 0) == (den < 0) and (math.abs(num) // math.abs(den)) or -(math.abs(num) // math.abs(den))
    local trailX = (residualLow12 & 0xfff) | (q * 4096)
    local lifetimeRoll = rand()
    local lifetime = lifetimeRoll % 100
    return { active = true, lifetime = lifetime, trailX = trailX, velX = velX }
  end

  local poolC = {}
  for i = 0, C.POOL_C_COUNT - 1 do
    poolC[i] = { active = false, lifetime = 0, trailX = ExplosionPoolCResidualLow12[i], velX = 0 }
  end

  for tickIdx = 0, C.PHASE2_TICKS - 1 do
    -- Spawn gate: OFF only on tick-index 0 (confirmed live - see this function's header
    -- comment), ON for every tick 1..127 including the last.
    if tickIdx >= 1 then
      for i = 0, C.POOL_C_COUNT - 1 do
        local p = poolC[i]
        if not p.active then
          poolC[i] = spawnPoolC(p.trailX & 0xfff)
        end
      end
    end
    -- Decay/despawn: unconditional every tick, all 128.
    for i = 0, C.POOL_C_COUNT - 1 do
      local p = poolC[i]
      if p.active then
        if p.lifetime < 1 then
          p.active = false
        else
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

  -- phase 3 (case3): camera shake (1/tick) + Pool A/B firing at their setup-assigned
  -- schedule tick, plus a re-fire at a fixed cycle length later (see this function's header
  -- comment for the confirmed exact mechanism and cycle lengths).
  local poolARefireTick = {}
  for i = 0, C.POOL_A_COUNT - 1 do
    local rt = poolASchedule[i] + C.POOL_A_REFIRE_CYCLE
    poolARefireTick[i] = rt <= C.PHASE3_TICKS - 1 and rt or nil
  end
  local poolBRefireTick = {}
  for i = 0, C.POOL_B_COUNT - 1 do
    local rt = poolBSchedule[i] + C.POOL_B_REFIRE_CYCLE
    poolBRefireTick[i] = rt <= C.PHASE3_TICKS - 1 and rt or nil
  end

  for tick = 0, C.PHASE3_TICKS - 1 do
    for i = 0, C.POOL_A_COUNT - 1 do
      if poolASchedule[i] == tick then
        rand() -- vfx_activate_and_position_particle: X roll
        rand() -- vfx_activate_and_position_particle: second-axis roll
      end
      if poolARefireTick[i] == tick then
        rand() -- vfx_activate_and_position_particle: X roll
        rand() -- vfx_activate_and_position_particle: second-axis roll
        rand() -- extra fractional-write roll (loop2 body)
      end
    end
    for i = 0, C.POOL_B_COUNT - 1 do
      if poolBSchedule[i] == tick then
        rand() -- sound-variant roll
        rand() -- vfx_activate_and_position_particle: X roll
        rand() -- vfx_activate_and_position_particle: second-axis roll
      end
      if poolBRefireTick[i] == tick then
        rand() -- sound-variant roll
        rand() -- vfx_activate_and_position_particle: X roll
        rand() -- vfx_activate_and_position_particle: second-axis roll
      end
    end
    rand() -- camera shake, unconditional every tick
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

-- simulateFinalFlame(startSeed) -> totalRandCalls
-- startSeed is the RNG's raw 32-bit state (Address.RNG) the instant before
-- spell_finalflame_vfx_setup (0x80101eb0) runs, i.e. the frame battle+0x14 holds the setup
-- pointer. Validated tick-by-tick against 30 live captures (Cleo, Rage Rune, vs Zombie
-- Dragon; 0 mismatches) - see docs/game_mechanics/Battle_Damage_Formula.md's "Final Flame"
-- section. Structure (all from the decompile):
--   setup: 30 rand() (pool B scale) + 30 (pool C scale) + 30 x 2 (pool D: start tick
--     rand()%64 + 20, then scale) = 120, in one frame.
--   tick machine (spell_finalflame_tick_state_machine, 0x80102280), own tick counter:
--     case 0 (64 ticks): no rand().
--     case 1 (128 ticks): pool A's 20 particles fire at ticks 0,3,...,57: rand()%40 plus
--       vfx_activate_and_position_particle's 2 = 3 each (60, fixed).
--     case 2 (296 ticks): pool B's first 29 particles fire at ticks floor(200k/30) (2 each,
--       58), its 30th is activated by hand at tick 180 (2); pool D's 30 particles fire first
--       at their start tick, then again every time their non-looping sprite (shared sheet
--       DAT_800aa004, seq 13: 11 frames x 5 = 55 updates) finishes - re-activation is checked
--       in the case body, the sprite update/deactivation in the epilogue, so one particle
--       fires every 55 ticks until case 2 ends (2 each). This is the only seed-dependent
--       part: the count depends only on the 30 start ticks.
--     case 3 (96 ticks): no rand(); damage at its end (apply_elemental_multiplier(5, Fire,
--       target, caster, 900), no RNG).
-- Real frames: case 2's ticks 201..295 each take 2 frames (the spell machine alone; the
-- animation pass keeps running every frame), so the cast hands the turn back at T0+697.
local FinalFlameDLife = 55

local function simulateFinalFlame(startSeed)
  local seed = startSeed
  local calls = 0
  local function rand()
    seed = RNGLib.nextRNG(seed)
    calls = calls + 1
    return RNGLib.getRNG2(seed)
  end

  for _ = 1, 30 do rand() end                  -- pool B scale
  for _ = 1, 30 do rand() end                  -- pool C scale
  local dStart = {}
  for k = 1, 30 do
    dStart[k] = rand() % 64 + 20               -- pool D start tick
    rand()                                     -- pool D scale
  end

  calls = calls + 20 * 3                       -- case 1: pool A, fixed
  calls = calls + 29 * 2 + 2                   -- case 2: pool B (29 scheduled + the 30th at 180)

  -- case 2, pool D: first fire at its start tick, then every FinalFlameDLife ticks through
  -- tick 295 (the rand() values drawn here don't change the count, so only count them)
  for k = 1, 30 do
    local fires = math.floor((295 - dStart[k]) / FinalFlameDLife) + 1
    calls = calls + fires * 2
  end

  return calls
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
    local xRoll = rand() -- r1
    local xRange = (radius - 1) * 2 -- iVar3
    local xOffset = (xRoll % xRange + 1) - radius -- iVar5
    squareRoot0(radius * radius - xOffset * xOffset)
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

-- Blazing Camp (spell 36, Fire+Lightning Magic Unite, all enemies): a fixed 54 rand() calls, independent of seed and
-- enemy count (spell_blazingcamp_*, static decompile 2026-10-06; live-validated the same day: 20 seeds plus the
-- first seed's per-tick counts, scripts/CaptureBlazingCampSeeds.lua, McDohl Fire + Luc Lightning Lv4 on
-- SpellDuration.State). Setup, the hit scripts, calc_dual_element_spell_damage and the end handler have none.
--   phase 2 (150 ticks): 10 meteors, meteor k activates at tick 72+6k, 2 rand() each = 20. Each starts at z=-300
--     and moves +25/tick (starting the tick it activates); when z>>12 passes -10 (the 12th move) it costs one more
--     rand() (the impact flash's life, rand()%32 + 0x30) = 10. The last impact is at tick 137, inside the phase.
--   phase 3 (64 ticks): 12 sparkles, sparkle k activates at tick 3k, 2 rand() each = 24 (never re-armed)
local function simulateBlazingCamp()
  local METEORS, METEOR_FIRST, METEOR_STEP, PHASE2_TICKS = 10, 72, 6, 150
  local MOVES_TO_IMPACT, SPARKLES = 12, 12
  local calls = 0
  for k = 0, METEORS - 1 do
    calls = calls + 2
    if METEOR_FIRST + METEOR_STEP * k + MOVES_TO_IMPACT - 1 < PHASE2_TICKS then calls = calls + 1 end
  end
  return calls + SPARKLES * 2
end

-- Deadly Fingertips (spell 25, Dark Lv1, one enemy): seed-dependent, 1075-1170 rand() calls
-- (spell_deadlyfingertips_*, static decompile 2026-10-07; live-validated the same day: 20 seeds plus the first
-- seed's per-tick counts, scripts/CaptureDeadlyFingertipsSeeds.lua, McDohl's own Soul Eater Rune slot 1).
-- The whole cost is the same 30-particle spark pool as the Dragon's Lightning (Dragon.simulateLightning):
-- vfx_spawn_random_arc_particle respawns any inactive line particle for 5 rand() (the 4th is its z velocity
-- -(r % 5 + 5), the 5th its life r % 0x46); a spark goes inactive when its life or z>>12 < -300 runs out. Here the
-- spawn gate is open on 209 passes: phase 2's 80 (the gate opens on its first tick), phase 3's 60, phase 4's 10
-- and the first 59 of phase 5 (its last tick closes the gate before the pass). Decay runs on every pass but
-- nothing spawns after the gate closes. Setup, the instant-death check (apply_elemental_multiplier, whose only
-- callee is printf), the hit script and the cleanup have no RNG. The machine is 64+32+80+60+10+60+60 = 366
-- ticks, 576 frames live.
local function simulateDeadlyFingertips(startSeed)
  local SPARKS, GATED_PASSES = 30, 80 + 60 + 10 + 59
  local TOTAL_PASSES = GATED_PASSES + 1 + 60
  local seed = startSeed
  local calls = 0
  local function rand()
    seed = RNGLib.nextRNG(seed)
    calls = calls + 1
    return RNGLib.getRNG2(seed)
  end

  local active, life, posZ, velZ = {}, {}, {}, {}
  for i = 1, SPARKS do active[i], life[i], posZ[i], velZ[i] = false, 0, 0, 0 end
  for pass = 1, TOTAL_PASSES do
    if pass <= GATED_PASSES then
      for i = 1, SPARKS do
        if not active[i] then
          rand(); rand(); rand()
          local velRoll = rand()
          life[i] = rand() % 0x46
          velZ[i] = -((velRoll % 5) + 5) * 4096
          posZ[i] = posZ[i] & 0xfff
          active[i] = true
        end
      end
    end
    for i = 1, SPARKS do
      if life[i] < 1 or posZ[i] // 4096 < -300 then active[i] = false end
      if active[i] then
        life[i] = life[i] - 1
        posZ[i] = posZ[i] + velZ[i]
      end
    end
  end
  return calls
end

-- Water Dragon (spell 38, Wind+Water Magic Unite, all enemies): seed-dependent, ~3000 rand() calls
-- (spell_waterdragon_*, static decompile 2026-10-07; live-validated the same day: 20 seeds plus the first seed's
-- per-tick counts, scripts/CaptureWaterDragonSeeds.lua, McDohl Water + Luc Wind on SpellDuration.State).
-- Phases 64+64+128+64+64 = 384 ticks. Everything below is rolled in this order inside one tick (the shared
-- epilogue runs on every phase; only phase 2 has a body):
--   setup: 302 = 30 x 3 + 20 x 2 + 80 x 2 + 12 x 1.
--   phase-2 body: 12 bolts, bolt k activates at tick 48+5k (2 rand()); their impacts roll nothing.
--   epilogue, per pool, in order (a pool respawns any particle that is inactive while its gate is open):
--     P1, 30 particles, gate = epilogue passes 64..318: 4 rand() (height, 2 in vfx_activate_and_position_particle,
--       then life = rand() % 180). Life counts down once per active pass and the particle goes inactive when it
--       reads < 1, so the period is life + 1.
--     P2, 20 particles, gate = 128..318: 5 rand() (height % 200, 2 in the helper, z velocity %0x400 + 0x1e00, life
--       % 180). The life never counts down; the particle ends when z>>12 > 0 (it starts at -height, moves by its
--       velocity each pass, carrying the low 12 bits of z from one life to the next), or at once if life < 1.
--     P3, 80 particles, gate = 64..318: 4 rand() as P1 with life % 96.
--   The gates close on phase 3's last pass (318), so phase 4 rolls nothing.
local function simulateWaterDragon(startSeed)
  local P1, P2, P3, BOLTS = 30, 20, 80, 12
  local PASSES, GATE1_FIRST, GATE2_FIRST, GATE_LAST = 384, 64, 128, 318
  local PHASE2_FIRST, BOLT_FIRST_TICK, BOLT_STEP = 128, 48, 5
  local seed = startSeed
  local calls = 0
  local function rand()
    seed = RNGLib.nextRNG(seed)
    calls = calls + 1
    return RNGLib.getRNG2(seed)
  end

  for _ = 1, 30 * 3 + 20 * 2 + 80 * 2 + 12 do rand() end
  local a1, l1, a3, l3 = {}, {}, {}, {}
  for i = 1, P1 do a1[i], l1[i] = false, 0 end
  for i = 1, P3 do a3[i], l3[i] = false, 0 end
  local a2, l2, z2, v2 = {}, {}, {}, {}
  for i = 1, P2 do a2[i], l2[i], z2[i], v2[i] = false, 0, 0, 0 end

  for pass = 0, PASSES - 1 do
    local bodyTick = pass - PHASE2_FIRST
    if bodyTick >= 0 and bodyTick < 128 and bodyTick >= BOLT_FIRST_TICK
      and (bodyTick - BOLT_FIRST_TICK) % BOLT_STEP == 0 and (bodyTick - BOLT_FIRST_TICK) // BOLT_STEP < BOLTS then
      rand(); rand()
    end
    local gate1 = pass >= GATE1_FIRST and pass <= GATE_LAST
    local gate2 = pass >= GATE2_FIRST and pass <= GATE_LAST
    if gate1 then
      for i = 1, P1 do
        if not a1[i] then rand(); rand(); rand(); l1[i] = rand() % 180; a1[i] = true end
      end
    end
    for i = 1, P1 do
      if l1[i] < 1 then a1[i] = false elseif a1[i] then l1[i] = l1[i] - 1 end
    end
    if gate2 then
      for i = 1, P2 do
        if not a2[i] then
          local height = rand() % 200
          rand(); rand()
          v2[i] = rand() % 0x400 + 0x1e00
          l2[i] = rand() % 180
          a2[i] = true
          z2[i] = (z2[i] & 0xfff) + (-height * 4096)
        end
      end
    end
    for i = 1, P2 do
      if l2[i] < 1 or z2[i] // 4096 > 0 then a2[i] = false else z2[i] = z2[i] + v2[i] end
    end
    if gate1 then
      for i = 1, P3 do
        if not a3[i] then rand(); rand(); rand(); l3[i] = rand() % 96; a3[i] = true end
      end
    end
    for i = 1, P3 do
      if l3[i] < 1 then a3[i] = false elseif a3[i] then l3[i] = l3[i] - 1 end
    end
  end
  return calls
end

-- Scorched Earth (spell 34, Fire+Earth Magic Unite, all enemies): a fixed 282 rand() calls, independent of seed and
-- enemy count (spell_scorchedearth_*, static decompile 2026-10-07; live-validated the same day: 20 seeds plus the
-- first seed's per-tick counts, scripts/CaptureScorchedEarthSeeds.lua, McDohl Earth + Luc Fire on
-- SpellDuration.State). Every roll sits inside vfx_activate_and_position_particle (2 rand), so only WHEN a particle
-- activates matters, never the rolled values. Setup 48 (4 loops x 12 rolls), then 292 shared-epilogue passes
-- (phase 1: 64, phase 2: 64, phase 3: 164; the tick label is already incremented, and reset to 0 on each phase's
-- last pass); phase 4 (waits for the meteors) onwards rolls nothing. The 55-tick sprite animation (sequence 0xd,
-- non-looping) is each A/F particle's life:
--   F (12 sparkles, start ticks 0,3..33; gate on in phases 1-3): when inactive, label == start fires and the
--     very next check (+0x24 == -1, no active test) fires again, so a first fire costs 4; then it re-activates
--     for 2 each time it is inactive again, every 55 passes = 12*4 + 53*2 = 154.
--   A (12 particles, start ticks 8k, phase-3 body only): fires when its countdown field equals the raw tick, then
--     the field is set to 30 and counts down once per active pass, so some re-fire at (30+t)/2: 16 activations = 32.
--   E (8 particles, start ticks 12k, phase-3 body): fires at its tick, then re-fires each time its expanding ring
--     (47 passes) is gone again: 24 activations = 48.
local function simulateScorchedEarth()
  local ANIM_TICKS, RING_TICKS, A_REARM = 55, 47, 30
  local PHASE1, PHASE2, PHASE3 = 64, 64, 164
  local calls = 48
  local F, A, E = {}, {}, {}
  for i = 0, 11 do
    F[i + 1] = { start = 3 * i, active = false, left = 0 }
    A[i + 1] = { counter = 8 * i, active = false, left = 0 }
  end
  for k = 0, 7 do E[k + 1] = { counter = 12 * k, ring = false, ringLeft = 0 } end

  for pass = 0, PHASE1 + PHASE2 + PHASE3 - 1 do
    local label
    if pass < PHASE1 + PHASE2 then
      local i = pass % 64
      label = i < 63 and i + 1 or 0
    else
      label = pass - (PHASE1 + PHASE2) + 1
    end
    if pass >= PHASE1 + PHASE2 then
      local tick = pass - (PHASE1 + PHASE2)
      for _, a in ipairs(A) do
        if a.counter == tick then
          calls = calls + 2
          a.counter = A_REARM
          if not a.active then a.active, a.left = true, ANIM_TICKS end
        end
      end
      for _, e in ipairs(E) do
        if e.counter == tick then
          calls = calls + 2
          e.ring, e.ringLeft, e.counter = true, RING_TICKS, 0
        end
      end
      for _, e in ipairs(E) do
        if e.counter == 0 and not e.ring then
          calls = calls + 2
          e.ring, e.ringLeft = true, RING_TICKS
        end
      end
    end
    for _, a in ipairs(A) do
      if a.active then
        a.counter, a.left = a.counter - 1, a.left - 1
        if a.left <= 0 then a.active = false end
      end
    end
    for _, f in ipairs(F) do
      if not f.active then
        if f.start == label then
          calls = calls + 2
          f.start, f.active, f.left = -1, true, ANIM_TICKS
        end
        if f.start == -1 then
          calls = calls + 2
          f.active, f.left = true, ANIM_TICKS
        end
      end
      if f.active then
        f.left = f.left - 1
        if f.left <= 0 then f.active = false end
      end
    end
    for _, e in ipairs(E) do
      if e.ring then
        e.ringLeft = e.ringLeft - 1
        if e.ringLeft <= 0 then e.ring = false end
      end
    end
  end
  return calls
end

-- Thor (spell 37, Lightning+Water Magic Unite, one enemy): seed-dependent (spell_thor_*, static decompile
-- 2026-10-07). Every rand() consumer, in the order a tick runs them (phases 64+48+128+80+64 ticks; only phase 2's
-- 128 ticks have a body, the other phases just run the shared epilogue):
--   setup (6): one roll per spark particle's scale.
--   phase-2 body, tick t = 0..127:
--     bolts: 4 bolt particles A[i]; while A[i] and its impact flash B[i] are both inactive it re-activates for 2
--       rand(). It starts at z=-300, moves +25/tick (from its own tick) and impacts on the 13th move (z>0):
--       1 rand() (the flash life, which never matters: the paired 48-tick flash C always ends B first), and B/C
--       stay up until 47 ticks later. So all 4 activate at t=0, 60, 120 and impact at 12, 72, 132 (phase 3).
--     trails: 6 arrays of 10 particles; array j's lead is armed at t = 32+3j. While the lead and the tail (10th)
--       are inactive and the lead's counter is 0 it activates for 2 rand(): t=a, a+25, a+50, a+75 (a+100 is past
--       the phase). A lead lives 16 ticks (the counter runs 0..16), then costs 3 rand() (its spark particle), and
--       the tail flag trails the lead by 9 ticks.
--     lightning arcs: from t=48, each of 20 line particles that is inactive respawns via
--       spell_flamingarrow_spawn_particle(p, 0x78) = 4 rand() (the same helper as Flaming Arrow).
--   epilogue (every tick of all 5 phases): arcs decay (lifetime < 1, or |trail_x>>12| < 5 -> inactive, else
--     lifetime-1 and trail_x += velocity), then bolt moves/impacts, then trail leads.
-- Live-validated (scripts/CaptureThorSeeds.lua, McDohl Lightning + Luc Water on SpellDuration.State, 20 seeds
-- plus the first seed's per-tick counts). The arcs' trail_x low 12 bits were read live: all 0.
local function simulateThor(startSeed)
  local SPARKS, BOLTS, ARRAYS, ARCS = 6, 4, 6, 20
  local PHASE2_TICKS, TOTAL_TICKS = 128, 128 + 80 + 64
  local ARC_RADIUS, ARC_FIRST_TICK = 0x78, 48
  local BOLT_IMPACT_MOVE, BOLT_START_Z, BOLT_SPEED = 13, -300, 25
  local FLASH_TICKS, TRAIL_FIRST, TRAIL_STEP, TRAIL_LEAD_TICKS, TRAIL_LEN = 48, 32, 3, 16, 10
  local seed = startSeed
  local calls = 0
  local function rand()
    seed = RNGLib.nextRNG(seed)
    calls = calls + 1
    return RNGLib.getRNG2(seed)
  end

  for _ = 1, SPARKS do rand() end

  local bolt, flashLeft = {}, {}
  for i = 1, BOLTS do bolt[i], flashLeft[i] = { active = false, z = 0 }, 0 end
  local lead, armed, flags = {}, {}, {}
  for j = 1, ARRAYS do
    lead[j], armed[j], flags[j] = { active = false, counter = 1 }, false, {}
    for k = 1, TRAIL_LEN do flags[j][k] = false end
  end
  local arcs = {}
  for i = 1, ARCS do arcs[i] = { active = false, lifetime = 0, trailX = 0, velX = 0 } end

  local function spawnArc(residualLow12)
    local xRoll = rand()
    local xOffset = (xRoll % ((ARC_RADIUS - 1) * 2) + 1) - ARC_RADIUS
    rand()
    local velScale = (rand() % 64) + 128
    local num, den = xOffset * 5, 6
    local q = (num < 0) == (den < 0) and (math.abs(num) // math.abs(den)) or -(math.abs(num) // math.abs(den))
    local lifetime = rand() % 100
    return { active = true, lifetime = lifetime, trailX = (residualLow12 & 0xfff) | (q * 4096),
      velX = -xOffset * velScale }
  end

  for tick = 0, TOTAL_TICKS - 1 do
    if tick < PHASE2_TICKS then
      for i = 1, BOLTS do
        if not bolt[i].active and flashLeft[i] == 0 then
          rand(); rand()
          bolt[i].active, bolt[i].z, bolt[i].moves = true, BOLT_START_Z, 0
        end
      end
      for j = 1, ARRAYS do
        if tick == TRAIL_FIRST + TRAIL_STEP * (j - 1) then lead[j].counter, armed[j] = 0, true end
      end
      for j = 1, ARRAYS do
        if armed[j] and not lead[j].active and not flags[j][TRAIL_LEN] and lead[j].counter == 0 then
          rand(); rand()
          lead[j].active = true
          for k = 1, TRAIL_LEN do flags[j][k] = true end
        end
      end
      if tick >= ARC_FIRST_TICK then
        for i = 1, ARCS do
          if not arcs[i].active then arcs[i] = spawnArc(arcs[i].trailX) end
        end
      end
    end

    for i = 1, ARCS do
      local a = arcs[i]
      if a.active then
        if a.lifetime < 1 then
          a.active = false
        else
          local trailXInt = math.floor(a.trailX / 4096)
          if trailXInt < 0 then trailXInt = -trailXInt end
          if trailXInt < 5 then
            a.active = false
          else
            a.lifetime = a.lifetime - 1
            a.trailX = a.trailX + a.velX
          end
        end
      end
    end
    for i = 1, BOLTS do
      local b = bolt[i]
      if b.active then
        b.moves = b.moves + 1
        if b.moves >= BOLT_IMPACT_MOVE then
          rand()
          b.active, flashLeft[i] = false, FLASH_TICKS
        end
      end
      if flashLeft[i] > 0 and not (b.active and b.moves == 0) then
        flashLeft[i] = flashLeft[i] - 1
      end
    end
    for j = 1, ARRAYS do
      local l = lead[j]
      if l.active then
        if l.counter < TRAIL_LEAD_TICKS then
          l.counter = l.counter + 1
        else
          l.active, l.counter = false, 0
          rand(); rand(); rand()
        end
      end
      flags[j][1] = l.active
      for k = TRAIL_LEN, 2, -1 do flags[j][k] = flags[j][k - 1] end
    end
  end
  return calls
end

-- Angry Blow (spell 17, Lightning Lv1): a fixed 6 rand() calls for any realistic target, all
-- inside the 64-tick phase 3 of spell_angryblow_tick_state_machine. Two "bolt" particles activate
-- at phase-3 ticks 0 and 12, 2 rand() each via vfx_activate_and_position_particle (4 total). Each
-- bolt starts at z=-300 and moves +25/tick in the shared epilogue; when z>>12 passes the target's
-- nRefPosZ>>12 it costs one more rand() (impact-flash life) and deactivates (2 total). Phase 3's
-- exit clears the bolts before that tick's epilogue, so bolt k (spawn tick s) gets 63-s moves.
-- targetZ (nRefPosZ>>12, default 0) only matters for a target so far "down" the z axis that a bolt
-- never arrives. Live-validated 2026-10-06 (scripts/CaptureAngryBlowDepth.lua, SpellDuration.State,
-- native z=0): z forced to 0/500/900 -> 6, 1000 -> 5, 1500 -> 4. Cutoffs for z in 901..999 are
-- from the static decompile, not measured. Machine length is 304 frames regardless of z.
local function simulateAngryBlow(targetZ)
  targetZ = targetZ or 0
  local calls = 0
  for _, spawnTick in ipairs({ 0, 12 }) do
    calls = calls + 2
    if -300 + 25 * (63 - spawnTick) > targetZ then calls = calls + 1 end
  end
  return calls
end

-- Raging Blow (spell 19, Lightning Lv3) and Ball of Lightning (spell 20, Lightning Lv4) cost
-- no rand() at all (verified by the user).
local function simulateRagingBlow()
  return 0
end

local function simulateBallOfLightning()
  return 0
end

-- Clay Guardian (spell 21, Earth Lv1, one ally; spell_clayguardian_*, static decompile 2026-10-06).
-- Setup and phases 0-2 (64+32+80 ticks) have no RNG; the buff itself (stat x3/2 on the target) and the
-- three hit-reaction scripts (0x8016f234) have none either. All of it is phase 3's sparkle loop, which
-- runs in the epilogue on each of that phase's 96 ticks (and stops once phase 4 clears its flag):
--   spawn pass, particles 0..9 in order: an inactive particle costs 3 rand() -
--     vfx_activate_and_position_particle(p, 30, 0) = 2, then life = rand() % 60 (the 3rd)
--   age pass, particles 0..9: life < 1 -> inactive, else life-1 (a particle moves at most 59
--     times, so the z cutoff at -200 never fires)
-- A sparkle with life L is active for L ticks and can respawn the tick after it expires, so the total
-- depends on the seed's life rolls (L = 0 respawns on the very next tick).
local function simulateClayGuardian(startSeed)
  local PARTICLES, TICKS, LIFE_RANGE = 10, 96, 60
  local seed = startSeed
  local calls = 0
  local function rand()
    seed = RNGLib.nextRNG(seed)
    calls = calls + 1
    return RNGLib.getRNG2(seed)
  end

  local active, life = {}, {}
  for i = 1, PARTICLES do active[i], life[i] = false, 0 end
  for _ = 1, TICKS do
    for i = 1, PARTICLES do
      if not active[i] then
        rand(); rand()
        life[i] = rand() % LIFE_RANGE
        active[i] = true
      end
    end
    for i = 1, PARTICLES do
      if life[i] < 1 then
        active[i] = false
      else
        life[i] = life[i] - 1
      end
    end
  end
  return calls
end

-- Copper Flesh (spell 23, Earth Lv3, one ally): zero rand() calls (spell_copperflesh_*, static
-- decompile 2026-10-06; you confirmed 0 too). The spell's whole effect is apply_status_effect(target, 8) on
-- phase 4's first tick, and nothing in setup, the 7 phases or that call rolls.
local function simulateCopperFlesh()
  return 0
end

-- Guardian of Earth (spell 33, Earth Lv5, whole party; spell_guardianofearth_*, static decompile
-- 2026-10-06). Seed-dependent. Phases 0-2 (64+32+64 ticks) have no RNG, and neither do the buff (stat
-- x3/2 on every living party member), the hit-reaction script (0x8016f234) or the end handler.
--   setup: 40 sparkle particles, each rolls its start tick = rand() % 48 (40 rand())
--   epilogue sparkle pass, on every tick of phase 3 (128) and the first 32 of phase 4 (the flag clears
--   when phase 4's tick counter reads 32). The counter is already incremented when the pass runs, so
--   a start tick s >= 1 fires on phase-3 tick s-1, and s = 0 fires on phase 3's last tick (the counter
--   was just reset to 0). Each activation is vfx_activate_and_position_particle(p, 0x78, 0) = 2 rand().
--   An inactive particle that already fired re-activates the next pass (radius 0x5a, also 2 rand()).
--   The sparkle sprite loops (vfx_create_particle param_4 = 1), so only the z cutoff ends a life: z
--   starts at the low 12 bits left over, falls 0x9600 per tick, and dies on the pass that finds
--   z>>12 < -300, which is 33 moves later. A particle therefore re-activates every 34 passes.
local function simulateGuardianOfEarth(startSeed)
  local PARTICLES, START_RANGE, PASSES, PHASE3_TICKS = 40, 0x30, 160, 128
  local Z_VELOCITY, Z_CUTOFF = -0x9600, -300
  local seed = startSeed
  local calls = 0
  local function rand()
    seed = RNGLib.nextRNG(seed)
    calls = calls + 1
    return RNGLib.getRNG2(seed)
  end

  local start, active, z = {}, {}, {}
  for i = 1, PARTICLES do
    start[i], active[i], z[i] = rand() % START_RANGE, false, 0
  end
  local function activate(i)
    rand(); rand()
    active[i] = true
    z[i] = z[i] & 0xfff
  end
  for pass = 0, PASSES - 1 do
    local label = pass < PHASE3_TICKS - 1 and pass + 1 or (pass == PHASE3_TICKS - 1 and 0 or pass - PHASE3_TICKS + 1)
    for i = 1, PARTICLES do
      if start[i] == label then
        start[i] = -1
        activate(i)
      end
    end
    for i = 1, PARTICLES do
      if start[i] == -1 and not active[i] then activate(i) end
    end
    for i = 1, PARTICLES do
      if active[i] then
        if z[i] // 4096 < Z_CUTOFF then active[i] = false end
        z[i] = z[i] + Z_VELOCITY
      end
    end
  end
  return calls
end

-- Thunder God (spell 32, Lightning Lv5): a fixed 472 rand() calls, independent of seed and of
-- the enemy count (spell_thundergod_*, static decompile 2026-10-06). Live-validated the same day
-- (scripts/CaptureThunderGod.lua, SpellDuration.State, McDohl with the Thunder Rune, 4 seeds): 96 in
-- the setup frame, 2 at each bolt tick, 72 at each of the 5 phase-4 activations; machine 484 frames.
--   setup: 24 flicker particles x 4 rand() = 96, all in the setup frame
--   phase 3 (180 ticks): 8 bolts, bolt k activates at tick 10k, 2 rand() each = 16 (impact has
--     no rand and nothing respawns)
--   phase 4 (64 ticks): each inactive flicker particle re-activates, but only while tick < 48,
--     at 3 rand() apiece (1 for the height + 2 inside vfx_activate_and_position_particle).
--     They deactivate when their non-looping sprite animation ends: sequences 6 and 0xb of the
--     shared effect sheet are both 5 frames x 2 ticks = 10 updates, so a particle is active for
--     ticks t..t+9 and re-activates at t+10: ticks 0, 10, 20, 30, 40 = 5 times each.
local function simulateThunderGod()
  local FLICKER, ANIM_TICKS, ACTIVATE_WHILE_TICK_BELOW = 24, 10, 48
  local calls = FLICKER * 4                        -- setup
  for tick = 0, 70, 10 do calls = calls + 2 end    -- phase 3 bolts at ticks 0, 10 .. 70
  local activeUntil = -1                           -- every flicker particle behaves identically
  for tick = 0, 63 do
    if tick < ACTIVATE_WHILE_TICK_BELOW and tick > activeUntil then
      calls = calls + FLICKER * 3
      activeUntil = tick + ANIM_TICKS - 1
    end
  end
  return calls
end

-- Rainstorm (spell 18, Lightning Lv2): 26 + 2 * livingEnemies rand() calls, seed-independent
-- (spell_rainstorm_tick_state_machine, static decompile 2026-10-06; the enemy dependence is
-- confirmed live by the user). Phase 2 (96 ticks) has 12 bolts: bolt k activates at tick 5k
-- (2 rand() via vfx_activate_and_position_particle), moves +25 z/tick from -300 and impacts the
-- fixed target z=0 on its 13th move (no rand at impact), which lights its flash for 0x38 ticks.
-- A second loop re-activates any bolt that is inactive with an inactive flash and a schedule
-- of 0 - only bolt 0 - so bolt 0 respawns once, at tick 68. Phase 4 then spends 2 rand() per
-- living enemy (the per-enemy hit particle). Damage has no RNG.
local function simulateRainstorm(livingEnemies)
  local BOLTS, SCHEDULE_STEP, PHASE_TICKS = 12, 5, 96
  local MOVES_TO_IMPACT, FLASH_TICKS = 13, 0x38
  local calls = 0
  local active, moves, flash = {}, {}, {}
  for k = 0, BOLTS - 1 do active[k], moves[k], flash[k] = false, 0, 0 end

  for tick = 0, PHASE_TICKS - 1 do
    for k = 0, BOLTS - 1 do                        -- loop 1: scheduled activation
      if k * SCHEDULE_STEP == tick then
        active[k], moves[k] = true, 0
        calls = calls + 2
      end
    end
    for k = 0, BOLTS - 1 do                        -- loop 2: respawn (schedule 0 only)
      if not active[k] and flash[k] == 0 and k * SCHEDULE_STEP == 0 then
        active[k], moves[k] = true, 0
        calls = calls + 2
      end
    end
    for k = 0, BOLTS - 1 do                        -- epilogue: bolts, then flashes
      if active[k] then
        moves[k] = moves[k] + 1
        if moves[k] >= MOVES_TO_IMPACT then active[k], flash[k] = false, FLASH_TICKS end
      end
    end
    for k = 0, BOLTS - 1 do
      if flash[k] > 0 then flash[k] = flash[k] - 1 end
    end
  end

  return calls + 2 * (livingEnemies or 1)
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
-- from prior gameplay (same category as Flaming Arrow's FlamingArrowResidualLow12, despite
-- that one's name - both turned out to be fixed constants, not genuine per-savestate
-- garbage; Black Shadow's own scale/residual tables below ARE the real per-savestate case).
-- Interpreted as raw signed 32-bit values >>12 in the spawn formula - most are far from a
-- "1.0-ish" 4096, several look like large/negative bit patterns, which is expected and
-- intentional (not corruption).
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
-- tick has run) - originally assumed to be genuine leftover VFX-pool memory by analogy with
-- Flaming Arrow's residual table below, on the same "partial-word write preserves untouched
-- bits" reasoning. That analogy is now suspect: Flaming Arrow's own residual table turned out
-- (via a cross-savestate raw-memory check) to be a fixed constant, not real residue, despite
-- looking identical in kind. This table has NOT been independently re-checked across multiple
-- savestates the way HellSlotScale was (see its comment above) - do that before trusting
-- either "fixed constant" or "genuine per-savestate garbage" for this specific field. All 40
-- slots start inactive.
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
    local xRoll = rand() -- r1
    local rangeN = (C.RADIUS - 1) * 2
    local xInt = (xRoll % rangeN + 1) - C.RADIUS
    rand() -- Z-axis roll, unused
    local velRoll = rand() -- r3
    local velScale = (velRoll % 64) + 128
    local velX = -xInt * velScale
    -- arithmetic (floor) shift, not Lua's native logical ">>" - scale is frequently negative
    -- once reinterpreted as signed32 (see HellSlotScale's large entries)
    local scaleShifted = math.floor(signed32(scale) / 4096)
    local finalOff = cDiv(xInt * scaleShifted, 4096)
    local posX = (residualLow12 & 0xfff) | (signed32((finalOff + C.REF_X) * 4096) & 0xFFFFFFFF)
    local lifeRoll = rand() -- r4
    local life = lifeRoll % 120
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
-- PER-SAVESTATE stale VFX-pool memory (unlike Hell's baked table, and unlike Flaming Arrow's
-- residual bits, which turned out to also be a fixed constant despite the name - see its
-- comment above). Confirmed by comparing BlackShadowWind.State and BlackShadowBats.State
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
    local xRoll = rand() -- r1
    local rangeN = (C.RADIUS - 1) * 2
    local xInt = (xRoll % rangeN + 1) - C.RADIUS
    rand() -- Z-axis roll, unused
    local velRoll = rand() -- r3
    local velScale = (velRoll % 64) + 128
    local velX = -xInt * velScale
    local scaleShifted = math.floor(signed32(scale) / 4096)
    local finalOff = cDiv(xInt * scaleShifted, 4096)
    local posX = (residualLow12 & 0xfff) | (signed32((finalOff + C.REF_X) * 4096) & 0xFFFFFFFF)
    local lifeRoll = rand() -- r4
    local life = lifeRoll % 120
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

-- simulateJudgment(startSeed) -> totalRandCalls
-- startSeed is the RNG's raw 32-bit state the frame battle+0x14 holds spell_judgment_vfx_setup
-- (0x80116660), before its first rand(). Validated against 3 full per-frame live captures
-- (scripts/CaptureJudgment.lua) and 20 injected seeds (scripts/CaptureJudgmentSeeds.lua), 0 mismatches
-- - see docs/game_mechanics/Battle_Damage_Formula.md's "Judgment" section. Mechanism (from
-- spell_judgment_vfx_setup / spell_judgment_tick_state_machine, 0x80116b7c, 1 tick = 1 frame):
--   setup: 15 bolt particles, each rand()%48 (its first-spawn tick, stored at +0x24) then a scale
--     roll = 30 rand(). Only bolts 4..14 are ever spawned by the tick machine.
--   case 0-4 (64+32+64+64+64 ticks) and 6-7 (60+60): no rand(). Damage (case 7's end,
--     apply_elemental_multiplier(4, Dark, target, caster, 1500)) has none either.
--   case 5 (96 ticks), the only phase with rand():
--     4 pool heads, first spawn at tick 0/6/12/18, then re-spawned the tick after each dies. A head's
--     z starts at -300 and gains 20 per tick (applied in the same tick's epilogue), so it lives
--     exactly 15 ticks: a spawn every 15 ticks. 2 rand() per spawn (vfx_activate_and_position_particle).
--     Bolts 4..14: first spawn at their setup-rolled tick, then re-spawned the tick after their
--     non-looping sprite finishes (33 active frames, measured): a spawn every 34 ticks. 3 rand() per
--     spawn (rand()%100, then the shared helper's 2).
local JudgmentConstants = {
  SETUP_BOLTS = 15,
  FIRST_ACTIVE_BOLT = 4,
  CASE5_TICKS = 96,
  HEAD_FIRST_TICKS = { 0, 6, 12, 18 },
  HEAD_PERIOD = 15,
  BOLT_PERIOD = 34,
  HEAD_CALLS = 2,
  BOLT_CALLS = 3,
}

local function simulateJudgment(startSeed)
  local C = JudgmentConstants
  local seed = startSeed
  local calls = 0
  local function rand()
    seed = RNGLib.nextRNG(seed)
    calls = calls + 1
    return RNGLib.getRNG2(seed)
  end

  local boltFirst = {}
  for i = 0, C.SETUP_BOLTS - 1 do
    boltFirst[i] = rand() % 48                 -- first-spawn tick
    rand()                                     -- scale
  end

  for tick = 0, C.CASE5_TICKS - 1 do
    for _, first in ipairs(C.HEAD_FIRST_TICKS) do
      if tick >= first and (tick - first) % C.HEAD_PERIOD == 0 then
        calls = calls + C.HEAD_CALLS
      end
    end
    for i = C.FIRST_ACTIVE_BOLT, C.SETUP_BOLTS - 1 do
      local first = boltFirst[i]
      if tick >= first and (tick - first) % C.BOLT_PERIOD == 0 then
        calls = calls + C.BOLT_CALLS
      end
    end
  end

  return calls
end

-- simulateDropsOfKindness() -> totalRandCalls
-- Fixed, seed-independent: spell_drops_of_kindness_vfx_setup (0x801058d4) rolls 3 values for each of 6
-- droplet particles (scale, depth rand()%100, rotation) = 18 calls in one frame, and the tick machine
-- (0x80105bc8; 64+32+90+60+60 ticks) never calls rand(). Live-confirmed on 20 seeds, always 18 - see
-- docs/game_mechanics/Battle_Damage_Formula.md's "Drops of Kindness" section.
local function simulateDropsOfKindness()
  return 18
end

-- simulateFogOfDeception() -> totalRandCalls
-- Fixed 0: spell_fog_of_deception_vfx_setup (0x801061a0) and the tick machine
-- (0x801062f0; nine cases, 411 frames live) never call rand(), and neither does the
-- effect applied in its case 6 (per-enemy hit animation + a 4/5 scale of one enemy field). Live-confirmed
-- on 20 seeds: 0 calls from setup to the end handler (0x80106844) - see
-- docs/game_mechanics/Battle_Damage_Formula.md's "Fog of Deception" section.
local function simulateFogOfDeception()
  return 0
end

-- simulateRainOfKindness(startSeed, partyCount) -> totalRandCalls
-- startSeed is the RNG's raw 32-bit state the frame battle+0x14 holds spell_rain_of_kindness_vfx_setup
-- (0x80107294), before its first rand(). Mechanism (spell_rain_of_kindness_vfx_setup /
-- spell_rain_of_kindness_tick_state_machine 0x80107630, FUN_80123e2c = the rain-line spawn):
--   setup: 4 droplet particles per party member, 3 rand() each = 12 * partyCount (72 for a party of 6).
--   tick machine: cases 0-1 (64+32 ticks) no rand. Case 2 (90 ticks) sets ctx[0x55], the "rain" flag,
--     on its first tick; case 4 clears it on its last tick (60), so the shared epilogue runs the rain
--     spawn loop on 90 + 90 (case 3) + 59 = 239 ticks. Each tick, every inactive one of the 32 rain
--     lines (index order) spawns: 5 rand() = x, second axis, depth, speed (rand()%5 + 10, whole
--     units/tick) and a life roll the code never reads. A line starts at z = -300 and gains its speed
--     every tick (the spawn tick included); the tick it is seen with z > 0 it deactivates, so it respawns
--     the tick after: period = floor(300 / speed) + 2. Healing (-300 HP each, case 5) has no rand().
local RainOfKindnessConstants = {
  SETUP_CALLS_PER_PARTY_MEMBER = 12,
  LINE_COUNT = 32,
  RAIN_TICKS = 239,
  SPAWN_CALLS = 5,
  START_Z = -300,
  SPEED_BASE = 10,
  SPEED_RANGE = 5,
}

local function simulateRainOfKindness(startSeed, partyCount)
  local C = RainOfKindnessConstants
  local seed = startSeed
  local calls = 0
  local function rand()
    seed = RNGLib.nextRNG(seed)
    calls = calls + 1
    return RNGLib.getRNG2(seed)
  end

  for _ = 1, C.SETUP_CALLS_PER_PARTY_MEMBER * partyCount do rand() end

  local lines = {}
  for i = 1, C.LINE_COUNT do lines[i] = { active = false, z = 0, speed = 0 } end

  for tick = 0, C.RAIN_TICKS do
    if tick < C.RAIN_TICKS then
      for i = 1, C.LINE_COUNT do
        local line = lines[i]
        if not line.active then
          rand()                                   -- x
          rand()                                   -- second axis
          rand()                                   -- depth
          line.speed = rand() % C.SPEED_RANGE + C.SPEED_BASE
          rand()                                   -- life, never read
          line.z = C.START_Z
          line.active = true
        end
      end
    end
    for i = 1, C.LINE_COUNT do
      local line = lines[i]
      if line.z > 0 then
        line.active = false
      elseif line.active then
        line.z = line.z + line.speed
      end
    end
  end

  return calls
end

-- simulateWaterOfKindness(partyCount) -> totalRandCalls
-- Seed-independent, but scales with the party: spell_water_of_kindness_vfx_setup (0x801068f4) makes 4
-- droplet particles per party member with 3 rand() each = 12 * partyCount, and the tick machine
-- (0x80106be4; 64+32+90+60+60 ticks) and every function it calls have none (they are the same helpers
-- Rain of Kindness's machine calls, whose live totals match with no other source). Healing is 300 HP each,
-- no rand(). Live-confirmed on 20 seeds with a party of 6 (always 72) and by the user with a party of 5 (60) - see
-- docs/game_mechanics/Battle_Damage_Formula.md's "Water of Kindness" section.
local function simulateWaterOfKindness(partyCount)
  return 12 * partyCount
end

-- simulateMotherOcean(partyCount) -> totalRandCalls
-- STATIC ONLY, not yet checked against a live capture. Same shape as Water of Kindness: setup
-- (spell_mother_ocean_vfx_setup, 0x80107fdc) makes 4 droplet particles per party member with 3 rand()
-- each (the depth roll is %60 here, %200 there - no effect on the count) = 12 * partyCount, and the tick
-- machine (0x801082ec) and everything it calls have no rand(): the two helpers new to it only do GPU math
-- and a formation swap (FUN_8012055c -> battle_swap_combatant_positions -> play_attack_animation). The
-- heal (case 5: restore each member to full HP) has none either. See
-- docs/game_mechanics/Battle_Damage_Formula.md's "Mother Ocean" section.
local function simulateMotherOcean(partyCount)
  return 12 * partyCount
end

-- simulateWindOfSleep(startSeed, eligibleEnemies) -> totalRandCalls
-- startSeed is the RNG's raw 32-bit state the frame battle+0x14 holds spell_wind_of_sleep_vfx_setup
-- (0x80108b80), before its first rand(). eligibleEnemies = enemies whose combatant-record byte is 0 and whose
-- attack data has no 0x4000 bit (5 in WindOfSleep.State). Validated against one per-frame capture and 20
-- injected seeds (scripts/CaptureWindOfSleep.lua), 0 mismatches. Mechanism
-- (spell_wind_of_sleep_vfx_setup / spell_wind_of_sleep_tick_state_machine 0x80108d54, 1 tick = 1 frame):
--   setup: 50 particles x 2 rand() = 100.
--   tick machine: cases 64+64+64+64+96+64 = 416 ticks. Case 2's first tick (machine tick 128) sets
--     ctx[0x43]; case 4's last tick (350 + 1) clears it, so the shared epilogue's spawn loop runs on ticks
--     128..350 (223). Each tick, every INACTIVE particle (index order) gets vfx_randomize_sphere_particle
--     (3 rand) and a life roll rand()%180 (1 rand) = 4; the loop right after deactivates a particle whose
--     life is below 1. Nothing else counts life down, so a particle only respawns (next tick, 4 more rand)
--     after a life roll of exactly 0 (1 in 180).
--   effect: case 3 runs the hit-reaction script DAT_8016de9c on each eligible enemy; its opcode 40 rolls
--     once per enemy (status 5 = Sleep, 70% to land). The animation reaches it at machine tick ~360,
--     after the particle flag is cleared, so these draws never interleave with the particle ones.
local WindOfSleepConstants = {
  SETUP_PARTICLES = 50,
  FIRST_SPAWN_TICK = 128,
  LAST_SPAWN_TICK = 350,
  SPAWN_CALLS = 4,
  SPHERE_CALLS = 3,
  LIFE_RANGE = 180,
}

local function simulateWindOfSleep(startSeed, eligibleEnemies)
  local C = WindOfSleepConstants
  local seed = startSeed
  local calls = 0
  local function rand()
    seed = RNGLib.nextRNG(seed)
    calls = calls + 1
    return RNGLib.getRNG2(seed)
  end

  for _ = 1, C.SETUP_PARTICLES * 2 do rand() end

  local active, life = {}, {}
  for i = 1, C.SETUP_PARTICLES do active[i], life[i] = false, 0 end

  for tick = C.FIRST_SPAWN_TICK, C.LAST_SPAWN_TICK + 1 do
    if tick <= C.LAST_SPAWN_TICK then
      for i = 1, C.SETUP_PARTICLES do
        if not active[i] then
          for _ = 1, C.SPHERE_CALLS do rand() end
          life[i] = rand() % C.LIFE_RANGE
          active[i] = true
        end
      end
    end
    for i = 1, C.SETUP_PARTICLES do
      if life[i] < 1 then active[i] = false end
    end
  end

  for _ = 1, eligibleEnemies do rand() end       -- Sleep roll, one per enemy
  return calls
end

return {
  simulateEarthquake = simulateEarthquake,
  simulateCharmArrow = simulateCharmArrow,
  simulateFlamingArrow = simulateFlamingArrow,
  simulateFirestorm = simulateFirestorm,
  simulateExplosion = simulateExplosion,
  simulateDancingFlames = simulateDancingFlames,
  simulateFinalFlame = simulateFinalFlame,
  simulateStormFang = simulateStormFang,
  simulateBlazingCamp = simulateBlazingCamp,
  simulateThor = simulateThor,
  simulateScorchedEarth = simulateScorchedEarth,
  simulateWaterDragon = simulateWaterDragon,
  simulateDeadlyFingertips = simulateDeadlyFingertips,
  simulateAngryBlow = simulateAngryBlow,
  simulateRainstorm = simulateRainstorm,
  simulateClayGuardian = simulateClayGuardian,
  simulateCopperFlesh = simulateCopperFlesh,
  simulateScolding = simulateScolding,
  simulateTheShredding = simulateTheShredding,
  simulateHealingWind = simulateHealingWind,
  simulateStorm = simulateStorm,
  simulateVoiceOfEarth = simulateVoiceOfEarth,
  simulateYell = simulateYell,
  simulateScream = simulateScream,
  simulateGuardianOfEarth = simulateGuardianOfEarth,
  simulateThunderGod = simulateThunderGod,
  simulateRagingBlow = simulateRagingBlow,
  simulateBallOfLightning = simulateBallOfLightning,
  simulateShiningWind = simulateShiningWind,
  simulateHell = simulateHell,
  simulateBlackShadow = simulateBlackShadow,
  simulateBlackShadowWind = simulateBlackShadowWind,
  simulateBlackShadowBats = simulateBlackShadowBats,
  simulateJudgment = simulateJudgment,
  simulateDropsOfKindness = simulateDropsOfKindness,
  simulateFogOfDeception = simulateFogOfDeception,
  simulateRainOfKindness = simulateRainOfKindness,
  simulateWaterOfKindness = simulateWaterOfKindness,
  simulateMotherOcean = simulateMotherOcean,
  simulateWindOfSleep = simulateWindOfSleep,
}
