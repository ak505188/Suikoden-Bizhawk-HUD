-- Build handling shared by lib/Address.lua, lib/AddressTables.lua and lib/AddressFunctions.lua.
--
-- Two builds of the US game exist and their main.exe layouts differ:
--   "v1.1": the disc image BizHawk normally runs (the values in every V11 table);
--   "v1.0": the original disc, which is also what the PSN release runs (the PSTV).
-- Each address file keeps a V11 table (all entries) and a V10 table (only the entries that moved), and wraps them with
-- AddressBuild.wrap(). The build is detected once from a word of main.exe code, then every wrapped table is filled with
-- plain fields for that build. Until the game's memory can be read the v1.1 values are returned and nothing is cached,
-- so a script started before the game has booted does not lock in the wrong build. Do not copy an address into a
-- module-level local at require time for the same reason; read it from the table where it is used.
local AddressBuild = {}

-- A word of main.exe code that differs between the builds (0x1508ec: v1.1 has the start of rcos, v1.0 another function).
local BUILD_PROBE = 0x1508ec
local BUILD_BY_WORD = { [0x04810002] = "v1.1", [0xafbf0018] = "v1.0" }

local build -- nil until known
local wrapped = {}

local function detect()
  if not (mainmemory and mainmemory.read_u32_le) then return nil end
  local ok, word = pcall(mainmemory.read_u32_le, BUILD_PROBE)
  return ok and BUILD_BY_WORD[word] or nil
end

local function apply(name)
  build = name
  for _, w in ipairs(wrapped) do
    for k, v in pairs(w.v11) do rawset(w.table, k, v) end
    if name == "v1.0" then
      for k, v in pairs(w.v10) do rawset(w.table, k, v) end
    end
  end
end

-- "v1.1" or "v1.0". Until the game's memory can be read the answer is "v1.1" and nothing is cached.
function AddressBuild.build()
  if build then return build end
  local found = detect()
  if found then apply(found) end
  return found or "v1.1"
end

-- Forces a build (offline tests, or a savestate whose memory is not loaded yet).
function AddressBuild.setBuild(name)
  assert(name == "v1.1" or name == "v1.0", "unknown build " .. tostring(name))
  apply(name)
end

-- Returns the table to use as the address file's module table: Address.NAME reads the value for the running build.
-- v10 holds only what differs from v11 (value = the v1.0 address).
function AddressBuild.wrap(v11, v10)
  local t = {}
  t.build, t.setBuild = AddressBuild.build, AddressBuild.setBuild
  wrapped[#wrapped + 1] = { table = t, v11 = v11, v10 = v10 }
  if build then apply(build) end
  return setmetatable(t, {
    __index = function(_, key)
      local name = AddressBuild.build() -- fills every wrapped table once the build is known
      local v = rawget(t, key)
      if v ~= nil then return v end
      return (name == "v1.0" and v10[key]) or v11[key]
    end,
  })
end

return AddressBuild
