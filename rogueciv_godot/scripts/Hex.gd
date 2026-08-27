class_name Hex
extends RefCounted

## Pointy-top hexagons in axial coordinates (q, r).
## World space: x = size * sqrt(3) * (q + r/2),  y = size * 1.5 * r

const SQ3 := 1.7320508075688772

## The six neighbour directions, in the order used everywhere else.
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
]


static func to_world(c: Vector2i, size: float) -> Vector2:
	return Vector2(size * SQ3 * (c.x + c.y * 0.5), size * 1.5 * c.y)


static func to_world_qr(q: int, r: int, size: float) -> Vector2:
	return Vector2(size * SQ3 * (q + r * 0.5), size * 1.5 * r)


static func from_world(p: Vector2, size: float) -> Vector2i:
	var q := (p.x * SQ3 / 3.0 - p.y / 3.0) / size
	var r := (p.y * 2.0 / 3.0) / size
	return _round_axial(q, r)


static func _round_axial(qf: float, rf: float) -> Vector2i:
	# round in cube space so the result is always a real hex
	var x := qf
	var z := rf
	var y := -x - z
	var rx := roundf(x)
	var ry := roundf(y)
	var rz := roundf(z)
	var dx := absf(rx - x)
	var dy := absf(ry - y)
	var dz := absf(rz - z)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector2i(int(rx), int(rz))


static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return int((absi(dq) + absi(dr) + absi(dq + dr)) / 2.0)


## Every coordinate within `n` rings of `c`, inclusive of `c` itself.
static func in_range(c: Vector2i, n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dq in range(-n, n + 1):
		var lo := maxi(-n, -dq - n)
		var hi := mini(n, -dq + n)
		for dr in range(lo, hi + 1):
			out.append(Vector2i(c.x + dq, c.y + dr))
	return out


## Just the coordinates exactly `n` rings out.
static func ring(c: Vector2i, n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if n <= 0:
		out.append(c)
		return out
	for coord in in_range(c, n):
		if distance(coord, c) == n:
			out.append(coord)
	return out


## The six corners of a hex, in world space, relative to its centre.
static func corners(size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i + 30.0)
		pts.append(Vector2(cos(a), sin(a)) * size)
	return pts


static func polygon(centre: Vector2, size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i + 30.0)
		pts.append(centre + Vector2(cos(a), sin(a)) * size)
	return pts


## The shared edge between a hex and its neighbour in direction `d`,
## as the two corner points, relative to the hex centre.
static func edge(d: int, size: float) -> Array[Vector2]:
	var c := corners(size)
	return [c[(5 - d + 6) % 6], c[(6 - d) % 6]]


## A straight line of hexes from a to b, endpoints included.
static func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var n := distance(a, b)
	var out: Array[Vector2i] = []
	if n == 0:
		out.append(a)
		return out
	var ax := float(a.x)
	var az := float(a.y)
	var ay := -ax - az
	var bx := float(b.x)
	var bz := float(b.y)
	var by := -bx - bz
	for i in range(n + 1):
		var t := float(i) / float(n)
		var x := ax + (bx - ax) * t
		var y := ay + (by - ay) * t
		var z := az + (bz - az) * t
		var rx := roundf(x)
		var ry := roundf(y)
		var rz := roundf(z)
		var dx := absf(rx - x)
		var dy := absf(ry - y)
		var dz := absf(rz - z)
		if dx > dy and dx > dz:
			rx = -ry - rz
		elif dy > dz:
			ry = -rx - rz
		else:
			rz = -rx - ry
		out.append(Vector2i(int(rx), int(rz)))
	return out


## A stable per-tile hash, for visual jitter that never touches the game RNG.
static func hash2(x: int, y: int) -> float:
	var h := (x * 374761393 + y * 668265263) ^ 0x5bf03635
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(absi(h) % 1000000) / 1000000.0
