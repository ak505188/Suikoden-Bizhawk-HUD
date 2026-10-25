# Builds outputs/AttackTimingsClean.json from outputs/AttackTimings.json (the walker's raw
# output, kept untouched as the data source). Each cleanup step is a function below, applied in
# order; re-run after regenerating the source with `AttackTimingWalker.py --json`.
# Needs node (reads Suikoden-RNG-lib's bestiary modules).
# Usage: python3 scripts/python/CleanAttackTimings.py
import json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "..", "outputs", "AttackTimings.json")
DST = os.path.join(HERE, "..", "..", "outputs", "AttackTimingsClean.json")
BESTIARY = os.path.join(HERE, "..", "..", "outputs", "Bestiary.json")
PATH_TIMINGS = os.path.join(HERE, "..", "..", "outputs", "AttackPathTimings.json")   # DerivePathTimings.py
RNG_LIB = "/home/alex/Projects/Suikoden-RNG-lib"

sys.path.insert(0, HERE)
import AttackTimingWalker as W                          # only for re-deriving lost columns

STATS = ("hp", "pwr", "skl", "def", "spd", "mgc", "luk")


def load_rng_lib_bestiary():
    """ENEMIES from Suikoden-RNG-lib (bosses were merged into it), as [{path, name, LVL, stats}]."""
    js = """
      import { ENEMIES } from './lib/Game/Bestiary/Enemies.js';
      const out = [];
      for (const [k, v] of Object.entries(ENEMIES)) out.push({ path: 'ENEMIES.' + k, ...v });
      console.log(JSON.stringify(out));
    """
    res = subprocess.run(["node", "--input-type=module", "-e", js], cwd=RNG_LIB,
                         capture_output=True, text=True, check=True)
    return json.loads(res.stdout)


def rekey(data, bestiary, lib):
    """Step 1: key every enemy by its Suikoden-RNG-lib export path (ENEMIES.X),
    matched on level + all seven base stats (unique for all 124 records; names differ between
    the ROM and the lib, e.g. 'Empire Soldier (sword)', '_2' suffixes). The walker's own key
    (Name@scriptTable) collides for records that share a script table but not a sprite sheet;
    it's kept as `walkerKey`. Reaction tables are re-keyed the same way."""
    sig = lambda lvl, s: (lvl,) + tuple(s[k.upper()] for k in STATS)
    by_sig = {sig(e["LVL"], e["stats"]): e for e in lib}
    assert len(by_sig) == len(lib), "Suikoden-RNG-lib has two entries with identical stats"
    assert len(bestiary) == len(data["enemies"]), "Bestiary and AttackTimings are out of step"

    new_keys = []
    for rec, e in zip(bestiary, data["enemies"]):
        assert rec["name"] == e["name"], (rec["name"], e["name"])
        m = by_sig.get((rec["level"],) + tuple(rec["baseStats"][k] for k in STATS))
        if m is None:
            raise SystemExit("no Suikoden-RNG-lib entry for %s (Lv%d)" % (rec["name"], rec["level"]))
        e["walkerKey"] = e["key"]
        e["key"] = m["path"]
        e["libName"] = m["name"]
        new_keys.append(m["path"])
    assert len(set(new_keys)) == len(new_keys), "two records matched the same lib entry"

    # The source's reaction tables are keyed by walkerKey, so where walkerKeys collide the
    # stored column/row came from the LAST record with that key (the walker's dict overwrite).
    last_idx = {}
    for i, e in enumerate(data["enemies"]):
        last_idx[e["walkerKey"]] = i
    lost = [i for i, e in enumerate(data["enemies"]) if last_idx[e["walkerKey"]] != i]

    party_loaded = {p["key"]: W.load_party(p["key"]) for p in data["party"]}
    enemy_loaded = {}

    def enemy(i):
        if i not in enemy_loaded:
            enemy_loaded[i] = W.load_monster(bestiary[i])
        return enemy_loaded[i]

    def recompute(att, tgt, slot, script):
        try:
            r = W.walk_reaction(att, tgt, slot, script)
            return r["self_busy8_clear"] if not r["blocked"] else None
        except (W.Unresolvable, TypeError):
            return None

    party_kinds = {"party_hit": (2, None), "party_crit": (8, None),
                   "party_rune_piece_1": (None, 0x8016c56c), "party_rune_piece_4": (None, 0x8016c648)}
    recomputed = 0
    for kind, (slot, script) in party_kinds.items():
        old = data["reaction"][kind]
        new = {}
        for attacker, row in old.items():
            att = party_loaded[attacker if attacker != "any" else data["party"][0]["key"]]
            nrow = {}
            for i, e in enumerate(data["enemies"]):
                if i in lost:                           # this record's column was overwritten
                    nrow[e["key"]] = recompute(att, enemy(i), slot, script)
                    recomputed += 1
                else:
                    nrow[e["key"]] = row.get(e["walkerKey"])
            new[attacker] = nrow
        data["reaction"][kind] = new
    # enemy_hit rows: the attacker's own sprite sheet isn't used by the reaction (it runs the
    # attacker's script on the TARGET's sheet), so a colliding pair's shared row is valid for both
    old = data["reaction"]["enemy_hit"]
    data["reaction"]["enemy_hit"] = {e["key"]: old[e["walkerKey"]] for e in data["enemies"]}

    return {"rekeyed": len(new_keys),
            "walkerKeyCollisions": sorted({data["enemies"][i]["walkerKey"] for i in lost}),
            "reactionCellsRecomputed": recomputed}


