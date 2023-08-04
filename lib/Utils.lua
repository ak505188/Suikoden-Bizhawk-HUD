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

  if type(str) == "nil" then
    str = "nil"
  elseif (type(str) == "table") then
    str = tableToStr(str)
  end

  if printDebugTable[name].count < printDebugTable[name].max then
    print(name .. " C:" .. printDebugTable[name].count .. "\n" .. str .. "\n")
    printDebugTable[name].count = printDebugTable[name].count + 1
  end
end

local function concatTables(...)
  local tables = {...}

  if #tables <= 1 then return tables end

  repeat
    local t2 = table.remove(tables)
    local t1 = table.remove(tables)

    for i=1, #t2 do
      t1[#t1+1] = t2[i]
    end

    table.insert(tables, t1)
  until #tables == 1

  return table.remove(tables)
end


return {
  drawTable = drawTable,
  cloneTable = cloneTable,
  concatTables = concatTables,
  printDebug = printDebug,
  tableToStr = tableToStr
}
