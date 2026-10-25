-- Start a specific battle from a field screen or the world map by driving the game's own encounter path.
-- Method and validation: notes/Battles_and_Encounters.md ("forcing a random-encounter group from Lua").
--
-- field_check_random_encounter skips its rolls when the field context's +0x37 bit 2 is set (the script opcode at
-- 0x801394d0 sets it through FUN_8012cbbc). The battle loader (0x800ddf98) then reads two words of the save struct:
-- +0x1bb4 = the encounter table pointer and +0x1bc0 = the 1-based group index in that table. Both tables live in the
-- area overlay, so the area has to be loaded first: request() can teleport there with lib/ScreenTeleport.lua.
-- Without the overlay the loader freezes (gamestate 3, group pointer never set): each enemy record points into it.
--
-- Two table sources, matching the two ways the game starts a fight:
--   random   (default): the room's own random-encounter table, room+0x38 -> block+4. group = the same index
--            field_pick_encounter_group would roll (the digit strings in lib/EncounterTable.lua).
--   scripted: opts.scripted = B, the script byte of the game's "start battle" opcode. The table is
--            list[B + u32(room+0x1c)], list = u32(room+0x20). Mt. Seifu's Queen Ant room (0/6/9): B=0 is the Queen
--            Ant fight with three Soldier Ants, B=1 the self-playing story battle.
--
-- World map (gamestate 1): a different scene. The WM main handler (scene slot 1 = Functions.WM_MAIN_RUNNING) rolls
-- the encounter itself; on a hit it writes the group index to +0x1bc0 and installs wm_battle_start
-- (Functions.WM_BATTLE_START) as slot 1. That handler takes the table from the WM context
-- (**(u32(*(WM_CTX_PTR)+0x2c)+0xc)), sets PREV_GAMESTATE 1 and GAMESTATE 3, and the dispatcher enters the battle
-- loader. So here the trigger is just those two writes while the map is idle. Only the region's random table exists.
--
-- Queued API, like ScreenTeleport: request(opts), then call tick() once per emulated frame (it also ticks
-- ScreenTeleport while the teleport runs, so do not tick that yourself).
--   opts = { group = 1, scripted = nil | B, wm=, area=, screen=, x=, y= }  (wm/area/screen/x/y omitted = stay on the
--   current screen or the world map, which must be idle; the teleport needs a field screen)
-- On success lastResult = { groupSize = n, slots = { 6 enemy slot indexes }, table = KSEG0 pointer }.
local Address = require "lib.Address"
local Functions = require "lib.AddressFunctions"
local Charmap = require "lib.Charmap"
local ScreenTeleport = require "lib.ScreenTeleport"

local ForceBattle = {}

local ENTER_TIMEOUT = 120 -- frames for the gamestate to become BATTLE after the write
local LOAD_TIMEOUT = 600 -- frames for the battle loader to publish the group pointer
local BATTLE = 3
-- Save struct slots the battle loader reads, at fixed offsets from GAMESTATE_BASE (the game state did not move between builds).
local SAVE_TABLE_PTR = 0x1bb4
local SAVE_GROUP_INDEX = 0x1bc0

ForceBattle.lastMessage = nil
ForceBattle.lastResult = nil
ForceBattle.lastMessageFrame = 0
local tickCount, lastFrame = 0, -1
local job

local function say(msg)
  ForceBattle.lastMessage = msg
  ForceBattle.lastMessageFrame = tickCount
end

local function finish(msg) say(msg); job = nil end

-- Area overlay data starts at 0x80010000, so the stricter-than-needed Address.isValidPointer floor is lower here.
local function overlayPtr(addr)
  local p = memory.read_u32_le(addr)
  if p < 0x80010000 or not Address.isValidPointer(p) then return nil end
  return p
end

local function ctxBase()
  local p = memory.read_u32_le(Address.FIELD_CTX_PTR)
  if p < 0x80100000 or not Address.isValidPointer(p) then return nil end
  return Address.sanitize(p)
end

local WORLD_MAP = 1

local MAX_GROUPS = 32 -- sanity cap: anything above is not a real table
local MAX_SCRIPTED = 32

local function roomBase()
  local p = overlayPtr(Address.ROOM_RECORD_PTR)
  return p and Address.sanitize(p)
end

-- True while the world map is loaded and idle (scene slot 1 holds the WM main handler).
local function onWorldMap()
  return memory.read_u8(Address.GAMESTATE) == WORLD_MAP
    and memory.read_u32_le(Address.SCENE_HANDLER_FIELD_MAIN) == Functions.WM_MAIN_RUNNING
end

-- The world-map region's encounter table (KSEG0) or nil + reason: **(u32(*(WM_CTX_PTR)+0x2c)+0xc).
local function worldMapTable()
  local ctx = overlayPtr(Address.WM_CTX_PTR)
  local region = ctx and overlayPtr(Address.sanitize(ctx) + 0x2c)
  local holder = region and overlayPtr(Address.sanitize(region) + 0xc)
  local tbl = holder and overlayPtr(Address.sanitize(holder))
  if not tbl then return nil, "no world map encounter table" end
  return tbl