PATH_FIELDS = ("dodgePoint", "recover", "missFree", "dodge", "counter", "death")


def add_path_timings(data):
    """Step 1b: merge scripts/python/DerivePathTimings.py's per-combatant miss / counter / cover / kill
    fields into each entry as `pathTiming` (enemies are still in Bestiary order here, party
    entries keyed by file code). Its own damage / free / reaction must agree with this file's
    hit-path values wherever both are known; a mismatch stops the build."""
    with open(PATH_TIMINGS) as f:
        pt = json.load(f)
    if len(pt["enemies"]) != len(data["enemies"]):
        raise SystemExit("AttackPathTimings.json is out of step with the Bestiary")
    checked = 0
    for entry, fields in [(e, f) for e, f in zip(data["enemies"], pt["enemies"])] + \
                         [(p, pt["party"].get(p["key"], {})) for p in data["party"]]:
        attack = entry.get("attack", {})
        roll = (attack.get("damage_roll") or [None])[0]
        if "damage" in fields and roll is not None and fields["damage"] != roll:
            raise SystemExit("%s: path damage %s != hit damage %s" % (entry["key"], fields["damage"], roll))
        checked += "damage" in fields
        entry["pathTiming"] = {k: fields[k] for k in PATH_FIELDS if k in fields}
    data["_meta"]["pathTiming"] = pt["_meta"]
    return {"entriesWithPathTiming": sum(1 for e in data["enemies"] + data["party"] if e["pathTiming"]),
            "damageCrossChecked": checked}


def split(data):
    """Step 2: turn enemies into an object keyed like Suikoden-RNG-lib's ENEMIES (bare key, e.g.
    enemies.QUEEN_ANT, enemies.QUEEN_ANT_BOSS; the lib merged its old BOSSES into ENEMIES). Each
    entry keeps its namespaced key as `path` (ENEMIES.X), which is what the reaction tables use,
    since those mix both groups and a bare key can exist in both."""
    groups = {"ENEMIES": {}}
    for e in data["enemies"]:
        ns, bare = e["key"].split(".", 1)
        entry = {"path": e["key"]}
        entry.update({k: v for k, v in e.items() if k != "key"})
        if bare in groups[ns]:
            raise SystemExit("duplicate key %s.%s" % (ns, bare))
        groups[ns][bare] = entry
    del data["enemies"]
    party = data.pop("party")
    reaction = data.pop("reaction")
    data["enemies"] = groups["ENEMIES"]
    data["party"] = party
    data["reaction"] = reaction
    return {"enemies": len(groups["ENEMIES"])}


def load_rng_lib_characters():
    """Suikoden-RNG-lib's CHARACTERS, as [[key, name], ...]."""
    js = """
      import CHARACTERS from './lib/Game/Characters.js';
      console.log(JSON.stringify(Object.entries(CHARACTERS).map(([k, v]) => [k, v.name])));
    """
    res = subprocess.run(["node", "--input-type=module", "-e", js], cwd=RNG_LIB,
                         capture_output=True, text=True, check=True)
    return json.loads(res.stdout)


# Party-file names (04_play header) that differ from Suikoden-RNG-lib's display name
CHARACTER_NAME_OVERRIDES = {"Hero": "MCDOHL"}


