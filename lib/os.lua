local OS = {
  NAMES = {
    Windows = 'WINDOWS',
    Linux = 'Linux',
  }
}

OS.type = os.getenv("HOME") == nil and OS.NAMES.Windows or OS.NAMES.Linux

function OS.convertPathToWindows(path)
  return path:gsub("/", "\\")
end

function OS.convertPathToLinux(path)
  return path:gsub("\\", "/")
end

function OS:convertPath(path)
  return self.type == self.NAMES.Windows and self.convertPathToWindows(path) or self.convertPathToLinux(path)
end

return OS
