extends Node

## Every table the game is made of. Autoloaded as `Data`.
## Nothing in here has behaviour: rules read these and act.

# =========================================================================
#  Run shape
# =========================================================================
const MAX_TURNS := 100
const NUM_RIVALS := 3
const BASE_CITY_CAP := 4
const BT_PER_AGE := 3          ## breakthroughs needed to advance one age
const HP_MAX := 100
const MAP_RADIUS := 10

const AGES := [
	{"name": "Dawn",   "sub": "stone and story"},
	{"name": "Bronze", "sub": "the first kingdoms"},
	{"name": "Iron",   "sub": "law, legion and road"},
	{"name": "Sail",   "sub": "powder and horizon"},
	{"name": "Steam",  "sub": "smoke and iron rails"},
	{"name": "Atomic", "sub": "the last age"},
]
const LAST_AGE := 5


## Progress needed for the nth breakthrough (0-based; 18 in a run).
static func bt_cost(n: int) -> int:
	return int(round(18.0 + 9.5 * n + 1.55 * n * n))


static func food_needed(pop: int) -> int:
	return int(round(14.0 + 7.0 * pop + pow(float(pop), 1.8)))


# =========================================================================
#  Terrain
# =========================================================================
## y = Vector3i(food, production, gold)
const TERRAIN := {
	"ocean":  {"name": "Ocean",     "y": Vector3i(1,0,1), "water": true},
	"coast":  {"name": "Coast",     "y": Vector3i(2,0,2), "water": true},
	"lake":   {"name": "Lake",      "y": Vector3i(3,0,1), "water": true},
	"grass":  {"name": "Grassland", "y": Vector3i(3,0,0), "water": false},
	"plains": {"name": "Plains",    "y": Vector3i(2,1,0), "water": false},
	"desert": {"name": "Desert",    "y": Vector3i(0,0,0), "water": false},
	"tundra": {"name": "Tundra",    "y": Vector3i(1,0,0), "water": false},
	"snow":   {"name": "Snow",      "y": Vector3i(0,0,0), "water": false},
}

const ELEV := {
	"flat": {"name": "",         "y": Vector3i(0,0,0),  "move": 1, "def": 0.0},
	"hill": {"name": "Hills",    "y": Vector3i(-1,2,0), "move": 2, "def": 0.25},
	"mtn":  {"name": "Mountain", "y": Vector3i(0,0,0),  "move": 9, "def": 0.0,
			 "blocks": true, "impassable": true},
}

const FEATURE := {
	"forest": {"name": "Forest",     "y": Vector3i(0,1,0),  "move": 2, "def": 0.25, "blocks": true},
	"jungle": {"name": "Jungle",     "y": Vector3i(1,0,0),  "move": 2, "def": 0.25, "blocks": true},
	"marsh":  {"name": "Marsh",      "y": Vector3i(1,-1,0), "move": 2, "def": -0.25},
	"oasis":  {"name": "Oasis",      "y": Vector3i(3,0,1),  "move": 1, "def": 0.0},
	"flood":  {"name": "Floodplain", "y": Vector3i(2,0,0),  "move": 1, "def": 0.0},
	"ice":    {"name": "Ice",        "y": Vector3i(0,0,0),  "move": 9, "def": 0.0,
			   "impassable": true},
}


# =========================================================================
#  Resources.  kind: b = bonus, l = luxury, s = strategic (gates a unit)
# =========================================================================
const RESOURCE := {
	"wheat":   {"name": "Wheat",   "kind": "b", "y": Vector3i(1,0,0), "on": ["plains","grass"]},
	"cattle":  {"name": "Cattle",  "kind": "b", "y": Vector3i(1,1,0), "on": ["grass"], "flat": true},
	"sheep":   {"name": "Sheep",   "kind": "b", "y": Vector3i(1,1,0), "on": ["grass","plains","desert"], "hill": true},
	"deer":    {"name": "Deer",    "kind": "b", "y": Vector3i(1,1,0), "on": ["tundra","grass","plains"], "needs_feature": "forest"},
	"fish":    {"name": "Fish",    "kind": "b", "y": Vector3i(2,0,1), "on": ["coast"]},
	"stone":   {"name": "Stone",   "kind": "b", "y": Vector3i(0,2,0), "on": ["plains","tundra","grass","desert"]},
	"gems":    {"name": "Gems",    "kind": "l", "y": Vector3i(0,0,4), "on": ["desert","plains"]},
	"silk":    {"name": "Silk",    "kind": "l", "y": Vector3i(0,0,3), "on": ["grass","plains"], "needs_feature": "forest"},
	"spice":   {"name": "Spices",  "kind": "l", "y": Vector3i(1,0,3), "on": ["grass","plains"], "needs_feature": "jungle"},
	"ivory":   {"name": "Ivory",   "kind": "l", "y": Vector3i(0,1,3), "on": ["plains","desert","grass"]},
	"incense": {"name": "Incense", "kind": "l", "y": Vector3i(0,0,4), "on": ["desert","plains"]},
	"horses":  {"name": "Horses",  "kind": "s", "y": Vector3i(1,1,0), "on": ["grass","plains","tundra"], "flat": true, "age": 0},
	"iron":    {"name": "Iron",    "kind": "s", "y": Vector3i(0,2,0), "on": ["grass","plains","tundra","desert","snow"], "age": 0},
	"niter":   {"name": "Niter",   "kind": "s", "y": Vector3i(1,1,0), "on": ["plains","desert","grass","tundra"], "age": 3},
	"oil":     {"name": "Oil",     "kind": "s", "y": Vector3i(0,3,0), "on": ["desert","tundra","snow","coast"], "age": 5},
	"uranium": {"name": "Uranium", "kind": "s", "y": Vector3i(0,2,0), "on": ["desert","tundra","snow","plains","grass"], "age": 5},
}


