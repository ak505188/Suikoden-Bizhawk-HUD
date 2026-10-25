# AIStaticChecks

66 `Check<Monster>AI.lua` scripts, one per regular-encounter monster AI that was decompiled
statically in Ghidra (no live capture). The findings (target-scan shape, move gate, special
script address) are in `docs/game_mechanics/Battle_Damage_Formula.md`, "Full regular-enemy AI
sweep", and 37 of the simple ones are modelled in `lib/EnemyAIPredictor.lua` (`KNOWN_AI`, marked
STATIC-ONLY). That is all the static work; these scripts are the **live check** of it.

## What each script does

Loads a savestate (`SAVESTATE`) positioned in a battle against that monster, picks the enemy
(`ENEMY_SLOT`), and walks the live `MonsterRecord` (`pAttackDataTable[bId]` chain) to confirm it
resolves to the AI address and matches the static finding. Each header says what to expect.

**None has ever been run**: the header of every one says `NO SAVESTATE`. Fill in `SAVESTATE` and
`ENEMY_SLOT`, then run headless, never against your live session:

    scripts/spawn-headless-emuhawk.sh /abs/path/to/scripts/AIStaticChecks/CheckCrowAI.lua "" <timeout>

## When it is safe to delete

- **One script:** once its monster's AI has been confirmed live (a passing run, or an equivalent
  live capture such as a seed test), and the doc row / `KNOWN_AI` entry is updated from
  "static only" to "live-validated". The script has no other consumer.
- **A whole script you will never run:** safe any time, since nothing requires or calls these
  files and the findings already live in the docs. You only lose the ready-made live check.
- **The whole folder:** when you no longer plan to live-verify the static-only AIs.

Do not delete a script just because it matches a plain-attack AI (the predictor entry is
still unverified for it).

## Not in `KNOWN_AI` (need own models)

Commander AIs (Viperman, Whip Wolf, Whip Master), "always special" ones (Banshee, Nightmare,
Shadow, Shadow Man, Slot Man, Sunshine King, Wyvern), all-row scanners (Mirage, Phantom),
Death Boar / Ghost Armor, Holly Spirit/Fairy, Holly Boy x2, Oannes, Red Soldier Ant, and the
back-row-reaching Black/Red Elemental. Ivy / Mad Ivy are omitted because their address
(`0x80080038`) is shared with Rabbit Bird in another overlay.