def key_characters(data, lib_chars):
    """Step 3: turn the party array into a `characters` object keyed like Suikoden-RNG-lib's
    CHARACTERS (GREMIO, FU_SU_LU, MCDOHL for the Hero), matched on the name stored in each
    04_play file's header. The file code (gre, shu, ...) is kept as `code`. Reaction tables
    switch from file codes to these keys (party rows, enemy_hit columns)."""
    by_name = {name.lower(): key for key, name in lib_chars}
    code_to_key = {}
    chars = {}
    for p in data.pop("party"):
        key = CHARACTER_NAME_OVERRIDES.get(p["name"]) or by_name.get(p["name"].lower())
        if key is None:
            raise SystemExit("no Suikoden-RNG-lib character named %r (%s)" % (p["name"], p["key"]))
        if key in chars:
            raise SystemExit("two party files match %s" % key)
        entry = {"code": p["key"]}
        entry.update({k: v for k, v in p.items() if k != "key"})
        chars[key] = entry
        code_to_key[p["key"]] = key
    unused = [k for k, _ in lib_chars if k not in chars]
    if unused:
        raise SystemExit("Suikoden-RNG-lib characters with no party file: %s" % unused)

    reaction = data.pop("reaction")
    for kind, table in reaction.items():
        if kind == "enemy_hit":                          # rows = enemies, columns = party
            reaction[kind] = {a: {code_to_key[c]: v for c, v in row.items()}
                              for a, row in table.items()}
        else:                                            # rows = party (or "any"), columns = enemies
            reaction[kind] = {(code_to_key.get(a, a)): row for a, row in table.items()}
    data["characters"] = chars
    data["reaction"] = reaction
    return {"characters": len(chars), "nameOverrides": CHARACTER_NAME_OVERRIDES}


# Fields with no information in the current walker output (constant for every entry). Step 4
# drops them only while that's still true, so a walker change that makes one meaningful keeps it.
UNINFORMATIVE = {
    ("attack", "target_busy_set"): 0,        # the attack script marks the target busy at frame 0
    ("attack", "target_busy_clear"): None,   # the target's reaction clears it -> reaction tables
    ("recover", "self_fx4_set"): None,       # return scripts never set the done bit
    ("recover", "script_rand"): [],          # return scripts never call rand()
}


def prune(data):
    """Step 4: drop fields that carry no information (see UNINFORMATIVE)."""
    entries = [e for group in ("enemies", "characters") for e in data[group].values()]
    dropped, kept = [], []
    for (block, field), constant in UNINFORMATIVE.items():
        if all(e[block].get(field) == constant for e in entries):
            for e in entries:
                e[block].pop(field, None)
            dropped.append("%s.%s" % (block, field))
        else:
            kept.append("%s.%s" % (block, field))
    return {"dropped": dropped, "keptBecauseNowInformative": kept}


def collapse_rune_piece(data):
    """Step 5: party_rune_piece_1 / _4 are fixed main.exe reaction scripts (0x8016c56c /
    0x8016c648) that take the same number of frames against every target, so both tables
    collapse to one number, reaction.party_rune_piece. Stops if that stops being true."""
    values = {v for kind in ("party_rune_piece_1", "party_rune_piece_4")
              for row in data["reaction"][kind].values() for v in row.values()}
    if len(values) != 1 or None in values:
        raise SystemExit("rune-piece reactions are no longer one constant: %s" % sorted(values, key=str))
    value = values.pop()
    reaction = data["reaction"]
    del reaction["party_rune_piece_1"], reaction["party_rune_piece_4"]
    reaction["party_rune_piece"] = value
    return {"party_rune_piece": value}


def compact_rows(table):
    """Store each row of a reaction table as
    { default: <most common value>, exceptions: { <column key>: <value> } }, with an exception
    only where a column differs from the default (exceptions is always present, empty when the
    whole row agrees). Lookup: row.exceptions[key] ?? row.default. Ties for most common go to
    the smaller value, so the output is deterministic."""
    from collections import Counter
    with_exceptions = {}
    for attacker, row in table.items():
        counts = Counter(row.values())
        best = max(counts.values())
        default = min(v for v, n in counts.items() if n == best)
        table[attacker] = {"default": default,
                           "exceptions": {k: v for k, v in row.items() if v != default}}
        if table[attacker]["exceptions"]:
            with_exceptions[attacker] = len(table[attacker]["exceptions"])
    return {"rows": len(table), "rowsWithExceptions": with_exceptions}


