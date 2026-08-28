"""Rate every card by how often it gets picked over the alternatives.

A card reward screen is a comparison: the card you took beat the ones you left.
Feed every one of those comparisons through Elo and you get a single number per
card for how much you want it.

What counts as a comparison
---------------------------
Only screens where a choice was actually made. Three things matter:

* Shops are excluded. The game logs a shop's whole inventory as
  ``card_choices``, so 494 of them look like seven-card screens where nothing
  was taken. Including them would sink every card that ever sat on a shelf.
  Combat rewards, boss rewards and event choices are the real decisions.
* Skipping is a comparison too. A third of reward screens get skipped, and that
  is the strongest signal there is. SKIP is rated alongside the cards, so it
  lands exactly at the "would I even take this" line: cards above it are ones
  you want, cards below it are ones you pass on.
* A card you took beat the cards you left AND beat skipping. A card you left
  did *not* lose to skipping - you took something else. Scoring it as a loss to
  SKIP would punish good cards for losing to better ones.

Why the ratings are solved, not replayed
----------------------------------------
Elo's usual update is an online estimator of a logistic comparison model, and
run sequentially it depends on the order the games arrive in. Shuffling and
replaying averages that down but never to zero - on this data it left cards
drifting +-7 Elo and the skip line moving +-15 with the seed. So `rate()` fits
the same model exactly (Bradley-Terry by minorization-maximization) and reports
it on the Elo scale: deterministic, no seed, no K to tune.

Cards seen only once or twice are pulled toward 1500 by a handful of virtual
drawn games, so a card that went 1-for-1 cannot outrank one that went 40-for-60,
and an all-or-nothing record stays finite.

Usage:
    python tools/sts2_elo.py            # write sts2_elo.js
    python tools/sts2_elo.py --report   # print the tables instead
"""

import argparse
import collections
import glob
import io
import json
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_JS = os.path.join(ROOT, "sts2_elo.js")
HISTORY = os.path.expandvars(
    r"%APPDATA%\SlayTheSpire2\steam\76561198018706944\profile1\saves\history")

ASCENSION = 10
SHOP_ROOMS = {"shop"}
SKIP = "(skip)"

BASE = 1500.0
PRIOR_GAMES = 6          # virtual drawn games against a fixed 1500 anchor
MAX_ITERS = 10000
TOLERANCE = 1e-11        # on log-strength; the fit is deterministic


def _strip(value, prefix):
    text = str(value)
    return text[len(prefix):] if text.startswith(prefix) else text


def load_choices():
    """Return (screens, stats); one screen per real card-selection decision."""
    screens = []
    stats = collections.Counter()
    for path in glob.glob(os.path.join(HISTORY, "*.run")):
        try:
            raw = json.load(io.open(path, encoding="utf-8-sig"))
        except (ValueError, IOError):
            stats["unreadable"] += 1
            continue
        if raw.get("ascension") != ASCENSION:
            continue
        stats["runs"] += 1
        character = _strip(raw["players"][0].get("character", ""), "CHARACTER.")
        for act in raw.get("map_point_history", []):
            for point in act:
                rooms = set(r.get("room_type") for r in point.get("rooms", []))
                if rooms & SHOP_ROOMS:
                    stats["shop_screens_dropped"] += 1
                    continue
                for player_stats in point.get("player_stats", []):
                    choices = player_stats.get("card_choices") or []
                    if not choices:
                        continue
                    # the same card can appear twice on one screen at different
                    # upgrade levels; collapse to the base id, a pick wins
                    seen = {}
                    for choice in choices:
                        cid = _strip((choice.get("card") or {}).get("id", ""), "CARD.")
                        if not cid:
                            continue
                        seen[cid] = seen.get(cid, False) or bool(choice.get("was_picked"))
                    if not seen:
                        continue
                    picked = sorted(c for c, was in seen.items() if was)
                    passed = sorted(c for c, was in seen.items() if not was)
                    screens.append({"character": character,
                                    "picked": picked, "passed": passed})
                    stats["screens"] += 1
                    stats["offers"] += len(seen)
                    if not picked:
                        stats["skipped_screens"] += 1
    return screens, stats


def comparisons(screens):
    """Each screen becomes a list of (winner, loser) pairs."""
    out = []
    for screen in screens:
        if screen["picked"]:
            for winner in screen["picked"]:
                for loser in screen["passed"]:
                    out.append((winner, loser))
                out.append((winner, SKIP))    # preferred to taking nothing
        else:
            for loser in screen["passed"]:
                out.append((SKIP, loser))     # nothing was worth taking
    return out