end

-- The room's random-encounter table (KSEG0) or nil + reason; also the block's rate and grace.
local function randomTable(room)
  local block = overlayPtr(room + 0x38)
  if not block then return nil, "room has no random encounter block" end
  block = Address.sanitize(block)
  local tbl = overlayPtr(block + 4)
  if not tbl then return nil, "encounter block has no table" end
  return tbl, memory.read_u8(block), memory.read_u8(block + 2)
end

-- Scripted table for script byte B (list[B + u32(room+0x1c)], list = u32(room+0x20)), or nil + reason.
local function scriptedTable(room, b)
  local list = overlayPtr(room + 0x20)
  if not list then return nil, "room has no scripted table list" end
  local index = b + memory.read_u32_le(room + 0x1c)
  local tbl = overlayPtr(Address.sanitize(list) + index * 4)
  if not tbl then return nil, string.format("scripted table %d (list entry %d) is not a pointer", b, index) end
  return tbl
end

-- Group list of a table: returns its address (the u32 count, then one group pointer per entry) and the count, or nil.
local function groupList(tbl)
  local groups = overlayPtr(Address.sanitize(tbl) + 8)
  if not groups then return nil end
  groups = Address.sanitize(groups)
  local count = memory.read_u32_le(groups)
  if count < 1 or count > MAX_GROUPS then return nil end
  return groups, count
end

-- Resolves the encounter table pointer (KSEG0) and group pointer for opts, or nil + reason.
local function resolveTable(opts)
  local tbl, why
  if opts.worldMap then
    if opts.scripted then return nil, "no scripted battles on the world map" end
    tbl, why = worldMapTable()
  else
    local room = roomBase()
    if not room then return nil, "no room record" end
    if opts.scripted then tbl, why = scriptedTable(room, opts.scripted) else tbl, why = randomTable(room) end
  end
  if not tbl then return nil, why end
  local groups, count = groupList(tbl)
  if not groups then return nil, "table has no group list" end
  if opts.group < 1 or opts.group > count then
    -- the loader would silently fall back to group 1, so refuse instead
    return nil, string.format("group %d out of range (table has %d)", opts.group, count)
  end
  local group = overlayPtr(groups + opts.group * 4)
  if not group then return nil, "group record is not a pointer" end
  return tbl, group
end

