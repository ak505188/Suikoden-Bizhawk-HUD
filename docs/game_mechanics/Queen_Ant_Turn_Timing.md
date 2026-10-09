# Queen Ant fight: per-turn frame timing (Queen, Soldier Ants, round start)

Frame offsets for the actors' own turns in the scripted Mt. Seifu fight
(`va7.bin`), extracted on 2026-10-07 from the per-frame logs of the 70+
headless runs described in [Queen_Ant_Ant_Respawn.md](./Queen_Ant_Ant_
Respawn.md) (`scripts/CaptureAntScenarios.lua`, `QueenAnt2.State`; 50 Queen
AoE turns, 25 CommandAnts turns, 211 Soldier Ant turns). Per-sample table:
[Queen_Ant_Turn_Timing_Samples.csv](./Queen_Ant_Turn_Timing_Samples.csv).

**Conventions.** `t0` = the frame `BattleState+0x8` (current actor) becomes
the actor. The actor's AI runs on `t0+1` (the first rand() of its turn is
on that frame; every roll of one AI pass lands on one frame). Frames are
sampled at frame end, so an event can read one frame later than the tick
that caused it. `r` = the AI tick of an ant (`t0+1`, later when its target
scan retries, see below). `A` below is Queen's own wind-up. "busy" = the
combatant's AI-struct `+5`. "gate" = `nRollGateCountdown` (`+0x1264`).
`nextRoll` = frame of the next turn-order roll (`pending actor` written),
`nextCopy` = the frame after, when the next actor is copied.

## Round start

Round-confirm tap = frame 0. At frame 28 the round counter increments,
**one** rand() is consumed and the gate is armed to 30. The first turn roll
is at frame 58 (gate 30 -> 0), the picked actor is copied at frame 59. Same
as an ordinary fight. The first roll costs one rand() per un-acted candidate
(9 here: 5 party, 3 ants, Queen).

## Queen Ant: AoE Earth

```
t0+1        move roll (1 rand()); her busy = 1, tag = 1
t0+A        party animation targets set (ai+4 = 9, all five same frame)
A+128       all living targets busy (8)
A+162       all targets busy clears (same frame for every slot)
A+175       the damage rolls (one rand() per living target, one frame)
A+176       all HP drops land on this frame
A+181       her busy clears
A+182       gate armed to 30
A+212       nextRoll
A+213       nextCopy
```

All offsets after `A` were identical in all 50 samples (one outlier where
the next roll was a different kind, nextRoll at A+361). The damage rolls are
a single frame, not spread across targets. **`A` varies**: observed values
(count): 58 (2), 99 (1), 142 (2), 152 (2), 164 (24), 166 (1), 171 (7),
174 (3), 178 (2), 184 (2), 186 (4). 164 is the mode; 58 occurred only with
no ant alive. What decides `A` is unresolved (it is not a fixed gap after
the last busy clear; ant attack animations still playing are the leading
suspect).

## Queen Ant: CommandAnts (no-op, still takes time)

Identical in all 25 samples:

```
t0+1        move roll (1 rand()); her busy = 1, tag = 1
t0+16       gate = -1
t0+17       gate armed to 90 (counts down 1/frame)
t0+107      gate armed to 30
t0+137      nextRoll
t0+138      nextCopy
t0+180      her busy clears (16 samples; the rest were cut by round end)
```

So the no-op branch costs 138 frames to the next actor, not 0. No HP
changes and no other rolls.

## Soldier Ant turns

The turn itself is short; the animation runs on afterwards (the next actor
can start while the ant is still busy).

```
                          Attack            Double Strike
gate armed (at r)         10                20
nextRoll                  r+10              r+20
nextCopy, same side       r+11              r+21
nextCopy, other side      r+108             r+83   (release signal)
HP drop lands             r+83              r+29
own busy clears           r+169             r+145
target busy (8) clears    r+118             r+63
```

(`other side` = the next actor is a party member after an ant; it waits for
the release signal, so it is later than the gate. Same side = ant or Queen
next.) `r` = t0+1 normally; each rejected scan retry adds one tick (below),
and every later offset moves with it (measured: own busy clear at 170, 171,
172 frames after t0 for 0, 1, 2 retries). These match the shared Soldier Ant
values to within one frame (damage 83, free 169, reaction/target 118,
recover 107 for Attack; +29, +82, +145, +63, gate 20 for Double Strike; the
"other side" copy reads 108/83 here, a one-frame sampling difference). The
damage roll itself is the frame before the HP drop (as for Queen's AoE:
roll A+175, HP A+176); it was not separately isolated for ants. The "other
side" Double Strike value is a single sample.
Counts: gate 10, 98+27+7 samples with the normal timing; gate 20, 31+8+2.
Longer own-busy values (203, 213, 214, 296-308) are the miss/dodge/counter
variants and were not decoded.

Double Strike rolls: one AI pass (target scan + move roll); the damage
frame is `r+29` with one HP drop (damage doubled). A separate hit/miss roll
is not visible in the RNG diffs of those samples, which still has to be
confirmed by counting calls per frame (not done).

## Checks

- **Round start**: yes, same as ordinary fights (above).
- **Target-scan retries**: yes, a total reject re-runs the whole scan on the
  **next tick**. A turn whose AI roll lands at t0+1, t0+2 or t0+3 shows
  rand() events on consecutive ticks and a busy-set at the same tick; one
  full scan pass (several rolls) runs inside one tick.
- **Turn-roll cost**: one rand() per un-acted, non-busy candidate. First
  roll 9 calls, then 8, 7, 6 as actors are picked; later rolls drop further
  when a candidate is busy (an ant's target is busy 8 and is skipped). Dead
  ants and revived ants already have `ActionTag = 1`, so they are skipped by
  tag, not by busy (a revived ant is also busy for 61 frames). A dying ant
  whose dead flag has not yet been set (`D` frames after HP 0) still has
  tag 0 and was not separately tested.
