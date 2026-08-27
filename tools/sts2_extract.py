"""Pull Slay the Spire 2 run history into the shape the visualiser wants.

The game writes one JSON file per run to

    %APPDATA%/SlayTheSpire2/steam/<id>/profile1/saves/history/<start_time>.run

and prunes old ones, so this script *merges* into the existing dataset rather
than rebuilding it: seven early runs are already gone from disk and would be
lost by a regenerate.

The filter matches what the dataset was originally built with, verified by
reproducing all of its on-disk records exactly:

    ascension == 10, was_abandoned is false, game_mode == "standard"

Usage:
    python tools/sts2_extract.py            # merge new runs into the dataset
    python tools/sts2_extract.py --verify   # re-derive existing rows, diff, write nothing
    python tools/sts2_extract.py --since 2026-08-20
    python tools/sts2_extract.py --build v0.111.0   # only the current patch
"""

import argparse
import datetime
import glob
import io
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JSON_OUT = os.path.join(ROOT, "sts2_a10_runs.json")
JS_OUT = os.path.join(ROOT, "sts2_data.js")
HISTORY = os.path.expandvars(
    r"%APPDATA%\SlayTheSpire2\steam\76561198018706944\profile1\saves\history")

ASCENSION = 10
GAME_MODE = "standard"


def _strip(value, prefix):
    """'CARD.CHILL' -> 'CHILL'. The game prefixes every id with its table."""
    text = str(value)
    return text[len(prefix):] if text.startswith(prefix) else text


def qualifies(raw):
    return (raw.get("ascension") == ASCENSION
            and not raw.get("was_abandoned", False)
            and raw.get("game_mode") == GAME_MODE)


def derive(raw):
    """One run file -> one dataset row."""
    player = raw["players"][0]
    points = [mp for act in raw.get("map_point_history", []) for mp in act]

    floor_hp, floor_max_hp, floor_gold, floor_types = [], [], [], []
    card_choices, encounters = [], []
    for mp in points:
        floor_types.append(mp.get("map_point_type"))
        stats = (mp.get("player_stats") or [{}])[0]
        floor_hp.append(stats.get("current_hp"))
        floor_max_hp.append(stats.get("max_hp"))
        floor_gold.append(stats.get("current_gold"))
        for choice in stats.get("card_choices", []):
            card_choices.append({
                "card": _strip((choice.get("card") or {}).get("id", ""), "CARD."),
                "picked": bool(choice.get("was_picked")),
            })
        for room in mp.get("rooms", []):
            if room.get("room_type") not in ("monster", "elite", "boss"):
                continue
            encounters.append({
                "name": _strip(room.get("model_id", ""), "ENCOUNTER."),
                "type": room.get("room_type"),
                "damage": stats.get("damage_taken"),
            })

    return {
        "character": _strip(player.get("character", ""), "CHARACTER."),
        "win": bool(raw.get("win")),
        "ascension": raw.get("ascension"),
        "floors": len(points),
        "build_id": raw.get("build_id"),
        "killed_by": _strip(raw.get("killed_by_encounter", ""), "ENCOUNTER."),
        "acts_reached": len(raw.get("acts", [])),
        "run_time_sec": raw.get("run_time"),
        "start_time": raw.get("start_time"),
        "deck_size": len(player.get("deck", [])),
        "relic_count": len(player.get("relics", [])),
        "floor_hp": floor_hp,
        "floor_max_hp": floor_max_hp,
        "floor_types": floor_types,
        "floor_gold": floor_gold,
        "card_choices": card_choices,
        "encounters": encounters,
    }


def read_history(since=None):
    out = {}
    for path in glob.glob(os.path.join(HISTORY, "*.run")):
        try:
            raw = json.load(io.open(path, encoding="utf-8-sig"))
        except (ValueError, IOError) as exc:
            print("  unreadable, skipped: %s (%s)" % (os.path.basename(path), exc))
            continue
        if since is not None and raw.get("start_time", 0) < since:
            continue
        out[raw.get("start_time")] = raw
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", help="only consider runs started on/after YYYY-MM-DD")
    ap.add_argument("--build", help="only consider runs from this build, e.g. v0.111.0")
    ap.add_argument("--verify", action="store_true",
                    help="re-derive rows already in the dataset and report differences")
    args = ap.parse_args()

    since = None
    if args.since:
        since = int(datetime.datetime.strptime(args.since, "%Y-%m-%d")
                    .replace(tzinfo=datetime.timezone.utc).timestamp())

    existing = json.load(io.open(JSON_OUT, encoding="utf-8-sig"))
    by_time = {r["start_time"]: r for r in existing}
    print("dataset: %d runs" % len(existing))

    history = read_history(since)
    print("history: %d run files considered" % len(history))

    if args.verify:
        checked = mismatched = 0
        for start, raw in sorted(history.items()):
            if start not in by_time or not qualifies(raw):
                continue
            checked += 1
            if derive(raw) != by_time[start]:
                mismatched += 1
                print("  MISMATCH at %s" % start)
        print("verified %d rows, %d mismatched" % (checked, mismatched))
        return 0 if mismatched == 0 else 1

    added = [derive(raw) for start, raw in sorted(history.items())
             if qualifies(raw) and start not in by_time
             and (args.build is None or raw.get("build_id") == args.build)]
    if not added:
        print("nothing new to add")
        return 0

    merged = sorted(existing + added, key=lambda r: r["start_time"])
    with io.open(JSON_OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(merged, fh, indent=4)
    with io.open(JS_OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("const RUN_DATA = ")
        json.dump(merged, fh, indent=4)
        fh.write(";\n")

    fmt = lambda t: datetime.datetime.fromtimestamp(
        t, datetime.timezone.utc).strftime("%Y-%m-%d")
    print("added %d runs, dataset now %d" % (len(added), len(merged)))
    for row in added:
        print("  %s  %-12s %-9s floors=%-3d %s" % (
            fmt(row["start_time"]), row["character"], row["build_id"],
            row["floors"], "WIN" if row["win"] else row["killed_by"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