# =========================================================================
#  Units.  cls: melee | ranged | siege | mounted | recon | settler
# =========================================================================
const UNIT := {
	"settler":  {"name": "Settler", "cls": "settler", "age": 0, "cost": 44, "str": 0, "mv": 2,
				 "glyph": "settler", "desc": "Founds a city. Costs the city that trains it one population."},
	"scout":    {"name": "Scout", "cls": "recon", "age": 0, "cost": 24, "str": 10, "mv": 4,
				 "glyph": "scout", "ignore_terrain": true, "sight": 3,
				 "desc": "Fast, far-sighted, and hopeless in a fight."},
	"warrior":  {"name": "Warrior", "cls": "melee", "age": 0, "cost": 30, "str": 20, "mv": 2, "glyph": "sword"},
	"slinger":  {"name": "Slinger", "cls": "ranged", "age": 0, "cost": 30, "str": 8, "mv": 2,
				 "rs": 16, "rng": 2, "glyph": "sling"},

	"spearman": {"name": "Spearman", "cls": "melee", "age": 1, "cost": 46, "str": 28, "mv": 2,
				 "glyph": "spear", "vs_mounted": true, "desc": "Doubles its strength against a mounted attacker."},
	"archer":   {"name": "Archer", "cls": "ranged", "age": 1, "cost": 48, "str": 16, "mv": 2,
				 "rs": 26, "rng": 2, "glyph": "bow"},
	"horseman": {"name": "Horseman", "cls": "mounted", "age": 1, "cost": 56, "str": 32, "mv": 4,
				 "glyph": "horse", "req": "horses"},

	"legion":   {"name": "Legion", "cls": "melee", "age": 2, "cost": 74, "str": 42, "mv": 2,
				 "glyph": "gladius", "req": "iron"},
	"crossbow": {"name": "Crossbow", "cls": "ranged", "age": 2, "cost": 78, "str": 26, "mv": 2,
				 "rs": 42, "rng": 2, "glyph": "xbow"},
	"knight":   {"name": "Knight", "cls": "mounted", "age": 2, "cost": 92, "str": 52, "mv": 4,
				 "glyph": "knight", "req": "horses"},
	"catapult": {"name": "Catapult", "cls": "siege", "age": 2, "cost": 80, "str": 24, "mv": 1,
				 "rs": 36, "rng": 2, "glyph": "catapult", "vs_city": 1.0,
				 "desc": "Ruinous against walls, feeble in the open."},

	"musket":   {"name": "Musketeer", "cls": "melee", "age": 3, "cost": 116, "str": 58, "mv": 2,
				 "glyph": "musket", "req": "niter", "gunpowder": true},
	"bombard":  {"name": "Bombard", "cls": "siege", "age": 3, "cost": 124, "str": 42, "mv": 1,
				 "rs": 58, "rng": 2, "glyph": "bombard", "vs_city": 1.6, "req": "niter", "gunpowder": true},
	"cuirass":  {"name": "Cuirassier", "cls": "mounted", "age": 3, "cost": 132, "str": 66, "mv": 4,
				 "glyph": "knight", "req": "horses"},

	"rifle":    {"name": "Rifleman", "cls": "melee", "age": 4, "cost": 154, "str": 74, "mv": 2,
				 "glyph": "rifle", "gunpowder": true},
	"artillery":{"name": "Artillery", "cls": "siege", "age": 4, "cost": 172, "str": 58, "mv": 1,
				 "rs": 74, "rng": 3, "glyph": "arty", "vs_city": 1.2, "gunpowder": true},
	"cavalry":  {"name": "Cavalry", "cls": "mounted", "age": 4, "cost": 180, "str": 82, "mv": 5,
				 "glyph": "horse", "req": "horses"},

	"infantry": {"name": "Infantry", "cls": "melee", "age": 5, "cost": 204, "str": 94, "mv": 2,
				 "glyph": "infantry", "gunpowder": true},
	"rocket":   {"name": "Rocket Battery", "cls": "siege", "age": 5, "cost": 232, "str": 74, "mv": 2,
				 "rs": 96, "rng": 3, "glyph": "rocket", "vs_city": 1.2, "gunpowder": true},
	"tank":     {"name": "Tank", "cls": "mounted", "age": 5, "cost": 250, "str": 112, "mv": 5,
				 "glyph": "tank", "req": "oil"},

	# --- unique units: each replaces one of the above for one civilisation ---
	"siegetower": {"name": "Siege Tower", "cls": "siege", "age": 2, "cost": 80, "str": 30, "mv": 2,
				   "rs": 46, "rng": 2, "glyph": "catapult", "vs_city": 1.3, "replaces": "catapult",
				   "desc": "Assyrian. A Catapult that keeps pace with the army and hits harder."},
	"chariot":    {"name": "War Chariot", "cls": "mounted", "age": 1, "cost": 54, "str": 38, "mv": 4,
				   "glyph": "chariot", "replaces": "horseman",
				   "desc": "Kemetite. A Horseman that needs no Horses and strikes harder."},
	"berserker":  {"name": "Berserker", "cls": "melee", "age": 2, "cost": 74, "str": 50, "mv": 3,
				   "glyph": "axe", "ignore_terrain": true, "replaces": "legion",
				   "desc": "Norse. A Legion needing no Iron, faster, and heedless of rough ground."},
	"elephant":   {"name": "War Elephant", "cls": "mounted", "age": 2, "cost": 90, "str": 64, "mv": 3,
				   "glyph": "elephant", "replaces": "knight",
				   "desc": "Mauryan. A Knight needing no Horses: slower, but far heavier."},
	"chukonu":    {"name": "Chu-Ko-Nu", "cls": "ranged", "age": 2, "cost": 78, "str": 30, "mv": 2,
				   "rs": 50, "rng": 2, "glyph": "xbow", "replaces": "crossbow",
				   "desc": "Tang. A Crossbow that fires twice as fast."},
	"eagle":      {"name": "Eagle Warrior", "cls": "melee", "age": 0, "cost": 30, "str": 26, "mv": 3,
				   "glyph": "eagle", "replaces": "warrior",
				   "desc": "Mexica. A Warrior, swifter and fiercer."},
}

