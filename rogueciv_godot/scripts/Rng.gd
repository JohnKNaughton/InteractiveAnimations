class_name Rng
extends RefCounted

## A small seeded generator, so a seed always rebuilds the same world.
## Deliberately separate from randi() — visual jitter must never disturb it.

var _state: int = 1


func _init(seed_value: int = 1) -> void:
	_state = seed_value & 0x7FFFFFFF
	if _state == 0:
		_state = 1


func state() -> int:
	return _state


func set_state(v: int) -> void:
	_state = v & 0x7FFFFFFF
	if _state == 0:
		_state = 1


func nextf() -> float:
	# xorshift32, then scaled into [0,1)
	_state ^= (_state << 13) & 0x7FFFFFFF
	_state ^= _state >> 17
	_state ^= (_state << 5) & 0x7FFFFFFF
	_state = _state & 0x7FFFFFFF
	if _state == 0:
		_state = 1
	return float(_state) / 2147483647.0


func rangef(a: float, b: float) -> float:
	return a + (b - a) * nextf()


func irange(a: int, b: int) -> int:
	## inclusive of both ends
	return a + int(nextf() * float(b - a + 1))


func below(n: int) -> int:
	return int(nextf() * float(n))


func chance(p: float) -> bool:
	return nextf() < p


func pick(arr: Array):
	if arr.is_empty():
		return null
	return arr[below(arr.size())]


func shuffle(arr: Array) -> Array:
	for i in range(arr.size() - 1, 0, -1):
		var j := below(i + 1)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t
	return arr