def rate(pairs):
    """Fit the ratings exactly, rather than approaching them by replay.

    Elo's familiar `K * (score - expected)` update is an *online estimator* of a
    logistic comparison model - the same model Bradley-Terry states directly. Run
    it as a sequential pass and the answer depends on the order the games arrive
    in; shuffling and replaying only averages that noise down, and it does not
    reach zero. Measured on this data, replay left cards drifting +-7 Elo and the
    skip line moving +-15 depending on the seed, which is too much for a number
    the chart draws as its centre.

    So solve the model instead. This is the standard minorization-maximization
    iteration for Bradley-Terry: given strengths p, a player's next strength is
    its win count over the sum of 1/(p_i + p_j) across its games. It is
    deterministic, monotonically convergent, and has no seed, no K and no epoch
    schedule to tune.

    The prior is the same idea as before, expressed exactly: every card carries
    PRIOR_GAMES/2 wins and PRIOR_GAMES/2 losses against a fixed anchor of
    strength 1, so a card seen twice is pulled toward the middle and an
    all-or-nothing record (Hotfix went 0 for 111) stays finite instead of
    running off to infinity.

    Ratings come back on the Elo scale, anchored so that the prior's opponent
    sits at exactly BASE.
    """
    opponents = collections.defaultdict(list)
    wins = collections.Counter()
    played = collections.Counter()
    for winner, loser in pairs:
        wins[winner] += 1
        played[winner] += 1
        played[loser] += 1
        opponents[winner].append(loser)
        opponents[loser].append(winner)

    names = list(played)
    strength = dict((name, 1.0) for name in names)
    half_prior = PRIOR_GAMES / 2.0
    anchor = 1.0

    iterations = 0
    for iterations in range(1, MAX_ITERS + 1):
        moved = 0.0
        updated = {}
        for name in names:
            own = strength[name]
            # real games, plus the prior's half-wins and half-losses vs anchor
            denom = half_prior * 2.0 / (own + anchor)
            for other in opponents[name]:
                denom += 1.0 / (own + strength[other])
            numer = wins[name] + half_prior
            new = numer / denom if denom > 0.0 else own
            updated[name] = new
            change = abs(math.log(new) - math.log(own))
            if change > moved:
                moved = change
        strength = updated
        if moved < TOLERANCE:
            break

    rating = dict((name, BASE + 400.0 * math.log10(strength[name] / anchor))
                  for name in names)
    return rating, played, iterations


def tally(screens):
    offered = collections.Counter()
    taken = collections.Counter()
    for screen in screens:
        for card in screen["picked"]:
            offered[card] += 1
            taken[card] += 1
        for card in screen["passed"]:
            offered[card] += 1
    return offered, taken


def table(screens):
    pairs = comparisons(screens)
    rating, _played, epochs = rate(pairs)
    offered, taken = tally(screens)
    rows = []
    for card, n in offered.items():
        rows.append({
            "card": card,
            "elo": int(round(rating.get(card, BASE))),
            "offered": n,
            "taken": taken.get(card, 0),
            "pick_rate": int(round(100.0 * taken.get(card, 0) / n)),
        })
    rows.sort(key=lambda row: (-row["elo"], row["card"]))
    return rows, int(round(rating.get(SKIP, BASE))), len(pairs), epochs


def pretty(name):
    return name.replace("_", " ").title()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", action="store_true", help="print instead of writing")
    parser.add_argument("--top", type=int, default=25)
    args = parser.parse_args()

    screens, stats = load_choices()
    print("A10 runs %d | screens %d | offers %d | skipped %d | shop screens dropped %d"
          % (stats["runs"], stats["screens"], stats["offers"],
             stats["skipped_screens"], stats["shop_screens_dropped"]))

    overall, skip_elo, pair_count, epochs = table(screens)
    print("overall: %d cards from %d head-to-heads in %d iterations, SKIP sits at %d"
          % (len(overall), pair_count, epochs, skip_elo))

    by_character = {}
    for character in sorted(set(s["character"] for s in screens)):
        subset = [s for s in screens if s["character"] == character]
        rows, skip_c, pairs_c, _ = table(subset)
        by_character[character] = {"rows": rows, "skip": skip_c, "pairs": pairs_c}
        print("  %-12s %4d cards, %5d head-to-heads, SKIP %d"
              % (character, len(rows), pairs_c, skip_c))

    if args.report:
        print("\n=== overall top %d ===" % args.top)
        for row in overall[:args.top]:
            print("  %5d  %-30s %3d/%-3d  %3d%%"
                  % (row["elo"], pretty(row["card"]), row["taken"],
                     row["offered"], row["pick_rate"]))
        print("\n=== overall bottom 12 ===")
        for row in overall[-12:]:
            print("  %5d  %-30s %3d/%-3d  %3d%%"
                  % (row["elo"], pretty(row["card"]), row["taken"],
                     row["offered"], row["pick_rate"]))
        return 0

    payload = {
        "runs": stats["runs"],
        "screens": stats["screens"],
        "offers": stats["offers"],
        "skipped_screens": stats["skipped_screens"],
        "shop_screens_dropped": stats["shop_screens_dropped"],
        "base": int(BASE),
        "overall": {"rows": overall, "skip": skip_elo, "pairs": pair_count},
        "by_character": by_character,
    }
    with io.open(OUT_JS, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("const CARD_ELO = ")
        json.dump(payload, handle, indent=2)
        handle.write(";\n")
    print("wrote %s" % os.path.relpath(OUT_JS, ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
