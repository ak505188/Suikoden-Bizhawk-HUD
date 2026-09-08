-- Generic live-capture helper for the Soul Eater spell family (Hell, Black Shadow, and any
-- future spell found to share the same mechanism - see spell_hell_spawn_particle's plate
-- comment in Ghidra and docs/game_mechanics/Battle_Damage_Formula.md's "Hell"/"Black Shadow"
-- sections). Every spell in this family shares the same per-slot particle layout (scale at
-- slot+0x30, posX at slot+0x1c, 0x44-byte stride) inside the same shared context struct
-- (DAT_8017a060/Address.SOUL_EATER_CTX) - only the handler address, this spell's own
-- case/tick/scaleAccum bookkeeping field offsets, and where its own slot array starts within
-- that shared struct differ per spell. Those differences are captured once per spell as a
-- "recipe" in M.RECIPES below.
--
-- This module must be `require`d from a script launched with the project root prepended to
-- package.path (BizHawk's --lua= CLI doesn't do this on its own - see
-- feedback-emuhawk-cli-lua-scripts / the project's EmuHawk CLI notes):
--   package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
--   local SoulEaterCapture = require "lib.SoulEaterCapture"
--
-- Used by scripts/CaptureSoulEaterResidual.lua - see
-- docs/game_mechanics/Black_Shadow_Simulation_Workflow.md for the full workflow this fits
-- into.

local Address = require "lib.Address"

local M = {}

-- captureOne(recipe, maxFrames) -> captured table, or nil, "timeout"
--
-- Call right after loading a savestate and injecting a seed (savestate.load + write_u32_le
-- Address.RNG). The savestate should already be positioned at or shortly before the target
-- spell's cast begins - this only fast-forwards through whatever wind-up ticks remain before
-- its RNG-consuming phase, NOT through menus, turn selection, or any other battle flow (there
-- is no generic way to automate that - see the Black Shadow workflow doc's note on why the
-- savestate needs to already be positioned this way).
--
-- Returns { startSeed, scale (recipe.slotCount-entry array), residual (same), scaleAccumInit,
-- frameCount, tickAtCapture } once recipe.handler is the active battle-state handler AND its
-- own case field reads recipe.caseValue. tickAtCapture should read whatever this recipe's
-- phase starts at (e.g. Black Shadow's tick counter counts UP from 0, so 0; Hell's counts
-- DOWN from 128, so 128) - if it doesn't match the spell's known starting value, the
-- savestate wasn't actually positioned where expected.
function M.captureOne(recipe, maxFrames)
  maxFrames = maxFrames or 500
  local frame = 0
  while frame < maxFrames do
    local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))
    local handler = mainmemory.read_u32_le(base + 0x14)
    if handler == recipe.handler then
      local ctx = Address.sanitize(mainmemory.read_u32_le(Address.SOUL_EATER_CTX))
      local caseVal = mainmemory.read_u32_le(ctx + recipe.caseFieldOffset)
      if caseVal == recipe.caseValue then
        local tick = mainmemory.read_u32_le(ctx + recipe.tickFieldOffset)
        local scaleAccum = mainmemory.read_u32_le(ctx + recipe.scaleAccumFieldOffset)
        local startSeed = mainmemory.read_u32_le(Address.RNG)
        local scale, residual = {}, {}
        for i = 0, recipe.slotCount - 1 do
          local slotBase = ctx + recipe.slotBaseOffset + i * recipe.slotStride
          scale[i + 1] = mainmemory.read_u32_le(slotBase + recipe.slotScaleOffset)
          residual[i + 1] = mainmemory.read_u32_le(slotBase + recipe.slotPosXOffset) & 0xfff
        end
        return {
          startSeed = startSeed,
          scale = scale,
          residual = residual,
          scaleAccumInit = scaleAccum,
          frameCount = frame,
          tickAtCapture = tick,
        }
      end
    end
    emu.frameadvance()
    frame = frame + 1
  end
  return nil, "timeout"
end

-- Known spell recipes. Add a new entry here once a new Soul Eater-family spell's mechanism is
-- traced (see docs/game_mechanics/Spell_RNG_Tracing_Methodology.md) and confirmed to reuse
-- spell_hell_spawn_particle. `magicFn` names the lib/Magic.lua function CalculateSoulEater
-- Totals.lua should call for this recipe's captured data - for a spell whose particle-pool
-- table turns out to be a fixed spell-wide constant (like Hell, not just per-savestate
-- garbage like Black Shadow), that function may not need the captured scale/residual data at
-- all (see simulateHell, which takes only a seed) - capturing is still harmless, just
-- unnecessary, in that case.
M.RECIPES = {
  BlackShadow = {
    handler = 0x80114ca8,
    caseFieldOffset = 0x2b6 * 4,   -- ctx + 0xad8
    caseValue = 2,
    tickFieldOffset = 0x2b7 * 4,   -- ctx + 0xadc
    scaleAccumFieldOffset = 0x2b4 * 4, -- ctx + 0xad0
    slotBaseOffset = 0x2c,
    slotStride = 0x44,
    slotCount = 40,
    slotScaleOffset = 0x30,
    slotPosXOffset = 0x1c,
    magicFn = "simulateBlackShadow", -- takes (startSeed, scale, residual, scaleAccumInit)
  },
  Hell = {
    handler = 0x80115a7c,
    caseFieldOffset = 0x14,        -- ctx + 0x14
    caseValue = 2,
    tickFieldOffset = 0x18,        -- ctx + 0x18
    scaleAccumFieldOffset = 0x3c,  -- ctx + 0x3c
    slotBaseOffset = 0x44,
    slotStride = 0x44,
    slotCount = 40,
    slotScaleOffset = 0x30,
    slotPosXOffset = 0x1c,
    magicFn = "simulateHell", -- takes only (startSeed) - Hell's table is a fixed spell-wide
                               -- constant already embedded in lib/Magic.lua, not per-savestate
  },
}

return M
