# Duels

Duels (the game's internal name is "ikki", one-on-one) are the
rock-paper-scissors fights: McDohl vs Kwanda, McDohl vs Teo, and Pahn vs
Teo. Each one is its own overlay in `data/12_ikki/`, loaded at
`0x80080000`:

- `shu_kwa.bin`: McDohl vs Kwanda
- `shu_teo.bin`: McDohl vs Teo
- `pan_teo.bin`: Pahn vs Teo

All three have byte-identical code at the same addresses. Only the data
differs (enemy stats and dialogue). The simulator is `lib/Duel.lua`.

Status: this comes from static RE in Ghidra, and a live capture confirmed
it on 2026-10-01 (`scripts/CaptureKwandaDuel.lua`). Over 5 rounds that
covered outcomes 3, 5, 6, 7 and 8, `lib/Duel.lua` matched every enemy move,
dialogue row, hit order, damage value and RNG step, along with the final
RNG state. A second capture of McDohl vs Teo (`scripts/CaptureTeoDuel.lua`)
covered 24 rounds across 6 seeds, including all 9 outcomes. All 34 of its
hits had a base of 100 or more, so the variance term was exercised in both
directions. Every hit matched (`scripts/CompareDuelCapture.lua`). See
[notes/Duels.md](../../notes/Duels.md).

## rand() usage

The overlay calls main.exe's `rand()` (`0x80147e38`) through the engine
callback table (`0x80165608`, slot `+0x90`). There are only two call sites:

1. `duel_pick_enemy_move` (`0x80087898`) is called once per round, at the
   round start. It runs before the enemy's line appears and before the
   player picks a command.
2. `duel_apply_hit` (`0x80084634`) is called once per hit landed, on
   either side.

So a round costs one roll for the move plus one roll per hit. That is 1
call for Defend vs Defend and up to 3 for a trade.

## Enemy move

```
move = ((rand() * 3) / 0x7fff) % 3      -- 0 Attack, 1 Defend, 2 Desperate
```

- `0x0000`-`0x2aaa` gives Attack.
- `0x2aab`-`0x5554` gives Defend.
- `0x5555`-`0x7ffe` gives Desperate.
- `0x7fff` wraps around to Attack.

The roll doesn't depend on HP, the round number, or the player's history.

## Dialogue

There is no separate roll for dialogue. Each duel has a 10x3 line table:

```
line = table[previousOutcome][enemyMove]
```

`previousOutcome` is 0 on round 1. After that it is the last round's
outcome index (1-9, see below). Because the column is the enemy's move,
every line identifies the move exactly. The Suikosource guide's columns
are a lossy version of this table.

## Outcomes and hits

```
outcome = playerMove * 3 + enemyMove + 1
```

The hits are listed in the order they land:

- 1, Atk vs Atk: enemy takes x1, then player takes x1.
- 2, Atk vs Def: enemy takes x1/2.
- 3, Atk vs Desp: enemy takes x1, then player takes x2.
- 4, Def vs Atk: player takes x1/2.
- 5, Def vs Def: no hits, no damage rolls.
- 6, Def vs Desp: enemy takes x2 (counter).
- 7, Desp vs Atk: player takes x1, then enemy takes x2.
- 8, Desp vs Def: player takes x2 (counter).
- 9, Desp vs Desp: enemy takes x2, then player takes x2.

Desperate "beating" Attack is really a trade: you still take a normal hit
first. Only outcomes 2, 4, 6 and 8 are one-sided.

## Damage

```
base = max(attacker.STR - defender.DEF, 1)
dmg  = base + ((base / 100) * rand()) % 10
x1/2: dmg = dmg / 2
x2:   dmg = max(dmg * 2, defender.currentHP / 4)
```

This is a simplified version of the physical formula. The variance is
`+0..9`, and it is always 0 while `base < 100`. So for Kwanda
(STR 150) against a hero with DEF 51 or more, the roll still happens but
doesn't change anything. The x2 multiplier has a floor of a quarter of the
defender's current HP. HP is capped at max, and there is no floor at 0
while the round is in progress.

There is no minimum of 1 after halving, so a x1/2 hit with base 1 does 0
damage.

The KO check runs after the whole round. Both hits always land and both
always roll. The player is checked first, so a double KO counts as a loss.

## Stats

Each side has a `0x1c`-byte record in the duel struct. The pointer to that
struct is an overlay global, and its address is different in each file even
though the code is the same:

- `shu_kwa.bin`: `*0x800a1d6c`
- `shu_teo.bin`: `*0x800a1dd0`
- `pan_teo.bin`: `*0x800a2340`

The record layout:

- Side 0 (player) is at `+0x6a4`. Side 1 (enemy) is at `+0x6c0`.
- `+0x0` holds current HP, and `+0x4` holds max HP.
- `+0x8` holds 8 shorts. Index 6 is STR and index 7 is DEF.
- `+0x18` holds the hit flags: 1 = x1, 2 = x1/2, 4 = x2, 8 = counter.

The enemy uses the overlay's hardcoded values:

- Kwanda: HP 280/280, STR 150, DEF 75.
- Teo (vs McDohl): HP 180/360, STR 240, DEF 105.
- Teo (vs Pahn): HP 370/370, STR 290, DEF 150.

For the player, `duel_init_sides` calls `battle_compute_ally_derived_stats`
(`0x800d4ec0`). That means STR and DEF are the character's normal battle
ATK and DEF, the same values `computeAllyATKDEF` produces. Current and max
HP carry over from the party record.

## Dialogue tables

The row is `previousOutcome` (0 on round 1), and the entries in each row
are the line for the enemy's move. The text was decoded from each
overlay's row table, and it uses the same text as `lib/Duel.lua`.

### McDohl vs Kwanda (`shu_kwa.bin`)

- Row 0:
  - Atk: Taste the sharpness of my blade!
  - Def: Can you break my invulnerable defenses?
  - Desp: Victory is near! I strike with all my might!
- Row 1:
  - Atk: Well done. But can you take this?
  - Def: Pretty good. How about another one?
  - Desp: The next one won't be so easy.
- Row 2:
  - Atk: Heh, now it's my turn.
  - Def: Damn! My turn!
  - Desp: I'll get you!
- Row 3:
  - Atk: Ha ha! You'll have to do better than that!
  - Def: Now it's your turn. Come on!
  - Desp: Here we go again!
- Row 4:
  - Atk: At a loss, are you? But I'll show no mercy!
  - Def: Don't bore me. Show me what you can do.
  - Desp: Take that!
- Row 5:
  - Atk: What's the matter? If you don't attack, I will!
  - Def: Cautious, aren't you. Just like a leader.
  - Desp: We're getting nowhere. Here I come!
- Row 6:
  - Atk: Damn! I underestimated you.
  - Def: Carefully...
  - Desp: Impossible! You can't avoid my blows!
- Row 7:
  - Atk: Whoa! Pretty good, Teo's little boy. Now it's my turn!
  - Def: Arghhh! I underestimated you.
  - Desp: Well done. You're a worthy opponent. Now it's my turn!
- Row 8:
  - Atk: That's nothing!
  - Def: Forget it. You're methods are obvious.
  - Desp: I'll show you how it's done.
- Row 9:
  - Atk: You're better than I thought. But how about this?
  - Def: What now?
  - Desp: Interesting. How about another round?

### McDohl vs Teo (`shu_teo.bin`)

- Row 0:
  - Atk: Here I come, my son.
  - Def: Show me what you've learned.
  - Desp: My sword is the Emperor's sword. I'll show no mercy!
- Row 1:
  - Atk: Well done!
  - Def: Good, try it again!
  - Desp: Can you avoid my sword?
- Row 2:
  - Atk: That was nothing. Now it's my turn.
  - Def: I'll see you coming next time!
  - Desp: My deadly sword...
- Row 3:
  - Atk: Do you see how much better I am?
  - Def: Is that all you've got?
  - Desp: Hmmm. Here I come again!
- Row 4:
  - Atk: Is defending yourself all you can do? You'll never win that way.
  - Def: Come on! Show me what a man you've become.
  - Desp: The next one will be more painful.
- Row 5:
  - Atk: We're getting nowhere. Here I come!
  - Def: Leader of the Liberation Army! No wonder you're careful.
  - Desp: If you don't attack, I will!
- Row 6:
  - Atk: Did you see that coming?
  - Def: Well done! I must be more careful too.
  - Desp: Are you trying to surpass me?
- Row 7:
  - Atk: That was pretty good. Now it's my turn.
  - Def: I'm losing my cool. I must be more cautious!
  - Desp: Now that I've seen what you've got, I'll show you what I can do.
- Row 8:
  - Atk: You're soft...soft! This is how you attack!
  - Def: I underestimated you! What's wrong? Another round?
  - Desp: That's...no good.
- Row 9:
  - Atk: The numbness in my hands, it's real!
  - Def: I mustn't underestimate you.
  - Desp: I'm delighted, my son. You're quite a warrior. But here's another!

### Pahn vs Teo (`pan_teo.bin`)

- Row 0:
  - Atk: My sword's not rusty yet.
  - Def: Strike me, Pahn!
  - Desp: Finish me with a single blow!
- Row 1:
  - Atk: Pretty good, Pahn.
  - Def: All right, do it again!
  - Desp: Can you dodge my blade, Pahn?
- Row 2:
  - Atk: Is that all you've got? Now it's my turn!
  - Def: I'll see that coming next time!
  - Desp: My killer blade...
- Row 3:
  - Atk: Do you see how we're mismatched?
  - Def: Do you give up?
  - Desp: Hmmm. Here I come again!
- Row 4:
  - Atk: All you can do is defend yourself, Pahn? No mercy!
  - Def: Come on, Pahn. See if you can kill me.
  - Desp: The next one will be more painful.
- Row 5:
  - Atk: We're getting nowhere. Here I come!
  - Def: You're a smart one, Pahn.
  - Desp: If you don't attack, I will!
- Row 6:
  - Atk: Did you see me coming?
  - Def: Good work, Pahn. I'll have to be more careful.
  - Desp: Impossible! Take that!
- Row 7:
  - Atk: That was a good one, Pahn. Now it's my turn.
  - Def: I'm losing my cool. Better be careful.
  - Desp: Now that I've seen what you've got, I'll show you what I can do.
- Row 8:
  - Atk: Get serious, Pahn. This is how it's done.
  - Def: What's the matter, Pahn? How about another round?
  - Desp: That's...no good.
- Row 9:
  - Atk: The numbness in my hands, it's real.
  - Def: You're better than I thought.
  - Desp: Excellent, Pahn. You're a real fighter. Here's another!
