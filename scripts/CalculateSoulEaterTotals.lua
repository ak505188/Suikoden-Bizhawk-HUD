-- Reads a capture file produced by CaptureSoulEaterResidual.lua and computes each candidate
-- seed's exact rand()-call total and post-cast RNG state, using the validated pure-code
-- simulator in lib/Magic.lua - no BizHawk needed. Works for any Soul Eater-family spell; which
-- lib/Magic.lua function to call is read from the capture file's own `spell` field via
-- lib/SoulEaterCapture.lua's RECIPES table.
--
-- Run with: lua5.4 scripts/CalculateSoulEaterTotals.lua [path/to/capture.lua]
-- (from the project root; defaults to the same OUTPUT_FILE path
-- CaptureSoulEaterResidual.lua writes to if no argument is given)
--
-- See docs/game_mechanics/Black_Shadow_Simulation_Workflow.md for the full two-step workflow
-- this script is the second half of.

package.path = package.path .. ";./?.lua"

local RNGLib = require "lib.RNG"
local Magic = require "lib.Magic"
local SoulEaterCapture = require "lib.SoulEaterCapture"

local DEFAULT_CAPTURE_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/SoulEaterResidualCapture.lua"

local function finalSeedAfter(startSeed, calls)
  local seed = startSeed
  for _ = 1, calls do
    seed = RNGLib.nextRNG(seed)
  end
  return seed
end

local function main()
  local capturePath = arg and arg[1] or DEFAULT_CAPTURE_FILE
  local chunk, loadErr = loadfile(capturePath)
  if not chunk then
    io.stderr:write(string.format("Failed to load capture file '%s': %s\n", capturePath, tostring(loadErr)))
    os.exit(1)
  end
  local capture = chunk()

  local recipe = SoulEaterCapture.RECIPES[capture.spell]
  if not recipe then
    io.stderr:write(string.format("Unknown spell '%s' in capture file - see lib/SoulEaterCapture.lua's RECIPES table\n", tostring(capture.spell)))
    os.exit(1)
  end
  local simulate = Magic[recipe.magicFn]
  if not simulate then
    io.stderr:write(string.format("lib/Magic.lua has no function named '%s'\n", tostring(recipe.magicFn)))
    os.exit(1)
  end

  print(string.format("spell: %s (lib/Magic.lua's %s)", capture.spell, recipe.magicFn))
  print(string.format("%-12s %-12s %10s %6s %12s %-12s", "seed", "startSeed", "frames", "tick", "totalCalls", "finalSeed"))
  for _, entry in ipairs(capture.entries) do
    -- Hell-style recipes' magicFn (e.g. simulateHell) takes only a seed - Black-Shadow-style
    -- ones need the captured per-savestate table too. Pass everything simulate can use;
    -- functions that don't need the extra arguments simply ignore them.
    local calls = simulate(entry.startSeed, entry.scale, entry.residual, entry.scaleAccumInit)
    local final = finalSeedAfter(entry.startSeed, calls)
    print(string.format("0x%08x   0x%08x   %10d %6d %12d 0x%08x",
      entry.seed, entry.startSeed, entry.frameCount, entry.tickAtCapture, calls, final))
  end
end

main()
