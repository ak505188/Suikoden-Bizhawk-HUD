-- Generic capture tool for any Soul Eater-family spell (Hell, Black Shadow, ...): for a list
-- of candidate RNG seeds, loads a user-supplied savestate positioned right before the target
-- spell's cast begins, injects each seed, and captures the data lib/Magic.lua's simulator
-- needs (40-slot scale/residual table, scaleAccum init, exact starting seed) once that
-- spell's RNG-consuming phase becomes active.
--
-- WHY THIS EXISTS: some Soul Eater spells (confirmed for Black Shadow, not Hell) read a
-- 40-slot "scale" table and per-slot posX residue from a shared VFX scratch struct
-- (DAT_8017a060/Address.SOUL_EATER_CTX) that is NOT reset before their cast - it's whatever
-- was last written there by some other, unidentified VFX effect. That data can't be derived
-- in pure code, but everything that produces it IS deterministic given a starting seed and a
-- savestate positioned at the cast boundary, so capturing it live here (cheap - only needs to
-- fast-forward through whatever wind-up ticks remain before the RNG-consuming phase, not the
-- spell's own multi-thousand-call cast itself) and handing it to the validated pure-code
-- simulator (CalculateSoulEaterTotals.lua, no BizHawk needed) gives an exact answer far
-- faster than frame-advancing through the whole cast for every candidate seed.
--
-- REQUIRES a savestate positioned right before the target spell's cast (like
-- BlackShadowWind.State/BlackShadowBats.State) - NOT an earlier point in the battle. Getting
-- from an arbitrary earlier point (battle start, a prior turn, etc.) to a specific spell's
-- cast requires real button input (menu confirmations, turn/action selection) that has no
-- generic solution - that has to be handled by however you produced the savestate in the
-- first place (playing it live, or your own scenario-specific driver script).
--
-- USAGE: edit SPELL/BASE_SAVE/SEEDS below, run via scripts/spawn-headless-emuhawk.sh, then
-- feed the OUTPUT_FILE it writes to CalculateSoulEaterTotals.lua with a plain `lua5.4`
-- interpreter (no BizHawk needed for that step). Full walkthrough in
-- docs/game_mechanics/Black_Shadow_Simulation_Workflow.md.
--
-- CAVEAT: each seed needs its own real fast-forward pass here - there is no way to skip
-- straight to the cast for a candidate seed without actually running the (few) frames leading
-- up to it. Fine for tens to low hundreds of candidates.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path

local Address = require "lib.Address"
local SoulEaterCapture = require "lib.SoulEaterCapture"

-- Which spell recipe to use - see lib/SoulEaterCapture.lua's M.RECIPES for the full list.
-- NOTE: Hell doesn't actually need this tool - its scale/residual table is a fixed,
-- spell-wide constant already embedded in lib/Magic.lua (simulateHell takes only a seed), so
-- there's nothing per-savestate to capture for it. This tool exists for spells like Black
-- Shadow, where that data is genuine per-savestate stale memory. "Hell" is supported here
-- (and was used to validate this tool is spell-agnostic) but you'd normally just call
-- Magic.simulateHell(seed) directly instead of running a live capture for it.
local SPELL = "BlackShadow"

-- The savestate to capture from - must already be positioned right before SPELL's cast
-- begins (i.e. the RNG-consuming phase starts within a few dozen frames of loading this, not
-- after navigating menus/turns - see the module-level comment above).
local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/BlackShadowWind.State"

-- Raw 32-bit RNG seeds to test (the value that would be written to Address.RNG right after
-- loading BASE_SAVE) - NOT RNGTable indices. If you're working from an index into this
-- project's RNGTable convention, resolve it to a raw seed yourself first
-- (RNGTable(0x42, N):getRNG(index)) and list the raw values here.
local SEEDS = {
  0x00000001,
  0x12345678,
  0xdeadbeef,
}

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/SoulEaterResidualCapture.lua"

local MAX_FRAMES = 500 -- generous for a savestate positioned right before the cast; increase
                        -- if BASE_SAVE is further from the target phase than expected

local function serializeIntArray(arr)
  local parts = {}
  for i = 1, #arr do
    parts[i] = tostring(arr[i])
  end
  return "{ " .. table.concat(parts, ", ") .. " }"
end

local function main()
  local recipe = SoulEaterCapture.RECIPES[SPELL]
  if not recipe then
    console.log("Unknown SPELL '" .. tostring(SPELL) .. "' - see lib/SoulEaterCapture.lua's RECIPES table")
    client.exit()
    return
  end

  local results = {}
  for _, seed in ipairs(SEEDS) do
    savestate.load(BASE_SAVE)
    mainmemory.write_u32_le(Address.RNG, seed)
    local captured, err = SoulEaterCapture.captureOne(recipe, MAX_FRAMES)
    if captured then
      table.insert(results, string.format(
        "  { seed = 0x%08x, startSeed = 0x%08x, frameCount = %d, tickAtCapture = %d, scaleAccumInit = %d, scale = %s, residual = %s },",
        seed, captured.startSeed, captured.frameCount, captured.tickAtCapture, captured.scaleAccumInit,
        serializeIntArray(captured.scale), serializeIntArray(captured.residual)))
      console.log(string.format("seed 0x%08x: captured at frame %d (tick=%d)", seed, captured.frameCount, captured.tickAtCapture))
    else
      table.insert(results, string.format("  -- seed 0x%08x FAILED: %s", seed, err))
      console.log(string.format("seed 0x%08x: FAILED (%s)", seed, err))
    end
  end

  local body = "-- Generated by scripts/CaptureSoulEaterResidual.lua - do not hand-edit.\n"
    .. "-- Load with CalculateSoulEaterTotals.lua (plain lua5.4, no BizHawk needed).\n"
    .. string.format("return {\n  spell = %q,\n  entries = {\n", SPELL)
    .. table.concat(results, "\n") .. "\n  },\n}\n"
  local file, writeErr = io.open(OUTPUT_FILE, "w")
  if file then
    file:write(body)
    file:close()
    console.log("Wrote " .. OUTPUT_FILE)
  else
    console.log("Failed to write output file: " .. tostring(writeErr))
  end
end

main()
client.exit()