## Upgrade paths, oldest first. `null` means that age has no unit of the line.
const LINES := {
	"melee":   ["warrior", "spearman", "legion", "musket", "rifle", "infantry"],
	"ranged":  ["slinger", "archer", "crossbow", null, "artillery", "rocket"],
	"mounted": [null, "horseman", "knight", "cuirass", "cavalry", "tank"],
	"siege":   [null, null, "catapult", "bombard", "artillery", "rocket"],
}


# =========================================================================
#  Promotions — a unit that survives long enough gets to choose one of two.
#  This is the second draft in the game, and the reason veterans feel owned.
# =========================================================================
const PROMOTION := {
	"shock":   {"name": "Shock", "desc": "+7 strength when attacking.",
				"for": ["melee","mounted","recon"], "m": {"atk": 7}},
	"bulwark": {"name": "Bulwark", "desc": "+7 strength when defending.",
				"for": ["melee","ranged","siege","mounted","recon"], "m": {"def": 7}},
	"drill":   {"name": "Drill", "desc": "+1 movement.",
				"for": ["melee","ranged","siege","mounted","recon"], "m": {"mv": 1}},
	"marksman":{"name": "Marksman", "desc": "+1 attack range.",
				"for": ["ranged","siege"], "m": {"rng": 1}},
	"zeal":    {"name": "Zeal", "desc": "Heal 35 HP after destroying an enemy.",
				"for": ["melee","ranged","siege","mounted","recon"], "m": {"heal_kill": 35}},
	"vanguard":{"name": "Vanguard", "desc": "Ignores rough terrain.",
				"for": ["melee","mounted","recon"], "m": {"ignore_terrain": 1}},
	"sapper":  {"name": "Sapper", "desc": "+50% strength against cities.",
				"for": ["melee","siege"], "m": {"vs_city": 0.5}},
	"skirmish":{"name": "Skirmisher", "desc": "May move again after attacking.",
				"for": ["mounted","recon"], "m": {"move_after": 1}},
	"ambush":  {"name": "Ambush", "desc": "+30% strength in forest, jungle and hills.",
				"for": ["melee","ranged","mounted","recon"], "m": {"rough": 0.30}},
	"siegecraft":{"name": "Siegecraft", "desc": "+12 ranged strength.",
				"for": ["ranged","siege"], "m": {"rs": 12}},
}
## experience needed for rank 1, 2, 3
const RANK_XP := [15, 45, 90]
const RANK_NAME := ["", "Veteran", "Elite", "Legendary"]


