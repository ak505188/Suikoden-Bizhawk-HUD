local function writeToTableUsingKeylist(tbl, keys, value)
  if #keys == 1 then
    tbl[keys[1]] = value
  else
    local key = table.remove(keys, 1)
    writeToTableUsingKeylist(tbl[key], keys, value)
  end
end

return {
  writeToTableUsingKeylist = writeToTableUsingKeylist
}
