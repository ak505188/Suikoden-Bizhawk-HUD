local Drawer = require "controllers.drawer"
local PartyChange = require "lib.PartyChange"
local ScreenTeleport = require "lib.ScreenTeleport"

local MESSAGE_FRAMES = 240

local Worker = {}

-- Runs every frame (Toolbox has RunInBackground) so Party Members' queued changes get applied.
function Worker:run()
  PartyChange.tick()
  ScreenTeleport.tick()
end

function Worker:onChange() end

function Worker:init() end

function Worker:draw()
  local lines = {}
  if PartyChange.queuedCount() > 0 then
    table.insert(lines, string.format("Party: applying %d change(s)...", PartyChange.queuedCount()))
  end
  if PartyChange.lastMessage and PartyChange.lastMessageAge() < MESSAGE_FRAMES then
    table.insert(lines, "Party: " .. PartyChange.lastMessage)
  end
  if ScreenTeleport.busy() then
    table.insert(lines, "Teleport: loading...")
  elseif ScreenTeleport.lastMessage and ScreenTeleport.lastMessageAge() < MESSAGE_FRAMES then
    table.insert(lines, "Teleport: " .. ScreenTeleport.lastMessage)
  end
  if #lines > 0 then Drawer:draw(lines, Drawer.anchors.BOTTOM_LEFT) end
end

return Worker
