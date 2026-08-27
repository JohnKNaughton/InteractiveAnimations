class_name Player
extends RefCounted

var id: int = 0
var is_human: bool = false
var is_barbarian: bool = false
var alive: bool = true

var leader: Dictionary = {}
var name: String = ""
var adjective: String = ""
var colour: Color = Color.WHITE

var gold: int = 30
var sci: int = 0
var bt_done: int = 0
var age: int = 0

var edicts: Array[String] = []
var wonders: Array[String] = []
var cities: Array[City] = []
var units: Array[Unit] = []
var capital: City = null

var m: Dictionary = {}            ## modifier bag; read through mod()
var seen: Dictionary = {}         ## Vector2i -> true, used as a set
var vis: Dictionary = {}
var dip: Dictionary = {}          ## other player id -> relationship

var kills: int = 0
var captured_capitals: int = 0
var score: int = 0
var name_index: int = 0
var lost_all_on: int = -1

# AI scratch
var objective_turn: int = -1
var objective: Vector2i = Vector2i(9999, 9999)
var has_objective: bool = false
var beacon_announced: bool = false


func mod(key: String) -> float:
	return float(m.get(key, 0.0))


func add_mods(bag: Dictionary) -> void:
	for k in bag:
		m[k] = float(m.get(k, 0.0)) + float(bag[k])


func subtract_mods(bag: Dictionary) -> void:
	for k in bag:
		m[k] = float(m.get(k, 0.0)) - float(bag[k])


func city_cap() -> int:
	return Data.BASE_CITY_CAP + int(mod("city_cap"))


func relation(other_id: int) -> Dictionary:
	if not dip.has(other_id):
		dip[other_id] = {
			"met": false, "war": false, "attitude": 0.0, "truce": 0,
			"last_tribute": -99, "paid": 0, "refused": 0, "denounced": false,
		}
	return dip[other_id]


func next_city_name() -> String:
	var list: Array = leader.get("cities", ["City"])
	var n: String = list[name_index % list.size()]
	name_index += 1
	if name_index > list.size():
		return n + " " + str(1 + int((name_index - 1) / float(list.size())))
	return n
