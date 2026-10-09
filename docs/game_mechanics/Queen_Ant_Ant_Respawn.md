# Queen Ant (Mt. Seifu): ant death and respawn timing

Frame-accurate timeline of how a Soldier Ant dies, waits, and is respawned
in the scripted Mt. Seifu Queen Ant fight (`va7.bin`). Measured live from
`QueenAnt2.State` (round-start, Free Will) on 2026-10-07 in headless
BizHawk. Scripts: `scripts/CaptureAntRespawnTiming.lua` (full byte diff of
a plain round), `scripts/CaptureAntKillMatrix.lua` (forced weapon kills) and
`scripts/CaptureAntScenarios.lua` (batches L, D, C, G, M, R: spell, Unite,
counter, multi-kill, last-actor and rune-loadout scenarios). Test injections
are in-spec: target ant HP 1, party HP at HPMax, runes/MP 4/items edited in
the savestate's memory, RNG seed overwritten.

All frame numbers are emulator frames. `K` = the frame the ant's HP first
reads 0. "rec" = `combatant_rec` (`battle_base + 0xb40 + idx*0x54`), "ai" =
the per-combatant AI struct (`battle_base + 0x50 + idx*0x8c`). Actor
indices: party 1-5 (Hero, Gremio, Pahn, Cleo, Ted in this state), ants 6-8,
Queen Ant 9. The respawn **costs no RNG**: the seed never changed on a
revive frame.

## Who does the respawn

`queen_ant_end_of_round_callback` (`va7.bin 0x8001139c`, hooked at
`BattleState+0x1334`). `battle_advance_turn` (`main.exe 0x800f3e98`) runs it
on **every frame** where `nRollGateCountdown (+0x1264) <= 0` and that
coroutine is the active one. After the last actor of a round has been
picked there is nobody left to roll for, so it keeps running every frame
until the round-end path starts. A revive can therefore happen mid-animation
and more than once per round.

The callback does nothing until every combatant has `ActionTag (rec+0x46)
!= 0`. Then, in one call, it revives **every** enemy slot with
`rec+0x45 != 0` (dead) and `ai+5 == 0` (not busy). Several ants that are
eligible on the same poll all revive on the same frame: three ants killed by
one AoE spell revived together, and two separate kills revived together once
both were past busy-clear.

## Per-ant lifecycle (frames relative to K)

```
K          HP = 0
K+D        rec+0x45 = 1 (dead), rec+0x46 = 1, ai+5 = 1 (busy),
           BattleState+0x2c -= 1
K+D+1      ai+1 = 1
K+D+2      ai+0x12 (u16 countdown) = 90, then -1 per frame
K+D+92     ai+1 = 0, ai+2 = 0
K+D+93     ai+3 = 0, ai+5 = 0   <- not busy, eligible to respawn
R          REVIVE (below)
R+1        ai+2 = 1
R+61       ai+5 = 0   <- spawn animation over
```

`D+93` held in every one of ~70 deaths, whatever killed the ant. A dead ant
already has `ActionTag = 1`, so it never holds the gate closed.

### D: kill to dead flag, by what killed it

```
killer                              D        notes
weapon, party slot 4 or 5           28
weapon, party slot 1 or 2           36
weapon, party slot 3                49
Talisman Unite (slots 2+3)          37       one sample
single-target spell (Fire L1,       0        dead flag the same frame;
  Lightning L1, Wind L2)                     casters 1, 4, 5 identical
Fire L2 (all enemies)               2-3      3 samples (3, 2, 3)
Earth L2 (all enemies)              0
counter-kill by slot 1 or 2         97       4 samples
counter-kill by slot 3              110      5 samples
```

`ai+4` holds the attacker's actor index while an ant is being hit and is
reset to the ant's own index at `K+D`. For spells it already equals the
ant's own index at K. A counter-kill is an ant dying on its own turn to the
party member it attacked; the killer is `ai+4`. Items cannot target enemies,
so they never kill an ant. Counters by slots 4 and 5 were not observed.

## R: the revive frame

R is the first frame at or after both of these where the callback runs:

1. The gate is open: every actor 1..8 has `ActionTag != 0`. This happens
   when the **last actor is selected** (its tag is set at selection, not
   when its action finishes), or when a party member dies (death sets the
   tag).
2. The ant is not busy: `K+D+93`, so the callback sees it one frame later.

```
gate already open when busy clears:  R = K + D + 94
gate opens later:                    R = last tag set + L
```

`L` depends on the last actor's action, because it decides when
`battle_advance_turn` is running again with `nRollGateCountdown <= 0`
(actor 3 was last in nearly every run, and the ant had been waiting since
well before, so these are pure gate-wait latencies):

