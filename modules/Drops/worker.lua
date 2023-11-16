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

  if self:isUpdateRequired() then
    self:updateBattle()
    self.DropTable = DropTable:new(self.State.Battle)
  end

  if self.DropTable then
    self.DropTable:run()
  end
end

function Worker:onChange() end

function Worker:isUpdateRequired()
  -- TODO: Handle start RNG change
  if not next(self.State.Battle) then return true end
  return StateMonitor.ENEMY_GROUP_PTR.changed or StateMonitor.ENCOUNTER_TABLE_PTR.changed
end

function Worker:draw(table_pos)
  Drawer:draw({ "Drops Module" }, Drawer.anchors.TOP_LEFT, nil, true)
  if not next(self.State.Battle) then return end
  self.DropTable:draw(table_pos)
end

function Worker:updateBattle()
  self.State.EnemyGroupPtr = StateMonitor.ENEMY_GROUP_PTR.current
  self.State.EncounterTablePtr = StateMonitor.ENCOUNTER_TABLE_PTR.current

  local enemyGroupAddr = Address.sanitize(self.State.EnemyGroupPtr)
  local encounterTableAddr = Address.sanitize(self.State.EncounterTablePtr)

  -- local groupSize = memory.read_u8(enemyGroupAddr)
  local enemies = memory.read_bytes_as_array(enemyGroupAddr + 4, 6)

  local EnemyTable = self.EnemyTablesByAddr[encounterTableAddr]
  if not EnemyTable then
    EnemyTable = Battle.readEnemyTable(encounterTableAddr)
    self.EnemyTablesByAddr[encounterTableAddr] = EnemyTable
  end

  local battleStruct = {
    Enemies = {}
  }

  for i=1,#enemies,1 do
    battleStruct.Enemies[i] = EnemyTable[enemies[i]]
  end

  self.State.Battle = battleStruct
end

return Worker
