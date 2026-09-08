package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"

local OUT = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/RegisterProbe.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

savestate.load("/home/alex/Projects/Suikoden-Bizhawk-HUD/Dragon.State")

local ok, regs = pcall(function() return emu.getregisters() end)
log("emu.getregisters() ok=" .. tostring(ok))
if ok and type(regs) == "table" then
  for k, v in pairs(regs) do
    log(string.format("  %s = 0x%08x (%d)", tostring(k), v, v))
  end
end

local ok2, err2 = pcall(function() return emu.getregister("v0") end)
log("emu.getregister('v0') ok=" .. tostring(ok2) .. " val=" .. tostring(err2))

local file = io.open(OUT, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
client.exit()
