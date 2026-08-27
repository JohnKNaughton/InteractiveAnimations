class_name Pal
extends RefCounted

## The look of the game: pop art.
##
## Flat saturated colour, a heavy black keyline around everything, and Ben-Day
## dots where a painting would put shading. There are no gradients and no soft
## shadows anywhere — if something needs to read as raised, it gets a thicker
## line or a block of dots, never a blur.
##
## The palette is deliberately small. Six inks and a paper. Anything that wants
## a new colour is almost always better served by an existing one at a
## different dot density.

## Kept so older drawing code that asks for a light direction still works; the
## pop art pass uses it only to decide which side gets the dots.
const LIGHT := Vector2(-0.52, -0.85)

# --- the six inks ---------------------------------------------------------
const INK        := Color("#141118")   ## the keyline. Everything is drawn over it.
const PAPER      := Color("#fff6e3")   ## newsprint cream
const PAPER_HI   := Color("#ffffff")
const RED        := Color("#ec1c34")
const YELLOW     := Color("#ffcf00")
const BLUE       := Color("#0f5fc4")
const CYAN       := Color("#3fb8e8")
const PINK       := Color("#ff5fa2")

# --- the world beyond the map --------------------------------------------
const VOID       := Color("#171425")   ## past the edge of the world
const VOID_DEEP  := Color("#100e1a")
const UNKNOWN    := Color("#241f33")   ## in bounds, never walked
const UNKNOWN_EDGE := Color("#3b3350")

# --- panels and lettering -------------------------------------------------
const PANEL      := PAPER
const PANEL_HI   := PAPER_HI
const PANEL_EDGE := INK
const INK_SOFT   := Color("#5c5468")
const INK_FAINT  := Color("#918899")
const ACCENT     := RED                ## the "look here" colour
const ACCENT_DEEP:= Color("#b8122a")
const ACCENT_DIM := Color("#ffd9de")
const TEAL       := Color("#00a99d")
const GOOD       := Color("#00a03c")
const BAD        := RED
const WARN       := Color("#ff8a00")
const SHADOW     := Color(0.08, 0.07, 0.09, 1.0)

# --- terrain: flat, loud, and few -----------------------------------------
const OCEAN    := Color("#0f5fc4")
const OCEAN_DEEP := Color("#0a3f8c")
const COAST    := Color("#3fb8e8")
const COAST_HI := Color("#7fd6f5")
const LAKE     := Color("#4fc3ea")
const SHORE    := Color("#ffe9a8")
const GRASS    := Color("#7ac943")
const PLAINS   := Color("#ffcf00")
const DESERT   := Color("#ffe08a")
const TUNDRA   := Color("#c9bfd4")
const SNOW     := Color("#fffdf7")
const MOUNTAIN := Color("#9a8fa8")

const FOREST   := Color("#2e9247")
const FOREST_HI:= Color("#57c05e")
const JUNGLE   := Color("#00843d")
const JUNGLE_HI:= Color("#3fae52")
const MARSH    := Color("#8fa83c")
const RIVER    := Color("#3fb8e8")
const RIVER_DEEP := Color("#0f5fc4")
const ICE      := Color("#eef7ff")

const TERRAIN_COLOUR := {
	"ocean": OCEAN, "coast": COAST, "lake": LAKE, "grass": GRASS,
	"plains": PLAINS, "desert": DESERT, "tundra": TUNDRA, "snow": SNOW,
}

# --- the six civilisations, poster-bright ---------------------------------
const CIV_COLOURS := {
	"crimson": Color("#ec1c34"),
	"indigo":  Color("#2b3ec9"),
	"teal":    Color("#00a99d"),
	"amber":   Color("#ff9500"),
	"plum":    Color("#b13fd4"),
	"olive":   Color("#7ac943"),
}
const BARBARIAN := Color("#6b5f4e")

# --- yields ---------------------------------------------------------------
const FOOD := Color("#00a03c")
const PROD := Color("#ff8a00")
const GOLD := Color("#ffcf00")
const SCI  := Color("#0f5fc4")

static var _font_ui: Font
static var _font_bold: Font
static var _font_display: Font


static func ui(weight := 0) -> Font:
	if weight == 1:
		return bold()
	if _font_ui == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Segoe UI Semibold", "Segoe UI", "Inter", "Arial"])
		f.font_weight = 600
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		_font_ui = f
	return _font_ui


static func bold() -> Font:
	if _font_bold == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Segoe UI Black", "Arial Black", "Segoe UI Bold", "Arial"])
		f.font_weight = 900
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		_font_bold = f
	return _font_bold


static func display() -> Font:
	## Headlines. Pop art shouts, so the titles are a poster face, not a serif.
	if _font_display == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray([
			"Impact", "Haettenschweiler", "Arial Black", "Segoe UI Black", "Arial"])
		f.font_weight = 900
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		_font_display = f
	return _font_display


## Lighten (amt > 0) or darken (amt < 0) a colour, keeping alpha.
static func shade(c: Color, amt: float) -> Color:
	if amt >= 0.0:
		return Color(
			c.r + (1.0 - c.r) * amt,
			c.g + (1.0 - c.g) * amt,
			c.b + (1.0 - c.b) * amt, c.a)
	var k := 1.0 + amt
	return Color(c.r * k, c.g * k, c.b * k, c.a)


## In a flat style these are the *screen tint* pair, used sparingly: a lit face
## goes toward paper, a shaded one toward the keyline. Both stay fully
## saturated, because a pop art shadow is a different ink, not a darker one.
static func lit(c: Color, amt: float) -> Color:
	return c.lerp(PAPER_HI, clampf(amt, 0.0, 1.0) * 0.85)


static func shaded(c: Color, amt: float) -> Color:
	return c.lerp(INK, clampf(amt, 0.0, 1.0) * 0.75)


static func desaturate(c: Color, amt: float) -> Color:
	var g := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
	return Color(lerpf(c.r, g, amt), lerpf(c.g, g, amt), lerpf(c.b, g, amt), c.a)


static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


## How ground outside your sight is drawn: the same ink, printed badly —
## darker and washed toward the unknown, never lighter than lit ground.
static func remembered(c: Color) -> Color:
	return shade(desaturate(c, 0.58), -0.30).lerp(UNKNOWN, 0.18)


## The dot colour to print over a given ground. Pop art shades with a denser
## screen of the *same* ink, so this is the ground pushed toward the keyline.
static func dot_over(c: Color) -> Color:
	return shaded(c, 0.42)
