local PartyLib = require "PartyLib"

while true do
  gui.text(0, 16, PartyLib.getPartyLVL())
  gui.text(0, 32, PartyLib.isChampionsRuneEquipped() and "ON" or "OFF")
  emu.frameadvance()
end
