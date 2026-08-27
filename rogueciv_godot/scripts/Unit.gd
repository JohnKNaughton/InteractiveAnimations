class_name Unit
extends RefCounted

var id: int = 0
var owner_id: int = 0
var type: String = "warrior"
var coord: Vector2i

var hp: int = Data.HP_MAX
var mv: int = 0
var xp: int = 0
var rank: int = 0
var promos: Array[String] = []

var fortified: int = 0
var asleep: bool = false
var done: bool = false
var embarked: bool = false
var dead: bool = false

var has_goto: bool = false
var goto: Vector2i

var moved_this_turn: bool = false
var fought_this_turn: bool = false

# AI scratch
var site_target: Vector2i = Vector2i(9999, 9999)
var has_site: bool = false
var garrison_of: City = null

# render scratch: where the token is actually drawn, for movement tweening
var draw_pos: Vector2 = Vector2.ZERO
var draw_init: bool = false
# a brief lunge toward whatever it just struck
var lunge_dir: Vector2 = Vector2.ZERO
var lunge_at: float = -99.0


func def() -> Dictionary:
	return Data.UNIT[type]


func cls() -> String:
	return Data.UNIT[type]["cls"]


func is_civilian() -> bool:
	return cls() == "settler"


func promo_value(key: String) -> float:
	var total := 0.0
	for p in promos:
		var m: Dictionary = Data.PROMOTION[p]["m"]
		if m.has(key):
			total += float(m[key])
	return total


func has_promo(key: String) -> bool:
	return promo_value(key) > 0.0


func rank_name() -> String:
	return Data.RANK_NAME[rank]


func title() -> String:
	var n: String = Data.UNIT[type]["name"]
	if rank > 0:
		return Data.RANK_NAME[rank] + " " + n
	return n
