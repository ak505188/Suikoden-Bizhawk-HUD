local Utils = require "lib.Utils"

local ANCHOR_POSITIONS = {
  TOP_LEFT = "topleft",
  TOP_RIGHT = "topright",
  BOTTOM_LEFT = "bottomleft",
  BOTTOM_RIGHT = "bottomright"
}

local initialOptsTopLeft = {
  x = 0,
  y = 32,
  gap = 16,
  anchor = ANCHOR_POSITIONS.TOP_LEFT
}

local initialOptsTopRight = {
  x = 0,
  y = 0,
  gap = 16,
  anchor = ANCHOR_POSITIONS.TOP_RIGHT
}

local initialOptsBottomLeft = {
  x = 0,
  y = 0,
  gap = 16,
  anchor = ANCHOR_POSITIONS.BOTTOM_LEFT
}

local initialOptsBottomRight = {
  x = 0,
  y = 0,
  gap = 16,
  anchor = ANCHOR_POSITIONS.BOTTOM_RIGHT
}

local Drawer = {
  anchorOpts = {
    [ANCHOR_POSITIONS.TOP_LEFT] = initialOptsTopLeft,
    [ANCHOR_POSITIONS.TOP_RIGHT] = initialOptsTopRight,
    [ANCHOR_POSITIONS.BOTTOM_LEFT] = initialOptsBottomLeft,
    [ANCHOR_POSITIONS.BOTTOM_RIGHT] = initialOptsBottomRight,
  },
  anchors = ANCHOR_POSITIONS
}

function Drawer:clear()
  gui.cleartext()
  self.anchorOpts[ANCHOR_POSITIONS.TOP_LEFT] = initialOptsTopLeft
  self.anchorOpts[ANCHOR_POSITIONS.TOP_RIGHT] = initialOptsTopRight
  self.anchorOpts[ANCHOR_POSITIONS.BOTTOM_LEFT] = initialOptsBottomLeft
  self.anchorOpts[ANCHOR_POSITIONS.BOTTOM_RIGHT] = initialOptsBottomRight
end

function Drawer:draw(table, anchor, reverse, skip_gap)
  anchor = anchor or ANCHOR_POSITIONS.TOP_LEFT
  reverse = reverse or false
  skip_gap = skip_gap or false

  local opts = self.anchorOpts[anchor]
  local newOpts = Utils.drawTable(table, opts);

  if skip_gap then
    newOpts.y = newOpts.y - newOpts.gap
  end

  self.anchorOpts[anchor] = newOpts
  return newOpts
end

return Drawer
