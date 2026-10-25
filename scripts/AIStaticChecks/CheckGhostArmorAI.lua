-- STATIC FINDING (Ghidra decompile, vb5.bin @ 0x80010178, base 0x80010000, no live capture yet):
-- ghost_armor_ai_select_target_and_move is a STRUCTURAL EXCEPTION unlike anything else traced so
-- far in this sweep - it has NO per-candidate RNG2 accept-roll and NO formationPos<4 front-row
-- restriction. It simply counts how many party members are alive (not dead) and not busy, across
-- ALL 6 formation slots (same unrestricted scope as Sydonia, but even simpler: no ~49% accept roll
-- per candidate either - every eligible member counts). If at least one qualifies, it
-- unconditionally arms LAB_80010224 as the next micro-state and commits (returns 1) - actual
-- target selection must happen inside that continuation code, not in this decision function. If
-- nobody qualifies (everyone dead or busy), it marks itself busy and returns 0.
--
-- This makes Ghost Armor a 4th confirmed back-row-reaching exception (alongside Killer Rabbit,
-- Slasher Rabbit, and Sydonia) - and structurally the simplest one, since it never needs an RNG2
-- roll to decide whether to act at all.
--
-- NO SAVESTATE EXISTS - not runnable yet. Once you have a savestate positioned in a battle against
-- a Ghost Armor, fill in SAVESTATE/ENEMY_SLOT below and run via scripts/spawn-headless-emuhawk.sh.
-- Checks the live per-instance MonsterRecord this enemy resolves to (pAttackDataTable[bId] chain)
-- against this static finding.
--
-- USAGE (once a savestate exists): edit SAVESTATE and ENEMY_SLOT below, then
--   scripts/spawn-headless-emuhawk.sh scripts/AIStaticChecks/CheckGhostArmorAI.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local Charmap = require "lib.Charmap"

local SAVESTATE = nil -- TODO fill in
local ENEMY_SLOT = nil -- TODO fill in (1-indexed combatant slot)

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckGhostArmorAI.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

if SAVESTATE == nil then
  log("No savestate configured yet - this script only documents the static finding above.")
  log("Static finding: AI @ 0x80010178 in vb5.bin (base 0x80010000). No row restriction, no")
  log("RNG accept-roll - commits unconditionally whenever any party member is alive/not busy.")
else
  local ok, err = pcall(function()
    savestate.load(SAVESTATE)
    for i = 1, 10 do emu.frameadvance() end

    local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))
    local rowArray = Address.sanitize(mainmemory.read_u32_le(base + 0x1344))
    local enemyDataAddr = base + 0x50 + ENEMY_SLOT * 0x8c
    local bId = mainmemory.read_u8(enemyDataAddr)
    local recordAddr = Address.sanitize(mainmemory.read_u32_le(rowArray + bId * 4))
    local name = Charmap.readStringFromMemory(recordAddr, 16)
    local aiFuncAddr = mainmemory.read_u32_le(recordAddr + 0x30)

    log(string.format("slot %d: bId=%d name=%q record=0x%08x aiFunc=0x%08x",
      ENEMY_SLOT, bId, name, recordAddr, aiFuncAddr))
    log(string.format("Expected aiFunc: 0x80010178 - match: %s", tostring(aiFuncAddr == 0x80010178)))
  end)
  if not ok then log("ERROR: " .. tostring(err)) end
end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
if SAVESTATE ~= nil then client.exit() end
