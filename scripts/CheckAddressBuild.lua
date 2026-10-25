-- Live check of the build-aware address files on whatever savestate is loaded here: prints the detected build, a few
-- table/global values and whether ActionEnumerator / BattleSnapshot still read a battle. Output: Lua/Output/CheckAddressBuild.txt
package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local STATE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/ZombieDragonStart.State"
local out = io.open("/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckAddressBuild.txt", "w")
local function log(...) out:write(string.format(...) .. "\n"); out:flush() end
local Address = require "lib.Address"
local Tables = require "lib.AddressTables"
local Functions = require "lib.AddressFunctions"
log("before load: build %s", Address.build())
savestate.load(STATE)
for _ = 1, 60 do emu.frameadvance() end
log("after load: build %s (probe word %08x)", Address.build(), mainmemory.read_u32_le(0x1508ec))
log("BATTLE_STATE_PTR %06x -> %08x, MONEY %d, RUNE table %06x first ptr %08x, FIGHT_MENU_HANDLER %08x",
    Address.BATTLE_STATE_PTR, mainmemory.read_u32_le(Address.BATTLE_STATE_PTR), mainmemory.read_u32_le(Address.MONEY),
    Tables.RUNE_ABILITY_SET_TABLE, mainmemory.read_u32_le(Tables.RUNE_ABILITY_SET_TABLE + 4), Functions.FIGHT_MENU_HANDLER)
local ActionEnumerator = require "lib.ActionEnumerator"
local ctx, why = ActionEnumerator:readBattleContext()
log("ActionEnumerator.readBattleContext: %s %s", tostring(ctx ~= nil), tostring(why))
local ok, BattleSnapshot = pcall(require, "lib.BattleSnapshot")
log("BattleSnapshot loads: %s", tostring(ok))
local PartyChange = require "lib.PartyChange"
log("PartyChange.FN.claimSlot %08x, cdSync %08x", PartyChange.FN.claimSlot, PartyChange.FN.cdSync)
local SEC = require "lib.SoulEaterCapture"
log("SoulEaterCapture BlackShadow handler %08x", SEC.RECIPES.BlackShadow.handler)
log("done")
out:close()
client.exit()
