class_name City
extends RefCounted

var id: int = 0
var owner_id: int = 0
var coord: Vector2i
var name: String = "City"

var pop: int = 1
var food: int = 0
var prod: int = 0
var hp: int = 100
var max_hp: int = 100

var structures: Array[String] = []
var queue: Dictionary = {}       ## {"kind": "unit"|"structure"|"wonder", "id": String}
var effects: Dictionary = {}     ## aggregated structure effects
var worked: Array[Tile] = []     ## Tile refs

var focus: String = "balanced"   ## balanced | growth | work | trade
var is_capital: bool = false
var founded: int = 1
var just_taken: int = 0


func has(structure_id: String) -> bool:
	return structures.has(structure_id)


func is_building() -> bool:
	return not queue.is_empty()


func queue_name() -> String:
	if queue.is_empty():
		return ""
	match queue["kind"]:
		"unit": return Data.UNIT[queue["id"]]["name"]
		"structure": return Data.STRUCTURE[queue["id"]]["name"]
		_: return Data.WONDER[queue["id"]]["name"]
