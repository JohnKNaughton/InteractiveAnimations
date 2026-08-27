class_name Tile
extends RefCounted

var coord: Vector2i
var pos: Vector2                 ## world position at hex size 1
var height: float = 0.0

var terrain: String = "ocean"
var elev: String = "flat"
var feature: String = ""         ## "" for none
var resource: String = ""        ## "" for none
var rivers: Array[int] = []      ## directions a river runs to
var continent: int = 0

var owner_id: int = -1
var city = null                  ## City, or null
var units: Array[Unit] = []      ## at most one military and one civilian

var improve: int = 0             ## tiles get better as they are worked
var worked_turns: int = 0
var worked_by: int = -1          ## city id, or -1

var ruin: bool = false
var camp: bool = false

# scratch, used by rendering and territory
var screen: Vector2 = Vector2.ZERO
var claim: int = 9999


func is_water() -> bool:
	return Data.TERRAIN[terrain].get("water", false)


func has_river() -> bool:
	return not rivers.is_empty()


func is_impassable() -> bool:
	if Data.ELEV[elev].get("impassable", false):
		return true
	if feature != "" and Data.FEATURE[feature].get("impassable", false):
		return true
	return false


func blocks_sight() -> bool:
	if Data.ELEV[elev].get("blocks", false):
		return true
	if feature != "" and Data.FEATURE[feature].get("blocks", false):
		return true
	return false


func move_cost() -> int:
	var c: int = Data.ELEV[elev]["move"]
	if feature != "":
		c = maxi(c, Data.FEATURE[feature]["move"])
	return c


func defence_bonus() -> float:
	var d: float = Data.ELEV[elev]["def"]
	if feature != "":
		d += Data.FEATURE[feature]["def"]
	return d


func is_rough() -> bool:
	return elev == "hill" or feature == "forest" or feature == "jungle"


func display_name() -> String:
	var bits: Array[String] = []
	if feature != "" and Data.FEATURE[feature]["name"] != "":
		bits.append(Data.FEATURE[feature]["name"])
	if Data.ELEV[elev]["name"] != "":
		bits.append(Data.ELEV[elev]["name"])
	bits.append(Data.TERRAIN[terrain]["name"])
	var s := " ".join(bits)
	if has_river():
		s += " on a river"
	return s


func military() -> Unit:
	for u in units:
		if Data.UNIT[u.type]["cls"] != "settler":
			return u
	return null


func civilian() -> Unit:
	for u in units:
		if Data.UNIT[u.type]["cls"] == "settler":
			return u
	return null
