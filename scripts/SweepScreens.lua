-- HEADLESS ONLY. For each target screen (global SWEEP_TARGETS_FILE -> Lua table list of {wm,area,screen,ns,
-- action,...}): load InvisVikiOutsideRoom.State, optionally force one NPC hidden (action = violate one clause of
-- its condition), write the zone triple, set the "leaving screen" flag so the game runs its own teardown + load
-- chain, then record where the 16 KB texture buffer (queue dest ptr 0x80178F78) and the room table landed and the
-- table's slot bytes. One TSV-ish line per target in the output file.
package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local OUT = SWEEP_OUT or "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/SweepScreens.txt"
local START = SWEEP_START or "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/InvisVikiOutsideRoom.State"
local f = io.open(OUT, "w"); f:close()
local function log(s) local h = io.open(OUT, "a"); h:write(s .. "\n"); h:close() end
pcall(function() client.speedmode(6400) end)
local targets = dofile(SWEEP_TARGETS_FILE)
local function hex8(a) local t = {} for i = 0, 7 do t[#t + 1] = string.format("%02x", memory.read_u8(a + i)) end return table.concat(t, "") end

for ti, t in ipairs(targets) do
  local ok, err = pcall(function()
    savestate.load(START)
    for _ = 1, 4 do emu.frameadvance() end
    local base = memory.read_u32_le(0x17be20) & 0x1fffff
    if t.action then
      local a = t.action.addr & 0x1fffff
      local v = memory.read_u8(a)
      if t.action.op == "clear" then v = v & (~t.action.mask & 0xff) else v = v | t.action.mask end
      memory.write_u8(a, v)
    end
    local function writeZones() memory.write_u8(0x1b8000, t.area); memory.write_u8(0x1b8001, t.screen); memory.write_u8(0x1b8002, t.wm) end
    if SWEEP_SAME_OVERLAY then
      writeZones()
      memory.write_u8(base + 0x34, 1) -- same-overlay screen change: teardown -> field_load_state_A
    else
      -- Full field exit + re-entry (reloads the area overlay): byte +0x34 = change-screen request, +0x35 non-zero
      -- with bit0 clear -> field_main_running takes field_main_exit_field, which sets next scene = field
      -- (gs+0x1BBC = 2); scene_dispatcher then restarts the field with FUN_80130EC4 (overlay load).
      -- Two phases: writing the new zone bytes BEFORE the request made the idle handler hang on some screens (it
      -- indexes per-screen tables with the new zone against the old screen's data), so request the exit first with
      -- the zones untouched and write them one frame later, before FUN_80130EC4 reads them.
      memory.write_u8(base + 0x35, 2); memory.write_u8(base + 0x37, 0); memory.write_u8(base + 0x34, 1)
      emu.frameadvance()
      writeZones()
    end
    local bufFirst, bufLast, idle, frames = 0, 0, 0, 0
    local done = false
    for fr = 1, 1200 do
      emu.frameadvance(); frames = fr
      local d = memory.read_u32_le(0x178f78)
      if d >= 0x80100000 and d < 0x80200000 then if bufFirst == 0 then bufFirst = d end; bufLast = d end
      local h1, h2 = memory.read_u32_le(0x17da94), memory.read_u32_le(0x17da98)
      if fr > 20 and h1 == 0x801319c4 and h2 == 0x80132790 then idle = idle + 1 else idle = 0 end
      if idle >= 10 then done = true; break end
    end
    local ptr = memory.read_u32_le(0x17daa0)
    local ns = memory.read_u8(0x17dbfc)
    local slots = {}
    if done and ptr >= 0x80100000 and ns > 0 and ns < 64 then
      for i = 0, ns - 1 do
        local a = (ptr & 0x1fffff) + i * 0x18
        slots[#slots + 1] = string.format("%d:%02x:%d,%d:%s", i + 1, memory.read_u8(a + 0x14), memory.read_u8(a), memory.read_u8(a + 1), hex8(a))
      end
    end
    log(string.format("T\t%d\t%d\t%d\t%s\tdone=%s\tframes=%d\tzones=%d/%d/%d\thdr=%08x\tns=%d\texp=%d\ttable=%08x\tbufFirst=%08x\tbufLast=%08x\tform=%d\tslots=%s",
      ti, t.wm, t.area, t.screen, tostring(done), frames,
      memory.read_u8(0x1b8002), memory.read_u8(0x1b8000), memory.read_u8(0x1b8001), memory.read_u32_le(0x10000),
      ns, t.ns or -1, ptr, bufFirst, bufLast, memory.read_u8(0x1b8003), table.concat(slots, " ")))
  end)
  if not ok then log("T\t" .. ti .. "\tERR\t" .. tostring(err)) end
end
log("DONE")
client.exit()
