-- https://github.com/xiedacon/lua-fs-module
-- Copyright (c) 2018, xiedacon.

local OS = require "lib.os"

local fs = { _VERSION = "0.1" }

local function popen (command, n)
  if not n then n = 3 end
  local result, err

  for i = 1, n do
    local file = io.popen(command)
    result, err = file:read("*a")
    file:close()

    if err and err == "Interrupted system call" then
    else
      break
    end
  end

  return result, err
end

function fs.read (path, n)
  local content, err = fs.readFile(path)

  if not content then
    if err == "Is a directory" then
      return fs.readdir(path, n)
    else
      return nil, err
    end
  else
    return content
  end
end

function fs.readdir (path, n)
  local content
  if OS.type == OS.NAMES.Linux then
    content = popen(string.format("ls -a '%s'", path), n)
  elseif OS.type == OS.NAMES.Windows then
    content = popen(string.format("dir /B %s", path), n)
  end

  if not content or content == "" then
    return nil, "No such file or directory"
  end

  local dir = {}
  local i = 0
  local start = 1
  while true do
    i = string.find(content, "\n", i + 1)
    if i == nil then
      break
    else
      local file = string.sub(content, start, i - 1)
      start = i + 1

      if file ~= "." and file ~= ".." then
        table.insert(dir, file)
      end
    end
  end

  return dir
end

function fs.readFile (path)
  local file, err = io.open(path)

  if not file then
    return nil, err
  end

  local content, err = file:read("*a")

  if not content then
    file:close()
    return nil, err
  end

  file:close()
  return content, err
end

function fs.writeFile (path, content)
  local file, err = io.open(path, "w+")

  if not file then
    return false, err
  end

  local ok, err = file:write(content)

  if not ok then
    file:close()
    return false, err
  end

  file:close()
  return true, err
end

fs.write = fs.writeFile

fs.appendToFile = function (path, content)
  local file, err = io.open(path, "a")

  if not file then
    return false, err
  end

  local ok, err = file:write(content)

  if not ok then
    file:close()
    return false, err
  end

  file:close()
  return true, err
end

function fs.exists (path)
  local file, err = io.open(path)

  if not file then
    return false
  else
    return true
  end
end

function fs.copy (path1, path2)
  local content, err = fs.read(path1)

  if not content then
    return false, err
  end

  local ok, err = fs.write(path2, content)

  if not ok then
    return false, err
  end

  return true
end

function fs.move (path1, path2)
  local command = OS.type == OS.NAMES.Linux and
    string.format('mv "%s" "%s"', path1, path2) or
    string.format('move "%s" "%s"', path1, path2)
  local ok = os.execute(command)

  if not ok then
    return false, "failed to move " .. path1 .. " to " .. path2
  else
    return true
  end
end

function fs.mkdir (path)
  local arguments = OS.type == OS.NAMES.Linux and '-p ' or ''
  local ok = os.execute(string.format('mkdir %s"%s"', arguments, path))

  if not ok then
    return false, "failed to mkdir " .. path
  else
    return true
  end
end

function fs.rm (path)
  local command = OS.type == OS.NAMES.Linux and
    string.format('rm "%s"', path) or
    string.format('del "%s"', path)
  local ok = os.execute(command)

  if not ok then
    return false, "failed to rm " .. path
  else
    return true
  end
end

fs.remove = fs.rm

function fs.rmdir (path)
  local ok = os.execute("rmdir '" .. path .. "'")

  if not ok then
    return false, "failed to rmdir " .. path
  else
    return true
  end
end

-- Stopped fixing compatability here
function fs.unlink (path)
  local ok = os.execute("unlink '" .. path .. "'")

  if not ok then
    return false, "failed to unlink " .. path
  else
    return true
  end
end

function fs.rmAll (path)
  local ok = os.execute("rm -rf '" .. path .. "'")

  if not ok then
    return false, "failed to rmAll " .. path
  else
    return true
  end
end

fs.removeAll = fs.rmAll

function fs.chown (path, own)
  local ok = os.execute("chown '" .. own .. "' '" .. path .. "'")

  if not ok then
    return false, "failed to chown " .. own .. " " .. path
  else
    return true
  end
end

function fs.chmod (path, mode)
  local ok = os.execute("chmod '" .. tostring(mode) .. "' '" .. path .. "'")

  if not ok then
    return false, "failed to chmod " .. tostring(mode) .. " " .. path
  else
    return true
  end
end

function fs.isDir (path)
  local file = io.open(path)

  if not file then
    return false
  end

  local content, err = file:read(0)
  file:close()

  if not content and err == "Is a directory" then
    return true
  else
    return false
  end
end

function fs.isFile (path)
  local file = io.open(path)

  if not file then
    return false
  end

  local content = file:read(0)
  file:close()

  if not content then
    return false
  else
    return true
  end
end

return fs
