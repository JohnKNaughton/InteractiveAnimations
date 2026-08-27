# RogueCiv (Godot 4.6)

A hex-grid 4X built as a roguelike: one hundred turns, six Ages, and
eighteen Edicts drafted one-of-three. The two you refuse are gone for the
rest of the run, so a run is a build rather than a checklist.

## The look

Pop art. Flat saturated colour, a heavy black keyline around every tile and
every token, Ben-Day dots where a painting would put shading, and comic
lettering set in capitals with a hard offset shadow.

The rule that keeps it coherent: **nothing in the game is blurred.** No
gradients, no soft drop shadows, no vignette. Depth is line weight and dot
density, the way it is in print. `Pal.gd` holds the whole palette — six inks
and a paper — and `MapView._ground` / `_benday` / `_keyline` are the three
primitives everything on the map is built from. `Ui._sb` gives every panel the
same treatment, and `Ui._hard_shadow` is the only shadow in the codebase.

## Playing it

Double-click **`Play RogueCiv.bat`** in the folder above this one. It finds
Godot and launches straight into the game.

Failing that, open `project.godot` in Godot 4.6 and press F5, or run:

    godot --path rogueciv_godot

Your run is written to disk after **every turn**, so you can close the window
whenever you like and press **Continue** next time. **Esc** opens a menu with
resume, restart, a fresh run, and save-and-quit.

## The shape of a run

Progress fills the bar in the top strip. Each time it fills you get a
**Breakthrough** and draft one Edict from three; three Breakthroughs advance
the Age. Win by completing **The Beacon** in the Atomic Age (it needs Uranium
in your borders), by taking every rival capital, or by holding **half the
cities in the world**. If turn 100 arrives, the highest score takes it. Lose
every city and the run is over — which can happen by turn twenty-five if you
leave your capital open.

Units that survive long enough earn a **promotion you choose**, so a veteran
is something you built rather than something you happened to keep alive.

## A small army, on purpose

One unit to a tile makes a big army a chore to move rather than a pleasure to
command, so there is a **ceiling** on it: three soldiers, plus one for every
city you hold. The count sits in the top strip and turns red when it is full.
Settlers are not soldiers and do not count.

The ceiling does most of the design work. A run is fought with six or seven
units you know by name rather than fifteen you shuffle, the turn stays short
all the way to turn 100, and the way to field a larger army is to go and take
somebody's city — which makes conquest pay twice.

## Deliberately absent

No worker units and no tile micromanagement: land improves as your cities
work it, and each city picks its own tiles from a focus you set with one
click. The city limit is small and rises only through Edicts, so there is
nothing to gain by sprawling.

## Deliberately gradual

Nothing is on screen until it matters. Turn one shows a name, your treasury
and one button. The Age track appears with your first research, the Nations
panel when you first meet somebody, the Cities list when you hold more than
one. A single coaching line sits under the top bar and retires once you have
done the thing it describes.

## Controls

| | |
|---|---|
| Click a unit, then a tile | move (red rings are targets) |
| Space | next unit that still has orders |
| Enter | end the turn |
| F / S | fortify / sleep |
| C | jump to your capital |
| Esc | the menu (or clear the selection first) |
| Drag or WASD | pan · **Wheel** zoom |
| M | mute · **[** and **]** volume |

## Layout

    scripts/
      Data.gd, Edicts.gd     tables: ages, terrain, units, 72 edicts, leaders
      Hex.gd, Rng.gd, Pal.gd  hex maths, seeded RNG, the whole palette
      Tile/Unit/City/Player   the model
      World.gd                map generation, territory, sight
      Game.gd                 the rules (autoloaded as `Game`)
      AI.gd                   the rivals
      MapView.gd              all drawing, and what is selected
      Ui.gd                   the interface
      MiniMap.gd              the plan of the world, top right
      Snd.gd                  sound, synthesised at load
      Save.gd                 writing and resuming a run
      Tests.gd                headless checks

Nothing is loaded from disk: the art is vector drawing and the sound is
synthesised into buffers at startup.

## Tests

    godot --headless --path rogueciv_godot -- --test

94 checks covering map generation across seeds, the draft, promotions,
upgrades, siege mechanics, the army ceiling, six full AI-vs-AI games, saving
and resuming, the click-to-move path, and the requirement that a passive
player actually loses.

Every dev run (tests, screenshots) is **silent** and writes to a separate save
slot, so testing can never make a noise or overwrite a real run.

There are also dev flags for looking at things: `--shot <file>`, `--seed N`,
`--turns N --auto`, `--zoom N`, `--modal <name>`, `--select unit|city|settler`,
`--glyphs`, `--units`, `--boot`.

### Balance harness

    godot --headless --path rogueciv_godot -- --sim 16

Plays complete runs with every seat on the AI and prints the shape of a run —
units on the board and cities held at turns 20/40/60/80/100, how long runs
last, and how they end. Use it before and after any balance change; it is the
difference between tuning and guessing.
