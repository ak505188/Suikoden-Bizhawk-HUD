-- Load any field screen (WM / area / screen) from Lua by driving the game's own screen-change path.
-- Method and validation: docs/game_mechanics/Invisible_Actor_Glitch.md ("all-screens tables"),
-- notes/Invisible_Actor_Glitch.md. Standalone sweep version: scripts/SweepScreens.lua.
--
-- The field's context struct (pointer at 0x17BE20) has a "change screen" request byte at +0x34. Setting
-- +0x35 = 2 (bit 0 clear) and +0x37 = 0 first makes field_main_running take field_main_exit_field, which frees
-- the field and restarts it with the area overlay reloaded, so the target may be in ANY area. The new zone bytes
-- must be written one frame AFTER the request: writing them first hung the idle handler on ~17% of screens.
--
-- The hero arrives at gs+4 / gs+6 (u16 tile X / Y; field_loader_idle copies them to ctx+0x28/+0x2c), which the game's
-- own door scripts set to the destination's door tile. Teleporting without setting them keeps the OLD screen's tile,
-- which can be inside a wall, so request() takes an arrival X/Y (see lib/ScreenList.lua entries).
--
-- Queued API, like PartyChange: request(wm, area, screen, x, y), then call tick() once per emulated frame.
local Address = require "lib.Address"
local Functions = require "lib.AddressFunctions"

local ScreenTeleport = {}

-- Addresses (per build): Address.FIELD_CTX_PTR, Address.SCENE_HANDLER_FIELD_MAIN / _FIELD_LOADER (idx1 field main / idx2 loader
-- scene handlers) and Functions.FIELD_MAIN_RUNNING / FIELD_LOADER_IDLE, the values those two handlers hold when idle.
local START_TIMEOUT = 120 -- frames for the exit request to be consumed
local LOAD_TIMEOUT = 1500 -- frames for the new screen to reach the idle state
local IDLE_FRAMES = 10

ScreenTeleport.lastMessage = nil
ScreenTeleport.lastMessageFrame = 0
local tickCount, lastFrame = 0, -1
local job

local function say(msg)
  ScreenTeleport.lastMessage = msg
  ScreenTeleport.lastMessageFrame = tickCount
end

local function finish(msg) say(msg); job = nil end

local function ctxBase()
  local p = memory.read_u32_le(Address.FIELD_CTX_PTR)
  if p < 0x80100000 or p >= 0x80200000 then return nil end
  return p & 0x1fffff
end

-- True while a field screen is loaded and idle (safe moment to request a change).
function ScreenTeleport.ready()
  return ctxBase() ~= nil and memory.read_u32_le(Address.SCENE_HANDLER_FIELD_MAIN) == Functions.FIELD_MAIN_RUNNING
    and memory.read_u32_le(Address.SCENE_HANDLER_FIELD_LOADER) == Functions.FIELD_LOADER_IDLE
end

function ScreenTeleport.current()
  return memory.read_u8(Address.WM_ZONE), memory.read_u8(Address.AREA_ZONE), memory.read_u8(Address.SCREEN_ZONE)
end

function ScreenTeleport.busy() return job ~= nil end
function ScreenTeleport.lastMessageAge() return tickCount - ScreenTeleport.lastMessageFrame end

-- Returns true if queued; false + reason otherwise.
function ScreenTeleport.request(wm, area, screen, x, y)
  if job then return false, "a teleport is already running" end
  if not ScreenTeleport.ready() then return false, "not in a field screen" end
  job = { wm = wm, area = area, screen = screen, x = x, y = y, step = "request", ticks = 0 }
  return true
end

function ScreenTeleport.tick()
  -- Menus call worker:run() in a tight loop while paused; only act on real emulated frames.
  local frame = emu.framecount()
  if frame == lastFrame then return end
  lastFrame = frame
  tickCount = tickCount + 1
  if not job then return end
  job.ticks = job.ticks + 1

  if job.step == "request" then
    local base = ctxBase()
    if not base then return finish("FAILED teleport: no field context") end
    memory.write_u8(base + 0x35, 2)
    memory.write_u8(base + 0x37, 0)
    memory.write_u8(base + 0x34, 1)
    job.step, job.ticks = "zones", 0
  elseif job.step == "zones" then
    memory.write_u8(Address.AREA_ZONE, job.area)
    memory.write_u8(Address.SCREEN_ZONE, job.screen)
    memory.write_u8(Address.WM_ZONE, job.wm)
    memory.write_u16_le(Address.AREA_ZONE + 4, job.x)
    memory.write_u16_le(Address.AREA_ZONE + 6, job.y)
    job.step, job.ticks, job.idle = "wait", 0, 0
  else
    if job.ticks > 20 and ScreenTeleport.ready() then job.idle = job.idle + 1 else job.idle = 0 end
    if job.idle >= IDLE_FRAMES then
      return finish(string.format("loaded %d/%d/%d", job.wm, job.area, job.screen))
    end
    if job.ticks > LOAD_TIMEOUT then
      return finish(string.format("FAILED %d/%d/%d: never finished loading (screen may not exist)", job.wm, job.area, job.screen))
    end
  end
end

return ScreenTeleport
