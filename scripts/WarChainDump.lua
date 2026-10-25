-- War battle chain oracle: plays a list of commands from KwandaWBT1.State (natural seed, natural
-- enemy picks) and writes every frame (RNG, round globals, sprites, fx, arrows) to a binary file in the
-- format read by scripts/python/WarDump.py, plus a text log of per-round facts. Output: Lua/Output/WarChain_<tag>.bin/.txt
package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local STATE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/KwandaWBT1.State"
-- true: apply scripts/WarPsnPatch.lua after every state load, so the recording behaves like the PSN build (compare with --psn)
local PSN_PATCH = false
local OUTDIR = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/"
-- {tag, seed or nil, {{category, groupId or unitIdx}, ...}}  (category 3 = Others; unit chosen by list index)
-- {tag, seed or nil, commands, patch or nil, forced first enemy action or nil}; a command is {category, unitIndex} for Charge/Bow/Magic or {3, groupId}
-- for Others (the unit is picked by group id from the offered list). patch = {ids made available}.
local RUNS = {
  {"chainA", nil, {{0,0},{0,0},{0,0},{0,0},{0,0},{0,0}}, nil},
  {"chainB", nil, {{1,0},{2,0},{0,0},{1,0},{2,0},{0,0}}, nil},
  {"chainM", nil, {{0,0},{3,35},{0,0},{3,35}}, {31, 101, 102}},
  {"chainD", nil, {{0,0},{3,34},{0,0}}, {10, 35, 34}},
  {"chainD2", nil, {{0,0},{2,0},{3,34},{1,0}}, {10, 35, 34}},
  {"chainS", nil, {{0,0},{3,32},{0,0},{3,24},{1,0},{3,33},{2,0}}, {54, 29, 62, 21}},
  -- random chains: seed + commands (first unit of the category, or an Others group id)
  {"rnd0", 0x6aa79988, {{0,0},{0,0},{1,0},{3,24},{2,0},{3,35},{3,24},{0,0},{0,0}}, {54,29,62,21,31,101,102,10,35,34}},
  {"rnd1", 0xb80e3b0e, {{3,33},{0,0},{0,0},{2,0},{0,0},{3,24},{0,0},{1,0},{1,0}}, {54,29,62,21,31,101,102,10,35,34}},
  {"rnd2", 0x3764b52f, {{0,0},{1,0},{0,0},{3,32},{0,0},{3,33},{1,0},{2,0},{0,0}}, {54,29,62,21,31,101,102,10,35,34}},
  -- single rounds, every matchup (the enemy action is forced: 0 C12, 2 B11, 3 M12, 4 C25)
  {"c_c", 0x12345678, {{0,0}}, nil, 4}, {"c_b", 0x12345678, {{0,0}}, nil, 2}, {"c_m", 0x12345678, {{0,0}}, nil, 3},
  {"b_c", 0x12345678, {{1,0}}, nil, 0}, {"b_b", 0x12345678, {{1,0}}, nil, 2}, {"b_m", 0x12345678, {{1,0}}, nil, 3},
  {"m_c", 0x12345678, {{2,0}}, nil, 0}, {"m_b", 0x12345678, {{2,0}}, nil, 2},
  {"m_m_win", 0x9493a683, {{2,0}}, nil, 3}, {"m_m_lose", 0x7ff8a683, {{2,0}}, nil, 3},
}
local GLOBALS = {
  {"phase", 0xa7760, 1}, {"state", 0xa77a8, 1}, {"next", 0xa77d0, 1}, {"timer", 0xa74d8, 2}, {"a74d0", 0xa74d0, 1},
  {"alive0", 0xa7738, 2}, {"alive1", 0xa773a, 2}, {"cap0", 0xa7758, 2}, {"cap1", 0xa775a, 2},
  {"kill0", 0xa73f0, 1}, {"kill1", 0xa73f1, 1}, {"k8", 0xa73f8, 1}, {"k9", 0xa73f9, 1}, {"a7400", 0xa7400, 1},
  {"drift", 0xa7768, 2}, {"pcnt", 0xa7680, 2}, {"ecnt", 0xa7682, 2}, {"lossP", 0xa7488, 4}, {"lossE", 0xa7490, 4},
  {"fxcnt", 0xa7518, 4}, {"arrcnt", 0xa77c0, 2}, {"a76b8", 0xa76b8, 1}, {"a74e8", 0xa74e8, 2}, {"a74f0", 0xa74f0, 1},
  {"a7498", 0xa7498, 1}, {"a7690", 0xa7690, 1}, {"a7408", 0xa7408, 1}, {"a7694", 0xa7694, 4}, {"a75b0", 0xa75b0, 1}, {"a7700", 0xa7700, 1},
  {"unit", 0xa77a0, 1}, {"cat", 0xa76e8, 1}, {"enemyIdx", 0xa76d0, 1}, {"turns", 0xa7692, 1}, {"a76a8", 0xa76a8, 1},
}
local function press(btn, n)
  for _ = 1, (n or 4) do joypad.set({[btn] = true}); emu.frameadvance() end
  for _ = 1, 10 do emu.frameadvance() end
