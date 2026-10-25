-- Addresses.lua's "Stats" field is confirmed correct and fixed per character (matches the
-- earlier RAM-scan's independently-found record addresses for Pesmerga/Sergei exactly). The
-- user clarified: at new-game start, every one of the 78 characters is initialized directly
-- to Level 1 with their real initial stats (no derivation/RNG involved for level 1 itself) -
-- so any character still untouched (never recruited, never leveled) should show their EXACT
-- Characters.js "initial" stats live, right now, at their Stats address. This checks that
-- directly using lib/Characters/Characters.lua's own confirmed field layout.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Addresses = require "lib.Characters.Addresses"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/ZombieDragonStart.State"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/InitialStatsCheck.txt"

-- Characters.js "initial" stats for characters expected to be untouched (level 1) this early.
local EXPECTED = {
  Pesmerga = {HP=26, PWR=22, SKL=7,  DEF=17, SPD=6,  MGC=3,  LUK=1},
  Sergei   = {HP=20, PWR=7,  SKL=17, DEF=16, SPD=9,  MGC=11, LUK=13},
  Sarah    = {HP=20, PWR=17, SKL=11, DEF=19, SPD=13, MGC=16, LUK=8},
  Rubi     = {HP=20, PWR=14, SKL=13, DEF=12, SPD=17, MGC=18, LUK=1},
  Quincy   = {HP=20, PWR=13, SKL=27, DEF=16, SPD=13, MGC=5,  LUK=14},
  Warren   = {HP=24, PWR=17, SKL=16, DEF=16, SPD=12, MGC=10, LUK=11},
  Stallion = {HP=16, PWR=14, SKL=9,  DEF=13, SPD=19, MGC=10, LUK=13},
}

local function main()
  savestate.load(BASE_SAVE)
  for i = 1, 30 do emu.frameadvance() end

  local lines = {}
  for name, exp in pairs(EXPECTED) do
    local rec = Addresses[name]
    if rec and rec.Stats then
      local addr = rec.Stats
      local id = memory.read_u8(addr + 0x0)
      local hp = memory.read_u16_le(addr + 0x4)
      local lvl = memory.read_u8(addr + 0xd)
      local pwr = memory.read_u8(addr + 0x10)
      local skl = memory.read_u8(addr + 0x11)
      local def = memory.read_u8(addr + 0x12)
      local spd = memory.read_u8(addr + 0x13)
      local mgc = memory.read_u8(addr + 0x14)
      local luk = memory.read_u8(addr + 0x15)

      local got = {HP=hp, PWR=pwr, SKL=skl, DEF=def, SPD=spd, MGC=mgc, LUK=luk}
      local allMatch = true
      for k, v in pairs(exp) do
        if got[k] ~= v then allMatch = false end
      end

      table.insert(lines, string.format(
        "%-10s Id=%-4s lvl=%-3s got={HP=%d,PWR=%d,SKL=%d,DEF=%d,SPD=%d,MGC=%d,LUK=%d} expected={HP=%d,PWR=%d,SKL=%d,DEF=%d,SPD=%d,MGC=%d,LUK=%d} MATCH=%s",
        name, tostring(id), tostring(lvl),
        hp, pwr, skl, def, spd, mgc, luk,
        exp.HP, exp.PWR, exp.SKL, exp.DEF, exp.SPD, exp.MGC, exp.LUK,
        tostring(allMatch)))
    else
      table.insert(lines, name .. ": no Stats address")
    end
  end

  local file, writeErr = io.open(OUTPUT_FILE, "w")
  if file then
    file:write(table.concat(lines, "\n") .. "\n")
    file:close()
  else
    console.log("Failed to write output file: " .. tostring(writeErr))
  end
  for _, l in ipairs(lines) do console.log(l) end
  console.log("DONE")
end

main()
client.exit()
