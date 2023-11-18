local Battle = require "lib.Battle"
local DropTable = require "lib.DropTable"
local Drawer = require "controllers.drawer"
local StateMonitor = require "monitors.State_Monitor"
local Gamestate = require "lib.Enums.Gamestate"
local Address = require "lib.Address"
local Utils = require "lib.Utils"

local Worker = {
  EnemyTablesByAddr = {},
  State = {
    Battle = {},
    EncounterTablePtr = nil,
    EnemyGroupPtr = nil,
  }
}

function Worker:init() end

function Worker:run()
  -- This doesn't work. Need to implement delay
  if StateMonitor.IG_CURRENT_GAMESTATE.current ~= Gamestate.BATTLE then return end

  local is_enemy_group_ptr_valid = Address.isValidPointer(StateMonitor.ENEMY_GROUP_PTR.current)
  local is_encounter_table_ptr_valid = Address.isValidPointer(StateMonitor.ENCOUNTER_TABLE_PTR.current)

  if not (is_enemy_group_ptr_valid and is_encounter_table_ptr_valid) then return end

  self:update()

  if self.DropTable then
    self.DropTable:run()
  end
end

function Worker:onChange() end

function Worker:isUpdateRequired()
  -- TODO: Handle start RNG change
  if not next(self.State.Battle) then return true end
  if self.State.EnemyGroupPtr ~= StateMonitor.ENEMY_GROUP_PTR.current then return true end
  if self.State.EncounterTablePtr ~= StateMonitor.ENCOUNTER_TABLE_PTR.current then return true end
  return false
end

function Worker:draw(table_pos)
  Drawer:draw({ "Drops Module" }, Drawer.anchors.TOP_LEFT, nil, true)
  if StateMonitor.IG_CURRENT_GAMESTATE.current ~= Gamestate.BATTLE then return end
  if not next(self.State.Battle) then return end
  self.DropTable:draw(table_pos)
end

function Worker:update()
  if self:isUpdateRequired() then
    self:updateBattle()
    self.DropTable = DropTable:new(self.State.Battle)
  end
end

function Worker:updateBattle()
  self.State.EnemyGroupPtr = StateMonitor.ENEMY_GROUP_PTR.current
  self.State.EncounterTablePtr = StateMonitor.ENCOUNTER_TABLE_PTR.current

  local enemyGroupAddr = Address.sanitize(self.State.EnemyGroupPtr)
  local encounterTableAddr = Address.sanitize(self.State.EncounterTablePtr)
  local groupSize = memory.read_u8(enemyGroupAddr)

  -- local groupSize = memory.read_u8(enemyGroupAddr)
  local enemies = memory.read_bytes_as_array(enemyGroupAddr + 4, 6)

  local EnemyTable = self.EnemyTablesByAddr[encounterTableAddr]
  if not EnemyTable then
    EnemyTable = Battle.readEnemyTable(encounterTableAddr)
    self.EnemyTablesByAddr[encounterTableAddr] = EnemyTable
  end

  local battleStruct = {
    Enemies = {},
    GroupSize = groupSize,
  }

  local slot = 1
  local count = 1
  while count <= #enemies and slot < 7 do
    local enemy_index = enemies[slot]
    -- print("EI:" .. enemy_index)
    if enemy_index ~= 0 then
      local enemy = EnemyTable[enemy_index]
      Utils.printDebug("Enemy", enemy, 6)
      battleStruct.Enemies[count] = enemy
      count = count + 1
    end
    slot = slot + 1
  end

  self.State.Battle = battleStruct
end

return Worker
