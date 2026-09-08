-- Empirical sweep: write many different RNG values (right after loading Dragon.State, before
-- any frame advance) and record the resulting move (Lightning=1 target hit, Fire Breath=multi
-- target hit) for each. Used to brute-force validate/discover the real move-selection formula
-- after a hand-derived one-roll-per-candidate model failed to predict the RNG+1 case correctly.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/Dragon.State"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/DragonSweepResults.txt"
local COMBATANT_BASE = 0xb94
local MAX_FRAMES = 600 -- phase-3 "wait for turn to end" never actually detects actor!=7 within
  -- 600 frames in practice (confirmed across all 12 seeds of the first sweep), so this cap
  -- always gets hit - kept at 600 for safety (200 was tried and cut off before damage landed,
  -- producing hits=0 false negatives). Unthrottled mode (config-headless.ini) makes this fast
  -- regardless of the cap - the earlier slowness was wall-clock throttling, not frame count.
local ENEMY_ACTOR_ID = 7
local NUM_COMBATANTS = 7

local SEEDS = {
  -- 50 fresh seeds, disjoint from every previously tested seed (both the original 12-seed
  -- batch and the earlier 30-seed batch), for an independent verification of the 100%-validated
  -- retry-loop formula in Battle_Damage_Formula.md.
  0x6aa79987, 0xbb91433a, 0x029a7245, 0xd1f6f86c, 0xd340bbcd,
  0xcd8778e7, 0x4c73a942, 0xdaea58ba, 0x5e503a67, 0xee897110,
  0x3193ca54, 0x452ec40a, 0x90e5e945, 0x6facaa50, 0x29645f8b,
  0x5f811cb9, 0x1fcff454, 0xdfc9e3b1, 0x6ed4e94b, 0x42d6cb5c,
  0x8fe46024, 0xa091250e, 0x2ca1c789, 0x9c9cea0c, 0x8d9fe5b9,
  0x2fd2b7a4, 0x5adad121, 0xbcf74d7a, 0xf543bbcf, 0xbb9d58e4,
  0x175f0cd2, 0x87f26aee, 0xfa882692, 0xbc428d42, 0x6980a81f,
  0x95c5fb98, 0x8101e89a, 0x2aa4857e, 0x25ece845, 0x34a9af41,
  0xb80e3b0d, 0x13ed748b, 0x30a1f6d5, 0xd64a3ce0, 0x57708107,
  0x527122dc, 0x06057c82, 0x7576714a, 0x56eaa301, 0x06e0f458,
}

local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

local function readCombatant(base, slot)
  local addr = base + COMBATANT_BASE + slot * 0x54
  return {
    curHp = mainmemory.read_u16_le(addr + 0x12),
    actionType = mainmemory.read_u8(addr + 0x47),
    abilitySlot = mainmemory.read_u8(addr + 0x48),
    targetIdx = mainmemory.read_u8(addr + 0x49),
  }
end

local function runOne(seed)
  savestate.load(BASE_SAVE)
  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))
  mainmemory.write_u32_le(Address.RNG, seed)

  local baseline = {}
  for i = 0, NUM_COMBATANTS - 1 do baseline[i] = readCombatant(base, i).curHp end

  local frame = 0
  local decided
  while frame < MAX_FRAMES do
    decided = readCombatant(base, ENEMY_ACTOR_ID - 1)
    if decided.actionType ~= 0 or decided.abilitySlot ~= 0 then break end
    emu.frameadvance()
    frame = frame + 1
  end

  while frame < MAX_FRAMES do
    if mainmemory.read_u32_le(base + 0x8) ~= ENEMY_ACTOR_ID then break end
    emu.frameadvance()
    frame = frame + 1
  end

  local damage = {}
  local hitCount = 0
  for i = 0, NUM_COMBATANTS - 1 do
    local finalHp = readCombatant(base, i).curHp
    if finalHp ~= baseline[i] then
      hitCount = hitCount + 1
      damage[#damage + 1] = string.format("s%d:-%d", i, baseline[i] - finalHp)
    end
  end

  local moveName = hitCount <= 1 and "Lightning" or "FireBreath"
  return string.format("seed=0x%08x -> %s hits=%d dmg=[%s] frames=%d",
    seed, moveName, hitCount, table.concat(damage, ","), frame)
end

local function flush()
  local file = io.open(OUTPUT_FILE, "w")
  if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
end

local ok, err = pcall(function()
  for _, seed in ipairs(SEEDS) do
    log(runOne(seed))
    flush() -- write incrementally so a timeout mid-sweep still keeps partial results
  end
end)
if not ok then log("ERROR: " .. tostring(err)) end
flush()
client.exit()
