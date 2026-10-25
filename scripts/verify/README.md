# verify

Live (headless BizHawk) checks that are worth re-running because they validate a model or tool
that is still in use. One-off "confirm this one static finding" scripts were deleted on 2026-10-12;
their results stay in `docs/game_mechanics/Battle_Damage_Formula.md` and `Battle_Algorithm.md`.

Run headless, never in your live session (see `scripts/spawn-headless-emuhawk.sh`).

## Scripts

`VerifyAttackTimings.lua`
: Logs per-frame attack timing from `ZombieDragonT2Start.State` and is compared against
  `outputs/AttackTimings.json` by `scripts/python/AttackTimingCompare.py`. Re-run after changing
  `AttackTimingWalker.py` or its inputs.

`VerifyCover.lua`
: Live log of the cover mechanic (`find_cover_target`, `battle_check_counter_attack`) on
  `3Mosquito1Ant.State`, compared by `scripts/python/VerifyCoverCompare.py` (85/85 predictions).
  Re-run if the cover model in the Python or docs changes.

`VerifyMosquitoRedAnt.lua`
: Mosquito / Red Soldier Ant AI and timings vs `outputs/AttackTimingsClean.json`, compared by
  `scripts/python/VerifyMosquitoRedAntCompare.py`. Re-run if `CleanAttackTimings.py` changes.

`VerifyEventAPI.lua`
: Diagnostic, not a game check: confirms BizHawk's `event.*` / `memory.registerwrite` callbacks
  fire at all in this build. Run it when a hook reports "zero hits" and you suspect the emulator.

## When each is safe to delete

- The three timing/cover scripts: when their Python counterpart (and the static model it checks)
  is retired, or you accept the recorded results in the docs without re-validating. Delete the
  `.lua` and its `*Compare.py` together.
- `VerifyEventAPI.lua`: when you no longer use `event.*` hooks, or the BizHawk build is pinned
  and known good.
