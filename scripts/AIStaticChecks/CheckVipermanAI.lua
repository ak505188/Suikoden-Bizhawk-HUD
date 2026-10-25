-- STATIC FINDING (Ghidra decompile, vd5.bin @ 0x800132d0, base 0x80010000, no live capture yet):
-- viperman_ai_select_target_and_move is a 2ND CONFIRMED INSTANCE of the Beast Commander
-- "commander" pattern (see CheckBeastCommanderAI.lua) - byte-for-byte the same shape, just in a
-- different area file:
--   - First scans OTHER ENEMY slots for any ally that is alive, not busy, and in the front row.
--   - If Viperman itself is in the front row, OR no such eligible ally was found: falls back to
--     the ordinary front-row-only party-target scan (~49%-per-candidate accept/retry) and always
--     commits to a plain physical Attack once a target locks.
--   - If Viperman is in the BACK row AND has an eligible front-row ally: instead plays a
--     self-targeted "command" script (0x800716d0, next micro-state LAB_8001352c).
-- Finding this exact pattern independently in TWO different area files (Beast Commander in
-- b_data.bin, Viperman here in vd5.bin) makes it much more likely this is a real, reachable
-- mechanic used by multiple "commander"-type monsters, not a one-off curiosity or dead code -
-- worth prioritizing for live validation (ideally testing Viperman in the BACK row with an
-- eligible front-row ally present, to see if the command branch actually triggers and what it
-- does).
--
-- NO SAVESTATE EXISTS - not runnable yet. Once you have a savestate positioned in a battle
-- involving a Viperman (ideally in the BACK row with a front-row ally alive), fill in
-- SAVESTATE/ENEMY_SLOT below and run via scripts/spawn-headless-emuhawk.sh. Checks the live
-- per-instance MonsterRecord this enemy resolves to (pAttackDataTable[bId] chain) against this
-- static finding.
--
-- USAGE (once a savestate exists): edit SAVESTATE and ENEMY_SLOT below, then
--   scripts/spawn-headless-emuhawk.sh scripts/AIStaticChecks/CheckVipermanAI.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local Charmap = require "lib.Charmap"

local SAVESTATE = nil -- TODO fill in
local ENEMY_SLOT = nil -- TODO fill in (1-indexed combatant slot)

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckVipermanAI.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

if SAVESTATE == nil then
  log("No savestate configured yet - this script only documents the static finding above.")
  log("Static finding: AI @ 0x800132d0 in vd5.bin (base 0x80010000). Same 'commander' pattern as")
  log("Beast Commander: back row + eligible front-row ally -> command script (0x800716d0).")
  log("Otherwise: front-row-only scan, always plain Attack.")
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
    log(string.format("Expected aiFunc: 0x800132d0 - match: %s", tostring(aiFuncAddr == 0x800132d0)))
  end)
  if not ok then log("ERROR: " .. tostring(err)) end
end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
if SAVESTATE ~= nil then client.exit() end
