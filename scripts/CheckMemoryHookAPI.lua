-- Introspects the memory/mainmemory/event Lua tables to find what hook APIs actually exist in
-- this BizHawk build, since memory.registerread doesn't exist (confirmed via
-- TraceMonsterRecord2cRead.lua). No savestate needed - just enumerates function names.

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckMemoryHookAPI.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

local function dumpTable(name, t)
  if type(t) ~= "table" then
    log(name .. " is not a table (type=" .. type(t) .. ")")
    return
  end
  local names = {}
  for k, v in pairs(t) do
    table.insert(names, tostring(k) .. ":" .. type(v))
  end
  table.sort(names)
  log(name .. " has " .. #names .. " entries:")
  for _, n in ipairs(names) do
    log("  " .. n)
  end
end

dumpTable("memory", memory)
dumpTable("mainmemory", mainmemory)
if event then dumpTable("event", event) end
if emu then dumpTable("emu", emu) end

local f = io.open(OUTPUT_FILE, "w")
if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
client.exit()
