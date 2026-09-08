-- Locates and dumps an enemy's AI action-selection function, ready for Ghidra import.
--
-- Background: this project's docs long flagged "which move an enemy picks" as an open
-- question. The call site was known (attack_data_table[Id]+0x30, invoked from
-- battle_dispatch_current_actor_action - see docs/game_mechanics/Turn_Order.md), but the
-- function body isn't in main.exe at all - it lives in the small per-battle overlay at
-- 0x80010000 (see feedback-ghidra-overlay-identification memory / Battle_Damage_Formula.md's
-- "AI/enemy move selection" section, where this exact recipe found and validated Zombie
-- Dragon's own AI formula 10/10 against live capture data).
--
-- This script automates the mechanical part (finding the function's address and dumping the
-- overlay bytes) - reading the decompile and deriving the actual formula is still manual work,
-- done in Ghidra after this. See docs/game_mechanics/Enemy_AI_Tracing_Methodology.md for the
-- full repeatable procedure this is step 1 of.
--
-- USAGE: edit BASE_SAVE/ENEMY_ACTOR_ID below (ENEMY_ACTOR_ID is this enemy's 1-indexed actor
-- number in THIS savestate's roster - same convention as scripts/CaptureEnemyMoveResults.lua,
-- re-derive it per savestate by watching base+0x8), run via
-- scripts/spawn-headless-emuhawk.sh scripts/LocateEnemyAIFunction.lua
--
-- Output: a .bin dump of the overlay (OUT_BIN) plus a text report (OUT_TXT) with every address
-- needed for the Ghidra side: import OUT_BIN, language PSX:LE:32:default, auto_analyze=false,
-- then set_image_base to OVERLAY_BASE (triggers analysis), then create_function +
-- decompile_function at the reported AI function address.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path

local Address = require "lib.Address"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/ZombieDragonT2.State"
local ENEMY_ACTOR_ID = 7

local OVERLAY_BASE = 0x10000 -- KUSEG-stripped 0x80010000, the small/room overlay region
local OVERLAY_SIZE = 0x20000 -- 128KB - generous for a small per-monster AI function; bump if
                              -- the reported AI function address falls suspiciously close to
                              -- or past this window's end

local OUT_BIN = "/tmp/enemy_ai_overlay.bin"
local OUT_TXT = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/LocateEnemyAIFunction.txt"

local lines = {}
local function log(s) table.insert(lines, s) end
local function sanitize(addr) return addr & 0x1fffff end
local function isValidPtr(addr) return Address.isValidPointer(addr) end

local ok, err = pcall(function()
  savestate.load(BASE_SAVE)
  for i = 1, 200 do emu.frameadvance() end -- battle struct populated, stable (see BattleSnapshot.lua)

  local baseRaw = memory.read_u32_le(Address.BATTLE_STATE_PTR)
  if not isValidPtr(baseRaw) then error("battle struct pointer invalid") end
  local base = sanitize(baseRaw)
  log(string.format("battle base = 0x%x", base))

  local ed = base + 0x50 + ENEMY_ACTOR_ID * 0x8c
  local id = memory.read_u8(ed + 0x0)
  log(string.format("enemy_data[%d].Id = %d", ENEMY_ACTOR_ID, id))

  local attackDataTableRaw = memory.read_u32_le(base + 0x1344)
  if not isValidPtr(attackDataTableRaw) then error("attack_data_table pointer invalid") end
  local attackDataTable = sanitize(attackDataTableRaw)
  log(string.format("attack_data_table ptr = 0x%x", attackDataTable))

  local monsterRecordRaw = memory.read_u32_le(attackDataTable + id * 4)
  if not isValidPtr(monsterRecordRaw) then error("monster record pointer invalid") end
  local monsterRecord = sanitize(monsterRecordRaw)
  log(string.format("monster record ptr (attack_data_table[%d]) = 0x%x", id, monsterRecord))

  local aiFuncAddr = memory.read_u32_le(monsterRecord + 0x30)
  log(string.format("AI function address (monsterRecord+0x30) = 0x%x", aiFuncAddr))

  if aiFuncAddr < 0x80000000 + OVERLAY_BASE or aiFuncAddr >= 0x80000000 + OVERLAY_BASE + OVERLAY_SIZE then
    log(string.format(
      "WARNING: AI function address 0x%x falls OUTSIDE the dumped overlay window [0x%x, 0x%x) - " ..
      "it may be in main.exe itself (check get_function_by_address there first) or a larger " ..
      "overlay (0x80080000 base) - adjust OVERLAY_BASE/OVERLAY_SIZE and re-run if so.",
      aiFuncAddr, 0x80000000 + OVERLAY_BASE, 0x80000000 + OVERLAY_BASE + OVERLAY_SIZE))
  end

  local f = io.open(OUT_BIN, "wb")
  local chunk = 0x1000
  for off = 0, OVERLAY_SIZE - 1, chunk do
    local part = memory.read_bytes_as_array(OVERLAY_BASE + off, chunk)
    local chars = {}
    for i = 1, #part do chars[i] = string.char(part[i]) end
    f:write(table.concat(chars))
  end
  f:close()
  log(string.format("\nDumped %d bytes to %s", OVERLAY_SIZE, OUT_BIN))
  log(string.format("Ghidra next steps: import_file(%q, language=PSX:LE:32:default, auto_analyze=false)",
    OUT_BIN))
  log(string.format("  then set_image_base(0x%x) on it, then create_function(0x%x), then decompile_function(0x%x)",
    0x80000000 + OVERLAY_BASE, aiFuncAddr, aiFuncAddr))
end)
if not ok then log("ERROR: " .. tostring(err)) end

local f = io.open(OUT_TXT, "w")
f:write(table.concat(lines, "\n"))
f:close()
client.exit()