-- Enemy names of one group, "Name xN" collapsed in first-appearance order, plus the enemy count. The enemy record
-- pointer array is table+0xc (1-based, like the slot bytes at group+4..9); a record starts with the charmap name.
local function describeGroup(tbl, group)
  local records = overlayPtr(Address.sanitize(tbl) + 0xc)
  local size, order, counts, labels = memory.read_u8(group), {}, {}, {}
  for i = 0, 5 do
    local slot = memory.read_u8(group + 4 + i)
    if slot ~= 0 then
      if not counts[slot] then
        local name, level = "?", 0
        local rec = records and overlayPtr(Address.sanitize(records) + slot * 4)
        if rec then
          rec = Address.sanitize(rec)
          name = Charmap.readStringFromList(memory.read_bytes_as_array(rec, 15), 1, 15) or "?"
          level = memory.read_u8(rec + 0x10) -- low byte of the big-endian LVL pair
        end
        -- Several enemies share a displayed name (Bandit R/Y/G), so the level helps tell the records apart.
        labels[slot] = string.format("%s Lv%d", name, level)
        counts[slot] = 0
        order[#order + 1] = slot
      end
      counts[slot] = counts[slot] + 1
    end
  end
  local parts = {}
  for _, slot in ipairs(order) do
    parts[#parts + 1] = counts[slot] > 1 and string.format("%s x%d", labels[slot], counts[slot]) or labels[slot]
  end
  return table.concat(parts, ", "), size
end

-- Every battle the current screen can start: { random = { rate=, grace= } | nil, entries = { { kind = "random" |
-- "scripted", group = n, scripted = B | nil, size = n, text = "Soldier Ant x6" }, ... } }, or nil + reason when no
-- room is loaded. Scripted tables are listed while the table list holds plausible tables (so a screen with none gives
-- an empty list). Random tables are per screen, not per area: grace and rate are too.
function ForceBattle.list()
  local result = { entries = {} }
  local room = roomBase()
  if onWorldMap() then
    local tbl, why = worldMapTable()
    if not tbl then return nil, why end
    result.worldMap = true
    local groups, count = groupList(tbl)
    for g = 1, groups and count or 0 do
      local group = overlayPtr(groups + g * 4)
      if not group then break end
      local text, size = describeGroup(tbl, Address.sanitize(group))
      result.entries[#result.entries + 1] = { kind = "random", group = g, size = size, text = text }
    end
    return result
  end
  if not room then return nil, "no room record" end
  local function add(kind, b, tbl)
    local groups, count = groupList(tbl)
    if not groups then return false end
    for g = 1, count do
      local group = overlayPtr(groups + g * 4)
      if not group then return false end
      local text, size = describeGroup(tbl, Address.sanitize(group))
      result.entries[#result.entries + 1] = { kind = kind, group = g, scripted = b, size = size, text = text }
    end
    return true
  end
  local tbl, rate, grace = randomTable(room)
  if tbl and add("random", nil, tbl) then result.random = { rate = rate, grace = grace } end
  for b = 0, MAX_SCRIPTED - 1 do
    local t = scriptedTable(room, b)
    if not (t and add("scripted", b, t)) then break end
  end
  return result
end

-- True on an idle field screen or the idle world map (the places request() can start from).
function ForceBattle.ready() return ScreenTeleport.ready() or onWorldMap() end

-- Returns true if queued; false + reason otherwise.
function ForceBattle.request(opts)
  opts = opts or {}
  if job then return false, "a forced battle is already running" end
  if ScreenTeleport.busy() then return false, "a teleport is already running" end
  local group = opts.group or 1
  local teleport = opts.wm ~= nil
  local worldMap = false
  if teleport then
    if opts.area == nil or opts.screen == nil or opts.x == nil or opts.y == nil then
      return false, "wm needs area, screen, x and y too"
    end
    local ok, why = ScreenTeleport.request(opts.wm, opts.area, opts.screen, opts.x, opts.y)
    if not ok then return false, why end
  elseif ScreenTeleport.ready() then
    worldMap = false
  elseif onWorldMap() then
    worldMap = true
  else
    return false, "not in a field screen or on the world map"
  end
  job = { group = group, scripted = opts.scripted, worldMap = worldMap, step = teleport and "teleport" or "arm", ticks = 0 }
  return true
end

function ForceBattle.busy() return job ~= nil end
function ForceBattle.lastMessageAge() return tickCount - ForceBattle.lastMessageFrame end

function ForceBattle.tick()
  -- Menus call worker:run() in a tight loop while paused; only act on real emulated frames.
  local frame = emu.framecount()
  if frame == lastFrame then return end
  lastFrame = frame
  tickCount = tickCount + 1
  if not job then return end
  job.ticks = job.ticks + 1

  if job.step == "teleport" then
    ScreenTeleport.tick()
    if not ScreenTeleport.busy() then
      local msg = ScreenTeleport.lastMessage or "?"
      if msg:sub(1, 6) ~= "loaded" then return finish("FAILED teleport: " .. msg) end
      job.step, job.ticks = "arm", 0
    end
  elseif job.step == "arm" then
    local base = ctxBase()
    if job.worldMap then
      if not onWorldMap() then return finish("FAILED: world map not idle") end
    elseif not base or not ScreenTeleport.ready() then
      return finish("FAILED: field not idle")
    end
    local tbl, group = resolveTable(job)
    if not tbl then return finish("FAILED: " .. group) end
    job.expectedGroup = group
    memory.write_u32_le(Address.GAMESTATE_BASE + SAVE_GROUP_INDEX, job.group)
    if job.worldMap then
      -- wm_battle_start copies the table pointer to +0x1bb4 itself
      memory.write_u32_le(Address.SCENE_HANDLER_FIELD_MAIN, Functions.WM_BATTLE_START)
    else
      memory.write_u32_le(Address.GAMESTATE_BASE + SAVE_TABLE_PTR, tbl)
      memory.write_u8(base + 0x37, memory.read_u8(base + 0x37) | 4)
      memory.write_u8(Address.ENCOUNTER_ARMED, 1)
      memory.write_u8(base + 0x36, 1)
    end
    job.table, job.step, job.ticks = tbl, "wait", 0
  else
    if memory.read_u8(Address.GAMESTATE) == BATTLE then
      local groupPtr = memory.read_u32_le(Address.ENEMY_GROUP_PTR)
      if groupPtr == job.expectedGroup and overlayPtr(Address.ENCOUNTER_TABLE_PTR) then
        local at = Address.sanitize(groupPtr)
        local slots = {}
        for i = 0, 5 do slots[#slots + 1] = memory.read_u8(at + 4 + i) end
        ForceBattle.lastResult = { groupSize = memory.read_u8(at), slots = slots, table = job.table }
        return finish(string.format("battle started: group %d, %d enemies", job.group, ForceBattle.lastResult.groupSize))
      end
      if job.ticks > LOAD_TIMEOUT then
        return finish("FAILED: battle never finished loading (loader stuck; area overlay not loaded?)")
      end
    elseif job.ticks > ENTER_TIMEOUT then
      return finish("FAILED: the game never entered a battle")
    end
  end
end

return ForceBattle