def compact_enemy_hit(data):
    """Step 6: enemy_hit rows as default + exceptions (see compact_rows). The enemy's hit script
    almost always decides the value alone; only Shadow / Shadow Man's depends on the target."""
    return compact_rows(data["reaction"]["enemy_hit"])


def compact_party_hit(data):
    """Step 7: party_hit rows (one per character, columns = enemy/boss paths) as default +
    exceptions, same format as enemy_hit."""
    return compact_rows(data["reaction"]["party_hit"])


def compact_party_crit(data):
    """Step 8: party_crit rows (crit reaction, table slot 8) as default + exceptions, same
    format as party_hit."""
    return compact_rows(data["reaction"]["party_crit"])


def move_reaction_into_entries(data):
    """Step 9: a reaction row belongs to the attacker (the game plays the attacker's own slot-2
    script, slot 8 on a crit, on whoever it hit), so move each row into its attacker's entry
    and drop the top-level reaction tables.
      characters.X.reaction = { hit: n, crit: n }   plain numbers: no character's reaction
                                                   depends on the target (checked here)
      enemies.X .reaction = { hit: { default, exceptions: { CHARACTER: n } } }
                                                   Shadow / Shadow Man have exceptions
      constants.runePieceReaction = n              the fixed main.exe script, any attacker"""
    reaction = data.pop("reaction")
    for key, entry in data["characters"].items():
        hit, crit = reaction["party_hit"][key], reaction["party_crit"][key]
        if hit["exceptions"] or crit["exceptions"]:
            raise SystemExit("%s's reaction now depends on the target; keep default/exceptions"
                             % key)
        entry["reaction"] = {"hit": hit["default"], "crit": crit["default"]}
    for group in ("enemies",):
        for entry in data[group].values():
            entry["reaction"] = {"hit": reaction["enemy_hit"][entry["path"]]}
    data["constants"] = {"runePieceReaction": reaction["party_rune_piece"]}
    return {"characters": len(data["characters"]),
            "enemies": len(data["enemies"]),
            "runePieceReaction": data["constants"]["runePieceReaction"]}


def main():
    with open(SRC) as f:
        data = json.load(f)
    with open(BESTIARY) as f:
        bestiary = json.load(f)["enemies"]
    report = rekey(data, bestiary, load_rng_lib_bestiary())
    report["pathTiming"] = add_path_timings(data)
    report["split"] = split(data)
    report["characters"] = key_characters(data, load_rng_lib_characters())
    report["prune"] = prune(data)
    report["runePiece"] = collapse_rune_piece(data)
    report["enemyHit"] = compact_enemy_hit(data)
    report["partyHit"] = compact_party_hit(data)
    report["partyCrit"] = compact_party_crit(data)
    report["reactionMoved"] = move_reaction_into_entries(data)
    data["_meta"]["cleaned"] = {
        "source": "outputs/AttackTimings.json",
        "script": "scripts/python/CleanAttackTimings.py",
        "keys": "enemies is an object keyed like Suikoden-RNG-lib's ENEMIES (bosses included) "
                "(matched on level + base stats). path = the namespaced key (ENEMIES.X) used "
                "in the source's reaction tables; walkerKey = the source's "
                "Name@scriptTable key; libName = the lib's display name. characters is an "
                "object keyed like Suikoden-RNG-lib's CHARACTERS (matched on the 04_play "
                "header name; the Hero is MCDOHL); code = the 04_play file code. Reaction "
                "tables use these same keys.",
        "duplicates": "none: every record is a distinct lib entry (Golden Hydra's three records "
                      "are GOLDEN_HYDRA_LEFT / _MIDDLE / _RIGHT)",
        "rekey": report,
    }
    data["_meta"]["reaction"] = (
        "Each entry's reaction = frames after the damage frame until the TARGET clears its own "
        "busy bit 8, for this entry as the attacker (the game plays the attacker's reaction "
        "script on the target). characters.X.reaction = { hit, crit } (numbers; no character's "
        "reaction depends on the target). enemies.X .reaction.hit = { default, "
        "exceptions: { <CHARACTER>: value } }: look up exceptions[character] ?? default "
        "(enemies never crit). constants.runePieceReaction replaces a party attacker's hit/crit "
        "when it has Rune_Piece_Type 1 (Fire) or 4 (Thunder): a fixed main.exe script that "
        "takes this many frames against any target.")
    with open(DST, "w") as f:
        json.dump(data, f, indent=4)
    print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
