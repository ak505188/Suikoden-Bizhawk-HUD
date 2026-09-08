# Static Monster/Boss AI Catalog — investigation history

This is the history behind
[docs/game_mechanics/Monster_AI_Static_Catalog.md](../docs/game_mechanics/Monster_AI_Static_Catalog.md).

## Cross-referencing the disc scan against live memory

The disc-file `MonsterRecord` scan (`scripts/ScanMonsterRecords.py`) and the live-memory
enemy-struct work were originally two separate threads (see `feedback-charmap-text-search.md`
and the battle-system RE progress notes) before being cross-referenced into one area map.

**Live-memory counterpart, confirmed 2026-09-07**: the exact same `MonsterRecord` struct the
scanner finds offline was confirmed reachable live during a real battle, per-slot, with no
file scanning at all — `BattleState.pAttackDataTable[bId]` resolves directly to this same
record, confirmed by decoding its name field live and getting `"Soldier Ant"`/`"Queen Ant"`
back, matching the catalog's own entries exactly.

## Per-area notes

- **`va7.bin` / Varkas**: Varkas's AI address (`0x800103b0`) reusing the plain-Bandit
  routine resolves what was an old "mystery `va7.bin` monster" note from earlier
  reverse-engineering sessions.
- **`vb8.bin`**: confirmed by the user to be the scripted fight for recruiting Anji/Kanak/
  Leonardo — no further digging needed there.
- **`ve2.bin`/`ve5.bin`**: confirmed by the user that `ve5.bin` is Qlon/Cave of the Past's
  own encounter table, and that there's no boss hiding there — nothing further to chase.

## Caveat about compressed/non-flat overlays

The one confirmed exception to the "flat, uncompressed block" assumption is `vc61.bin`
("Dragon") — see `notes/Battle_Damage_Formula.md` for the full dead-end/resolution
investigation into why its AI code doesn't decode at the naive offset.
