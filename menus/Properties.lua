local MENU_TYPES = {
  base = 'BASE',
  module = 'MODULE',
  custom = 'CUSTOM',
  module_menu = 'MODULE MENU',
  tool = 'TOOL',
  tool_menu = 'TOOL MENU',
}

local CONTROL_TYPES = {
  cursor = 'CURSOR',
  buttons = 'BUTTONS',
  scrolling_cursor = 'SCROLLING_CURSOR',
}

local ENTRY_TYPES = {
  select = 'Select',
  edit = 'Edit'
}

return {
  CONTROL_TYPES = CONTROL_TYPES,
  ENTRY_TYPES = ENTRY_TYPES,
  MENU_TYPES = MENU_TYPES,
}
