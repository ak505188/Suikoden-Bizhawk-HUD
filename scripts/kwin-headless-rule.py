#!/usr/bin/env python3
"""Temporarily adds/removes a KWin window rule that forces this project's spawned BizHawk
instances to start minimized (never taking focus), so they don't interrupt whatever else is
on screen - including kicking a fullscreen app out of fullscreen, which is what plain
xdotool-after-the-fact minimizing can't prevent (the focus-steal that triggers it already
happened by the time xdotool can react).

The rule is scoped IN TIME, not by any property of the user's own BizHawk usage: it exists
only for the duration of one spawned instance (added right before launch, removed right
after), so it never affects the user's own manual BizHawk launches, which happen when this
rule isn't present at all. See scripts/spawn-headless-emuhawk.sh, which calls this
automatically - you shouldn't normally need to run this directly.

Usage:
  kwin-headless-rule.py add     # add the rule + reconfigure KWin
  kwin-headless-rule.py remove  # remove the rule (if present) + reconfigure KWin
"""
import configparser
import subprocess
import sys
from pathlib import Path

KWINRULESRC = Path.home() / ".config/kwinrulesrc"
RULE_UUID = "b1ack5had-0w00-4ead-1ine-000000000001"  # fixed, recognizable, project-specific


def reconfigure_kwin():
    subprocess.run(["qdbus6", "org.kde.KWin", "/KWin", "reconfigure"], check=False)


def load():
    cfg = configparser.ConfigParser(strict=False)
    cfg.optionxform = str  # preserve key case
    if KWINRULESRC.exists():
        cfg.read(KWINRULESRC)
    return cfg


def save(cfg):
    with open(KWINRULESRC, "w") as f:
        cfg.write(f, space_around_delimiters=False)


def add():
    cfg = load()
    if not cfg.has_section("General"):
        cfg.add_section("General")
        cfg.set("General", "count", "0")
        cfg.set("General", "rules", "")

    existing_rules = [r for r in cfg.get("General", "rules", fallback="").split(",") if r]
    if RULE_UUID not in existing_rules:
        existing_rules.append(RULE_UUID)
        cfg.set("General", "rules", ",".join(existing_rules))
        cfg.set("General", "count", str(len(existing_rules)))

    if cfg.has_section(RULE_UUID):
        cfg.remove_section(RULE_UUID)
    cfg.add_section(RULE_UUID)
    cfg.set(RULE_UUID, "Description", "TEMPORARY - Suikoden-Bizhawk-HUD headless capture (auto-removed)")
    # Match either the main EmuHawk window (dynamic title, always ends "- BizHawk") or the
    # Lua Console window (fixed exact title) - this Mono/WinForms build doesn't set WM_CLASS,
    # so title is the only usable match field.
    cfg.set(RULE_UUID, "title", "BizHawk|Lua Console")
    cfg.set(RULE_UUID, "titlematch", "3")  # RegEx
    cfg.set(RULE_UUID, "minimize", "true")
    cfg.set(RULE_UUID, "minimizerule", "3")  # Apply Initially (set once at creation, not enforced continuously)
    # `minimize` alone only affects the window's minimized/taskbar state - it does NOT stop
    # the initial focus-steal that happens at map time (confirmed empirically: the window
    # still took focus for several seconds with only the minimize rule set). Focus Stealing
    # Prevention is the actual relevant control - force it to Extreme (4) so KWin refuses to
    # grant this window focus at all, continuously (Force=2), not just at creation.
    cfg.set(RULE_UUID, "fsplevel", "4")     # Extreme
    cfg.set(RULE_UUID, "fsplevelrule", "2") # Force
    save(cfg)
    reconfigure_kwin()


def remove():
    cfg = load()
    if cfg.has_section(RULE_UUID):
        cfg.remove_section(RULE_UUID)
    if cfg.has_section("General"):
        existing_rules = [r for r in cfg.get("General", "rules", fallback="").split(",") if r and r != RULE_UUID]
        cfg.set("General", "rules", ",".join(existing_rules))
        cfg.set("General", "count", str(len(existing_rules)))
    save(cfg)
    reconfigure_kwin()


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in ("add", "remove"):
        print(__doc__)
        sys.exit(1)
    if sys.argv[1] == "add":
        add()
    else:
        remove()