# =========================================================================
#  Structures and wonders
# =========================================================================
const STRUCTURE := {
	"granary":   {"name": "Granary", "age": 0, "cost": 62, "desc": "+2 food", "f": {"food": 2}},
	"barracks":  {"name": "Barracks", "age": 0, "cost": 64, "desc": "+20% unit production; new units start trained",
				  "f": {"unit_pct": 0.20, "xp": 15}},
	"walls":     {"name": "Walls", "age": 0, "cost": 70, "desc": "+40 city defence, +5 strength",
				  "f": {"hp": 40, "def": 5}},
	"library":   {"name": "Library", "age": 1, "cost": 92, "desc": "+3 progress", "f": {"sci": 3}},
	"market":    {"name": "Market", "age": 1, "cost": 92, "desc": "+3 gold", "f": {"gold": 3}},
	"harbour":   {"name": "Harbour", "age": 1, "cost": 88, "desc": "+1 food and +1 gold on every water tile",
				  "coastal": true, "f": {"water": 1}},
	"workshop":  {"name": "Workshop", "age": 2, "cost": 124, "desc": "+25% production", "f": {"prod_pct": 0.25}},
	"aqueduct":  {"name": "Aqueduct", "age": 2, "cost": 114, "desc": "+3 food; the city may grow past 8",
				  "f": {"food": 3, "max_pop": 8}},
	"amphi":     {"name": "Amphitheatre", "age": 2, "cost": 120, "desc": "+2 gold, +2 progress, borders reach further",
				  "f": {"gold": 2, "sci": 2, "radius": 1}},
	"university":{"name": "University", "age": 3, "cost": 166, "desc": "+6 progress", "f": {"sci": 6}},
	"bank":      {"name": "Bank", "age": 3, "cost": 166, "desc": "+6 gold", "f": {"gold": 6}},
	"fortress":  {"name": "Fortress", "age": 3, "cost": 156, "desc": "+90 city defence, +12 strength",
				  "f": {"hp": 90, "def": 12}},
	"factory":   {"name": "Factory", "age": 4, "cost": 228, "desc": "+40% production", "f": {"prod_pct": 0.40}},
	"lab":       {"name": "Laboratory", "age": 5, "cost": 300, "desc": "+12 progress", "f": {"sci": 12}},
}

## One of each may exist in the whole world.
const WONDER := {
	"greatlib":  {"name": "The Great Library", "age": 1, "cost": 210,
				  "desc": "A Breakthrough at once, and +5 progress here.",
				  "f": {"sci": 5}, "once": "free_bt"},
	"gardens":   {"name": "The Hanging Gardens", "age": 1, "cost": 210,
				  "desc": "+2 food in every city you hold.", "emp": {"p_food": 2}},
	"colossus":  {"name": "The Colossus", "age": 1, "cost": 190, "coastal": true,
				  "desc": "+7 gold here, and +1 gold on every water tile you work.",
				  "f": {"gold": 7}, "emp": {"t_gold_water": 1}},
	"terracotta":{"name": "The Terracotta Army", "age": 2, "cost": 270,
				  "desc": "Every unit you own gains a rank; new units start seasoned.",
				  "emp": {"xp_start": 30}, "once": "rank_all"},
	"bazaar":    {"name": "The Grand Bazaar", "age": 2, "cost": 270,
				  "desc": "+35% gold across the empire.", "emp": {"pct_gold": 0.35}},
	"magellan":  {"name": "Magellan's Fleet", "age": 3, "cost": 320, "coastal": true,
				  "desc": "Your units may cross water, and all gain +1 movement.",
				  "emp": {"embark": 1, "mv_all": 1}},
	"peace":     {"name": "The Statue of Peace", "age": 3, "cost": 300,
				  "desc": "Every rival warms to you greatly, and none may demand tribute.",
				  "emp": {"diplo": 35, "no_tribute": 1}, "once": "peace"},
	"ironworks": {"name": "The Ironworks", "age": 4, "cost": 430,
				  "desc": "+10 production here, +15% everywhere.",
				  "f": {"prod": 10}, "emp": {"pct_prod": 0.15}},
	"rail":      {"name": "The Transcontinental Rail", "age": 4, "cost": 410,
				  "desc": "+3 movement inside your borders, +6 gold in every city.",
				  "emp": {"mv_border": 3, "p_gold": 6}},
	"beacon":    {"name": "The Beacon", "age": 5, "cost": 820, "req": "uranium", "victory": true,
				  "desc": "A light to outlast the age. Finishing it wins the run."},
}
