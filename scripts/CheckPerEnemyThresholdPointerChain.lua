-- User: "Now is there a way to find these on a per-enemy basis?" -> "I meant more in terms of
-- pointers/offsets in in-game memory." Demonstrates the REAL per-enemy (per-species) live memory
-- pointer chain battle_dispatch_current_actor_action (main.exe 0x800f40fc) itself uses to find
-- an enemy's own AI function - no ROM/Ghidra needed, purely live memory reads:
--
--   1. base = BattleState (Address.BATTLE_STATE_PTR)
--   2. bId = EnemyDataArray[slot].bId                    (base+0x50+slot*0x8c+0x00)
--   3. rowPtrArray = *(base+0x1344)                        (BattleState.pAttackDataTable)
--   4. speciesRow = *(rowPtrArray + bId*4)                 (per-species row pointer)
--   5. aiFuncAddr = *(speciesRow + 0x30)                   (the AI function's live address)
--
-- Then, from aiFuncAddr, scans forward through LIVE instruction memory for the known
-- `ori v0,zero,0x7fff` signature (word 0x34027fff) and reads the immediate off the following
-- `slti` - the exact same technique used for the static ROM scan, just walked entirely through
-- live RAM starting from a genuine per-enemy pointer instead of a Ghidra address.
--
-- USAGE: scripts/spawn-headless-emuhawk.sh scripts/CheckPerEnemyThresholdPointerChain.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path

local Address = require "lib.Address"

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckPerEnemyThresholdPointerChain.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

local PATTACKDATATABLE_OFFSET = 0x1344
local ENEMYDATA_STRIDE = 0x8c

local function findThreshold(base, aiFuncAddr)
  -- Scan up to 150 instructions (600 bytes) forward for the ori v0,zero,0x7fff signature word -
  -- wide enough to cover a target-scan-with-retry preamble (e.g. Soldier Ant's own loop pushes
  -- its move-choice roll to +0x174) as well as near-immediate cases (Queen Ant's own, no
  -- preamble at all). Keep looking past the FIRST hit too, in case a function has multiple
  -- move-choice rolls (e.g. Neclord's own 2-roll Wind/Bats/Lightning split, or Golden Hydra's 3).
  local hits = {}
  local off = 0
  while off <= 600 do
    local word = mainmemory.read_u32_le(Address.sanitize(aiFuncAddr + off))
    if word == 0x34027fff then
      -- 128 bytes (32 instructions) - wide enough to cover both the simple 1-division shape
      -- (Queen Ant/Dragon/Neclord/etc: (roll*100)/32767 < threshold) and the 2-division %100
      -- shape (Soldier Ant: ((roll*100)/32767)%100 < threshold, which inserts a whole extra
      -- div-by-100 + mfhi sequence before its own slti).
      for off2 = off + 4, off + 128, 4 do
        local w2 = mainmemory.read_u32_le(Address.sanitize(aiFuncAddr + off2))
        local opcode = (w2 >> 26) & 0x3f
        if opcode == 0x0A then -- slti
          local imm = w2 & 0xffff
          table.insert(hits, { imm = imm, addr = aiFuncAddr + off2 })
          off = off2
          break
        end
      end
    end
    off = off + 4
  end
  return hits
end

local ok, err = pcall(function()
  savestate.load("/home/alex/Projects/Suikoden-Bizhawk-HUD/QueenAnt.State")
  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))

  local rowPtrArray = Address.sanitize(mainmemory.read_u32_le(base + PATTACKDATATABLE_OFFSET))
  log(string.format("pAttackDataTable row-pointer array (live) = 0x%08x", rowPtrArray))

  -- slots 6,7,8 = the 3 Soldier Ants; slot 9 = Queen Ant (confirmed formation from earlier work)
  for _, slot in ipairs({ 6, 7, 8, 9 }) do
    local bId = mainmemory.read_u8(base + ENEMYDATA_STRIDE * slot + 0x50)
    local speciesRow = Address.sanitize(mainmemory.read_u32_le(rowPtrArray + bId * 4))
    local aiFuncAddr = mainmemory.read_u32_le(speciesRow + 0x30)
    local hits = findThreshold(base, aiFuncAddr)
    local parts = {}
    for _, h in ipairs(hits) do
      table.insert(parts, string.format("0x%02x(~%d%%)@0x%08x", h.imm, h.imm, h.addr))
    end
    log(string.format("slot %d: bId=%d  aiFunc=0x%08x  thresholds=%s",
      slot, bId, aiFuncAddr, #parts > 0 and table.concat(parts, ", ") or "none found"))
  end
end)

if not ok then log("ERROR: " .. tostring(err)) end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
client.exit()
