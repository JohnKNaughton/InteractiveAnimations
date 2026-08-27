Making some fun visualizations for my portfolio and webpages. There is a loose theme of simulations and board games. 

Visualization 1: Monopoly End of Turn Landing Probabilities
Simulating the permutations of a game of Monopoly, by looking at how the probabilites of ending your turn on any given square evolve. 
The simulation uses a pseudo-Markov Chain, making some assumptions of player decisions based on two dominant strategies. 

RogueCiv (rogueciv.html) — the first prototype, kept for reference; the Godot version below is the one being worked on
A hex-grid 4X strategy game built as a roguelike: one hundred turns, six Ages, and eighteen Edicts drafted one-of-three.
The two you refuse are gone for the rest of the run, so a run is a build rather than a checklist. You pick one of three
leaders, settle a small continent alongside three rivals with their own agendas, and win by completing The Beacon in the
Atomic Age or by taking every rival capital. There are no worker units and no tile micromanagement — cities work their
own land from a focus you set with one click, and the city limit only rises through Edicts, so there is nothing to gain
by sprawling. Losing is quick and real: leave your capital open and the run can end by turn twenty-five.

RogueCiv in Godot (rogueciv_godot/)
The same game rebuilt as a Godot 4.6 project, with a deliberately minimalist presentation: a warm paper palette, flat
hexes, and unexplored ground left blank so the map appears as it is walked. The interface reveals itself as you play —
turn one shows a name, a treasury and one button, and the Age track, the Nations panel and the city list each arrive the
moment they first mean something. Units that survive long enough choose one of two promotions, so a veteran is something
you built. Double-click "Play RogueCiv.bat" to play, or open project.godot in Godot 4.6 and press F5. Runs are saved
after every turn, so you can stop and resume whenever.
