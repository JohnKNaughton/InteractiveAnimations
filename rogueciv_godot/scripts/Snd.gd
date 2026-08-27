extends Node

## Every sound is synthesised into a small buffer at load. No assets,
## nothing to ship, and the whole palette fits on one screen.

const RATE := 22050
const VOICES := 8

var enabled := true
var master := 0.42
var _bank: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last: Dictionary = {}


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://rogueciv.cfg") == OK:
		enabled = bool(cfg.get_value("sound", "on", true))
		master = clampf(float(cfg.get_value("sound", "volume", master)), 0.0, 1.0)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_build_bank()


func play(cue: String) -> void:
	if not enabled or not _bank.has(cue):
		return
	# a stack of units resolving at once must not become a wall of noise
	var gap := 0.06 if cue in ["move", "hit", "select"] else 0.12
	var now := Time.get_ticks_msec() / 1000.0
	if _last.has(cue) and now - float(_last[cue]) < gap:
		return
	_last[cue] = now
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _bank[cue]
	p.volume_db = linear_to_db(master)
	p.play()


func toggle() -> bool:
	enabled = not enabled
	_remember()
	if enabled:
		play("select")
	return enabled


## Volume in eight steps, so it can be turned down rather than only off.
func nudge_volume(delta: float) -> float:
	master = clampf(master + delta, 0.0, 1.0)
	if master > 0.0:
		enabled = true
	_remember()
	play("select")
	return master


func _remember() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://rogueciv.cfg")
	cfg.set_value("sound", "on", enabled)
	cfg.set_value("sound", "volume", master)
	cfg.save("user://rogueciv.cfg")


# =========================================================================
#  Synthesis
# =========================================================================
class Buf:
	var d := PackedFloat32Array()

	func _init(seconds: float) -> void:
		d.resize(int(Snd.RATE * seconds))
		d.fill(0.0)

	func tone(freq: float, start: float, dur: float, vol: float,
			shape := "sine", slide_to := 0.0) -> void:
		var i0 := int(start * Snd.RATE)
		var n := int(dur * Snd.RATE)
		for i in n:
			var idx := i0 + i
			if idx < 0 or idx >= d.size():
				continue
			var t := float(i) / float(n)
			var f := freq
			if slide_to > 0.0:
				f = lerpf(freq, slide_to, t)
			var phase := TAU * f * (float(i) / Snd.RATE)
			var s := 0.0
			match shape:
				"square": s = 1.0 if sin(phase) >= 0.0 else -1.0
				"saw": s = fposmod(phase / TAU, 1.0) * 2.0 - 1.0
				"tri": s = asin(sin(phase)) * (2.0 / PI)
				_: s = sin(phase)
			# quick attack, exponential decay: percussive without a click
			var env := minf(1.0, t / 0.02) * pow(1.0 - t, 2.2)
			d[idx] += s * env * vol

	func noise(start: float, dur: float, vol: float, cutoff: float) -> void:
		var i0 := int(start * Snd.RATE)
		var n := int(dur * Snd.RATE)
		var last := 0.0
		# a one-pole low pass gives the burst some body
		var a := clampf(cutoff / float(Snd.RATE), 0.01, 0.99)
		var rs := RandomNumberGenerator.new()
		rs.seed = 12345
		for i in n:
			var idx := i0 + i
			if idx < 0 or idx >= d.size():
				continue
			var t := float(i) / float(n)
			var raw := rs.randf() * 2.0 - 1.0
			last = last + a * (raw - last)
			d[idx] += last * pow(1.0 - t, 2.6) * vol

	func to_stream() -> AudioStreamWAV:
		var bytes := PackedByteArray()
		bytes.resize(d.size() * 2)
		for i in d.size():
			var v := int(clampf(d[i], -1.0, 1.0) * 32000.0)
			bytes.encode_s16(i * 2, v)
		var w := AudioStreamWAV.new()
		w.format = AudioStreamWAV.FORMAT_16_BITS
		w.mix_rate = Snd.RATE
		w.stereo = false
		w.data = bytes
		return w


func _build_bank() -> void:
	var b: Buf

	b = Buf.new(0.10); b.tone(660, 0.0, 0.07, 0.22, "tri")
	_bank["select"] = b.to_stream()

	b = Buf.new(0.16); b.noise(0.0, 0.10, 0.20, 900); b.tone(320, 0.0, 0.08, 0.10, "sine", 240)
	_bank["move"] = b.to_stream()

	b = Buf.new(0.30); b.noise(0.0, 0.22, 0.55, 2200); b.tone(150, 0.0, 0.18, 0.42, "square", 60)
	_bank["hit"] = b.to_stream()

	b = Buf.new(0.45); b.noise(0.0, 0.36, 0.55, 1100); b.tone(110, 0.0, 0.36, 0.45, "saw", 42)
	_bank["kill"] = b.to_stream()

	b = Buf.new(0.60)
	for i in 3:
		b.tone([523.0, 659.0, 784.0][i], i * 0.075, 0.38, 0.30, "tri")
	_bank["found"] = b.to_stream()

	b = Buf.new(0.70)
	for i in 4:
		b.tone([392.0, 523.0, 659.0, 784.0][i], i * 0.06, 0.44, 0.28, "square")
	_bank["capture"] = b.to_stream()

	b = Buf.new(0.95)
	for i in 4:
		b.tone([392.0, 330.0, 262.0, 196.0][i], i * 0.11, 0.52, 0.32, "saw")
	_bank["lost"] = b.to_stream()

	b = Buf.new(1.40)
	for i in 5:
		b.tone([392.0, 523.0, 659.0, 784.0, 1047.0][i], i * 0.10, 0.80, 0.32, "tri")
	b.noise(0.0, 0.6, 0.22, 500)
	_bank["age"] = b.to_stream()

	b = Buf.new(0.60); b.tone(880, 0.0, 0.50, 0.24, "sine"); b.tone(1320, 0.05, 0.45, 0.14, "sine")
	_bank["draft"] = b.to_stream()

	b = Buf.new(0.65); b.tone(659, 0.0, 0.50, 0.28, "tri"); b.tone(988, 0.08, 0.50, 0.24, "tri")
	_bank["edict"] = b.to_stream()

	b = Buf.new(0.70)
	for i in 3:
		b.tone([523.0, 784.0, 1047.0][i], i * 0.07, 0.46, 0.26, "tri")
	_bank["promote"] = b.to_stream()

	b = Buf.new(0.14); b.tone(240, 0.0, 0.10, 0.24, "square", 200)
	_bank["turn"] = b.to_stream()

	b = Buf.new(0.35); b.tone(523, 0.0, 0.20, 0.22, "tri"); b.tone(784, 0.07, 0.24, 0.18, "tri")
	_bank["build"] = b.to_stream()

	b = Buf.new(1.20)
	for i in 4:
		b.tone([523.0, 659.0, 784.0, 1175.0][i], i * 0.11, 0.70, 0.30, "tri")
	_bank["wonder"] = b.to_stream()

	b = Buf.new(0.90); b.tone(196, 0.0, 0.72, 0.42, "saw", 92); b.noise(0.0, 0.7, 0.30, 600)
	_bank["war"] = b.to_stream()

	b = Buf.new(1.80)
	for i in 5:
		b.tone([523.0, 659.0, 784.0, 1047.0, 1319.0][i], i * 0.13, 1.15, 0.34, "tri")
	_bank["win"] = b.to_stream()

	b = Buf.new(0.22); b.tone(160, 0.0, 0.17, 0.28, "square", 120)
	_bank["deny"] = b.to_stream()
