-- Follow-up to DiffEnemyDataUnkRegions.lua: check whether the sign-flipping cluster found at
-- EnemyData+0x1d/+0x1e-1f/+0x34-35/+0x36-37 (which flips every time the +0x10 idle timer resets,
-- roughly every 59-60 frames) actually drives Gigantes' on-screen position (nPosX/Y/Z at
-- +0x5c/+0x60/+0x64, nRefPosX/Y/Z at +0x68/+0x6c/+0x70), by sampling those fields at and around
-- each observed reset frame (37, 97, 158, 218, 279, 339, 400, 460).
--
-- USAGE: scripts/spawn-headless-emuhawk.sh /home/alex/Projects/Suikoden-Bizhawk-HUD/scripts/CheckSwayPositionLink.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local Charmap = require "lib.Charmap"
local BattleRoundInput = require "lib.BattleRoundInput"

local SAVESTATE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/Gigantes.State"
local SAMPLE_FRAMES = {35, 36, 37, 38, 60, 96, 97, 98, 120, 157, 158, 159, 217, 218, 219}
local TRACE_FRAMES = 460

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckSwayPositionLink.txt"
local outHandle = io.open(OUTPUT_FILE, "w")
local function log(s)
  console.log(s)
  if outHandle then outHandle:write(s .. "\n"); outHandle:flush() end
end

local ok, err = pcall(function()
  savestate.load(SAVESTATE)
  for i = 1, 5 do emu.frameadvance() end

  local baseRaw = mainmemory.read_u32_le(Address.BATTLE_STATE_PTR)
  local base = Address.sanitize(baseRaw)
  local partyCount = mainmemory.read_u32_le(base + 0x1c)
  local totalCombatants = mainmemory.read_u32_le(base + 0x24)
  local rowArray = Address.sanitize(mainmemory.read_u32_le(base + 0x1344))

  local gigantesIdx = nil
  for idx = partyCount + 1, totalCombatants do
    local enemyDataAddr = base + 0x50 + idx * 0x8c
    local speciesId = mainmemory.read_u8(enemyDataAddr)
    local recordAddr = Address.sanitize(mainmemory.read_u32_le(rowArray + speciesId * 4))
    local name = Charmap.readStringFromMemory(recordAddr, 16)
    if name:match("^Gigantes") then gigantesIdx = idx end
  end
  local enemyDataAddr = base + 0x50 + gigantesIdx * 0x8c
  log(string.format("Gigantes EnemyData at relative 0x%06x", enemyDataAddr))

  local newBase = BattleRoundInput:chooseRoundOption(BattleRoundInput.Choice.FREE_WILL)
  if not newBase then error("round-start menu never became ready") end

  local sampleSet = {}
  for _, f in ipairs(SAMPLE_FRAMES) do sampleSet[f] = true end

  for frame = 1, TRACE_FRAMES do
    emu.frameadvance()
    if sampleSet[frame] then
      local timer = mainmemory.read_u8(enemyDataAddr + 0x10)
      local swayFlag = mainmemory.read_s8(enemyDataAddr + 0x1d)
      local sway1e = mainmemory.read_s16_le(enemyDataAddr + 0x1e)
      local sway34 = mainmemory.read_s16_le(enemyDataAddr + 0x34)
      local nPosX = mainmemory.read_s32_le(enemyDataAddr + 0x5c)
      local nPosY = mainmemory.read_s32_le(enemyDataAddr + 0x60)
      local nPosZ = mainmemory.read_s32_le(enemyDataAddr + 0x64)
      local nRefPosX = mainmemory.read_s32_le(enemyDataAddr + 0x68)
      local nRefPosY = mainmemory.read_s32_le(enemyDataAddr + 0x6c)
      local nRefPosZ = mainmemory.read_s32_le(enemyDataAddr + 0x70)
      log(string.format(
        "frame %3d: timer=%3d sway1d=%4d sway1e=%6d sway34=%6d | nPos=(%d,%d,%d) nRefPos=(%d,%d,%d)",
        frame, timer, swayFlag, sway1e, sway34, nPosX, nPosY, nPosZ, nRefPosX, nRefPosY, nRefPosZ))
    end
  end
end)

if not ok then log("ERROR: " .. tostring(err)) end
if outHandle then outHandle:close() end
client.exit()
