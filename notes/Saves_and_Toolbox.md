# Saves, Character Editor, and Recruitment Editor — notes

This is the history/uncertainty behind
[docs/game_mechanics/Saves_and_Toolbox.md](../docs/game_mechanics/Saves_and_Toolbox.md).

## Recruitment Editor

The lack of a recruitment-state value legend is a documentation gap worth
flagging for anyone extending this tool.

The 108-byte ordering being unverified against disassembly should be
confirmed before being relied on for slot→character mapping.

## Open questions

- IGT address selection remains genuinely unresolved — four candidates
  tried, none confirmed accurate; see the address table in the docs page.
- `getSaveName`'s `-- TODO: Add events using event index and state check` —
  event/cutscene locations aren't distinguished in save naming.
- EXP write endianness inconsistency between `Characters.lua` and
  `lib/Characters/Utils.lua` — see
  [Characters_and_Stats.md](../docs/game_mechanics/Characters_and_Stats.md#character-struct-0x50--80-bytes-relative-to-stats-address).
- No recruitment-state value legend exists anywhere — real reverse
  engineering work still needed if precise state semantics are wanted.
- Recruitment slot ordering is inferred, not confirmed against disassembly.
