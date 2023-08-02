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

local function tableToStr(o)
  if type(o) == 'table' then
    local s = '{ '
    for k,v in pairs(o) do
      if type(k) ~= 'number' then k = '"'..k..'"' end
      s = s .. '['..k..'] = ' .. tableToStr(v) .. ','
    end
    return s .. '} '
  else
    return tostring(o)
  end
end

local printDebugTable = {}

-- Prints a limited amount of times, so you don't infinite loop prints
local function printDebug(name, str, max)
  if printDebugTable[name] == nil then
    printDebugTable[name] = {}
    printDebugTable[name].max = max or 1
    printDebugTable[name].count = 0
  end

  if printDebugTable[name].count < printDebugTable[name].max then
    print(name .. str)
    printDebugTable[name].count = printDebugTable[name].count + 1
  end
end

return {
  drawTable = drawTable,
  cloneTable = cloneTable,
  printDebug = printDebug,
  tableToStr = tableToStr
}
