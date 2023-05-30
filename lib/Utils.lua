local function drawTable(strs, opts)
  local x = opts.x or 0
  local y = opts.y or 0
  local gap = opts.gap or 16
  local anchor = opts.anchor or "topleft"
  local reverse = opts.reverse or false

  if reverse then
    for i = #strs, 1, -1 do
      gui.text(x, y, strs[i], nil, anchor)
      y = y + gap
    end
  else
    for _,row in ipairs(strs) do
      gui.text(x, y, row, nil, anchor)
      y = y + gap
    end
  end
  return {
    x = x,
    y = y + gap,
    gap = gap,
    anchor = anchor,
    reverse = reverse
  }
end

local function cloneTable(t)
  return { table.unpack(t) }
end

return {
  drawTable = drawTable,
  cloneTable = cloneTable
}
