-- STATIC FINDING (Ghidra decompile, f_data.bin @ 0x80084294, base 0x80080000, no live capture yet):
-- mirage_ai_select_target_and_move is a 2ND CONFIRMED INSTANCE of the Sydonia-style pattern (see
-- Sydonia's own documentation in docs/game_mechanics/Battle_Damage_Formula.md): scans ALL party
-- members with NO front-row gate at all (same ~49%-per-candidate RNG2 accept, just without the
-- formationPos<4 restriction - like Sydonia/Ghost Armor/Red Elemental). After a target locks, it
-- branches on the LOCKED TARGET's OWN row - mirrored from Sydonia's version:
--   if the locked target is in the FRONT row: declines (return -1 -> plain Attack)
--   if the locked target is in the BACK row: commits to a special move against that SAME target
--     (clears a 2-byte field on itself at selfIdx*0x8c+0x90 - same field Shadow Man clears -
--     script 0x800a4c40, next micro-state LAB_80083848, returns 1)
-- Sydonia does the OPPOSITE (front-row target -> special move, back-row target -> decline) - same
-- structural template, opposite row trigger. This is useful independent confirmation that the
-- "scan unrestricted, then branch on the target's own locked row" template is a real, reused
-- pattern in this engine, not a one-off quirk unique to Sydonia.
--
-- NO SAVESTATE EXISTS - not runnable yet. Once you have a savestate positioned in a battle against
-- a Mirage (ideally with a target locked in the back row, to trigger the special-move branch),
-- fill in SAVESTATE/ENEMY_SLOT below and run via scripts/spawn-headless-emuhawk.sh. Checks the
-- live per-instance MonsterRecord this enemy resolves to (pAttackDataTable[bId] chain) against
-- this static finding.
--
-- USAGE (once a savestate exists): edit SAVESTATE and ENEMY_SLOT below, then
--   scripts/spawn-headless-emuhawk.sh scripts/AIStaticChecks/CheckMirageAI.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local Charmap = require "lib.Charmap"

local SAVESTATE = nil -- TODO fill in
local ENEMY_SLOT = nil -- TODO fill in (1-indexed combatant slot)

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckMirageAI.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

if SAVESTATE == nil then
  log("No savestate configured yet - this script only documents the static finding above.")
  log("Static finding: AI @ 0x80084294 in f_data.bin (base 0x80080000). No front-row gate on the")
  log("scan; branches on the LOCKED TARGET's row: front-row target -> plain Attack, back-row")
  log("target -> special move (0x800a4c40). Sydonia-style, mirrored direction.")
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
    log(string.format("Expected aiFunc: 0x80084294 - match: %s", tostring(aiFuncAddr == 0x80084294)))
  end)
  if not ok then log("ERROR: " .. tostring(err)) end
end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
if SAVESTATE ~= nil then client.exit() end