end
local function wait(n) for _ = 1, n do emu.frameadvance() end end
local function r8(a) return mainmemory.read_u8(a) end
local function ru(a, size)
  if size == 1 then return mainmemory.read_u8(a) elseif size == 2 then return mainmemory.read_u16_le(a) else return mainmemory.read_u32_le(a) end
end
local function ptrRead(ptr, n)
  if ptr < 0x80000000 or ptr >= 0x80200000 then return string.rep("\0", n) end
  local t = memory.read_bytes_as_array(ptr & 0x1fffff, n, "MainRAM")
  return string.char(table.unpack(t))
end
local function w32(fh, v) fh:write(string.pack("<I4", v & 0xffffffff)) end
local function menuReady() return r8(0xa7760) == 2 and r8(0xa76a8) == 2 end

pcall(client.speedmode, 6400)
for _, run in ipairs(RUNS) do
  local tag, seed, cmds, patch, forceEnemy = run[1], run[2], run[3], run[4], run[5]
  savestate.load(STATE)
  if PSN_PATCH then require("scripts.WarPsnPatch").apply() end
  if seed then mainmemory.write_u32_le(0x9010, seed) end
  for _, id in ipairs(patch or {}) do mainmemory.write_u8(0x18ebb0 + id, 0xff) end
  if forceEnemy then mainmemory.write_u8(0xa76d0, forceEnemy) end
  wait(5)
  local fh = io.open(OUTDIR .. "WarChain_" .. tag .. ".bin", "wb")
  local log = {}
  local cap0, cap1 = mainmemory.read_u16_le(0xa7758), mainmemory.read_u16_le(0xa775a)
  local fxcnt = mainmemory.read_u32_le(0xa7518)
  fh:write("WAD1"); w32(fh, mainmemory.read_u32_le(0x9010)); w32(fh, cap0); w32(fh, cap1); w32(fh, fxcnt); w32(fh, #GLOBALS)
  local frame = 0
  local function dumpFrame()
    frame = frame + 1
    w32(fh, frame); w32(fh, mainmemory.read_u32_le(0x9010))
    for _, g in ipairs(GLOBALS) do w32(fh, ru(g[2], g[3])) end
    local sprites = mainmemory.read_u32_le(0xa76b0)
    local p0, p1 = mainmemory.read_u32_le(sprites & 0x1fffff), mainmemory.read_u32_le((sprites & 0x1fffff) + 4)
    fh:write(ptrRead(p0, cap0 * 28)); fh:write(ptrRead(p1, cap1 * 28))
    fh:write(ptrRead(mainmemory.read_u32_le(0xa7648), fxcnt * 28))
    fh:write(ptrRead(mainmemory.read_u32_le(0xa7650), 30 * 32))
    fh:write(ptrRead(mainmemory.read_u32_le(0xa7778), 25 * 28))
  end
  for turn, cmd in ipairs(cmds) do
    if not menuReady() then log[#log+1] = "menu not ready, stop"; break end
    log[#log+1] = string.format("turn %d: enemyIdx=%d used=%d%d%d%d%d p=%d e=%d rng=%08x", turn, r8(0xa76d0), r8(0xa7458), r8(0xa7459), r8(0xa745a), r8(0xa745b), r8(0xa745c),
      mainmemory.read_u16_le(0xa7680), mainmemory.read_u16_le(0xa7682), mainmemory.read_u32_le(0x9010))
    for _ = 1, cmd[1] do press("P1 D-Pad Down") end
    press("P1 X"); wait(60)
    local idx = cmd[2]
    if cmd[1] == 3 then
      idx = -1
      for i = 0, r8(0xa73d0) - 1 do if r8(0xa7658 + i) == cmd[2] then idx = i end end
      log[#log+1] = "others list count=" .. r8(0xa73d0) .. " idx=" .. idx
    end
    for _ = 1, idx do press("P1 D-Pad Down") end
    press("P1 X"); wait(60)
    press("P1 X")
    for f = 1, 9000 do
      if f % 24 == 0 and not menuReady() then joypad.set({["P1 X"] = true}) end
      emu.frameadvance()
      dumpFrame()
      if f > 40 and menuReady() then break end
      if r8(0xa7760) >= 5 and r8(0xa7760) ~= 9 and f > 5 then log[#log+1] = string.format("battle end phase %d result %d", r8(0xa7760), r8(0xa76d8)); break end
    end
    if r8(0xa7760) >= 5 then break end
  end
  fh:close()
  local lf = io.open(OUTDIR .. "WarChain_" .. tag .. ".txt", "w"); lf:write(table.concat(log, "\n"), "\n"); lf:close()
end
client.exit()