```
last actor does                     L (frames after its tag is set)
Defend                              1
Attack (target alive, dead, or      10   (dispatch arms countdown 0x0a)
  Queen; a dead target is
  re-selected to a living enemy)
Item (Medicine on self)             17
failed Unite (falls back to Defend) 1
Unite (Talisman, executes)          137  (one sample)
Rune, single target (Fire L1)       310  (spell cast length)
Rune, all enemies (Fire L2)         449  (spell cast length)
```

Rune and Unite keep the coroutine busy for the whole cast, so L is simply
the animation time. Rune, Item and Unite are one-seed measurements; Defend
and Attack have many samples. (An earlier version of this doc said Defend
was 4; that came from picking the wrong "last" tag.)

At R the callback sets `rec+0x45 = 0`, HP = HPMax, `rec+0x46 = 1` (**cannot
act again this round**, acts normally next round), `BattleState+0x2c += 1`,
`ai+3 = 1`, `ai+5 = 1` (busy 61 frames for the spawn animation). Status
flags (`rec+0x4a`) are **not** cleared: an ant given Bucket+Sleep (0x30)
before dying still had 0x30 after respawning.

## Worked example (QueenAnt2.State, one Free Will round)

Frames from the round-confirm tap.

```
ant 7: K=217  killer slot 5  D=28 -> dead 245, not busy 338
       gate opened 458 (slot 3 Attack), poll 468 -> REVIVE 468
       (251 frames after K; 130 of them waiting for the gate)
ant 6: K=514  killer slot 3  D=49 -> dead 563, not busy 656
       gate already open       -> REVIVE 657 (K+143)
```

Round 1 lasted 772 frames, round 2 864 frames; round 3 ended the battle at
657 frames.

## A dead ant always respawns before the round ends

The round-end path starts (`pending actor = 0`, `nRollGateCountdown = 30`)
on the **same frame as the last revive** in every run that had one. A dead
or busy enemy makes the turn roll return "wait", so the round cannot end
while an ant is dead; once the gate is open the callback revives it and the
round-end path follows immediately. For a sim: a late kill delays the round
end by up to `K + D + 94` instead of being cut off, and the spawn animation
(61 frames) plays during round end. From that frame to the menu being ready
again was 84 frames in 23 samples (52 when no ant was involved, other values
when long actions were still resolving).

## Fight end (round 3)

Same callback: once the gate is open and `dwRoundNumber > 2` it sets
`BattleState+0x34 = 1`, so fight end = gate open + L + the countdown
sequence.

```
original 3-round capture (last actor slot 3, L = 36):
556   last ActionTag set (gate opens)
562   nRollGateCountdown armed to 0x1e (30)
592   countdown expires -> callback polls: BattleState+0x34 = 1
592   re-armed to 30 (round-end cleanup); 622 expires
623   armed to 30 again; 653 expires; 654 countdown = -1
657   battle exits
```

With a Defend as the last action `+0x34` is set one frame after the tag
(1437 -> 1438 and 1440 -> 1441). The exit follows 65-66 frames after
`+0x34` in the clean samples (592 -> 657, 1438 -> 1503, 1441 -> 1506). A
revive in progress or a long last action lengthens it (one sample took 107).
Round 3 therefore ends at "gate open + L + about 65".

## Gate details (decompile, confirmed against the data)

- The gate checks `ActionTag (rec+0x46)` and nothing else (no busy flag).
- By the loop bounds it covers actors `1 .. total-1`, not the last actor
  (Queen Ant). Decompile reading only. Queen acted before the gate in every
  capture, so this never mattered.
- Party deaths set the victim's tag, so a death can open the gate early.

## Queen Ant AoE Earth, rune check

Queen's MGC is **55** (ATK 75, SKL 25, DEF 50, SPD 20, LUK 55), written once
at round-1 start and unchanged through round 3. Six 3-round runs with edited
rune loadouts (Earth, Soul Eater, Fire, Lightning, Water, none, and unmapped
rune 8) produced about 45 AoE hits where the target survived. Every one
matched the documented formula: damage halved for Earth (id 6) and Soul
Eater (id 1), plain for Fire, Lightning, Water, no rune, and rune 8. No
counterexample to "no halving without an Earth or Soul Eater rune". Hits
that killed the target were excluded (the target's remaining HP clipped the
visible damage).

## Revived ant, other observations

- Round 2 Free Will targets a revived ant normally.
- A queued attack whose target is dead when the actor's turn comes is
  re-targeted to a living enemy (action `0/0/6` became `0/0/7`).
- `CommandAnts` still costs 0 RNG and does nothing: a revived ant has
  `ActionTag = 1`, so it is never eligible.

## Not measured / open

- Rune, Item and Unite last-actor latencies for more than one spell or seed,
  and Magic Unite.
- D for counter-kills by slots 4 and 5, other Unites, and spells other than
  the ones listed.
- A death after the round-end path has started (for example poison).
- Whether targeting a respawning ant is blocked mid-spawn: commands are
  chosen at round start, so only the re-target case above was observable.
