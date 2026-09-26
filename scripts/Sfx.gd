class_name Sfx
extends Node

## Task 12 polish — runtime-synthesized sound effects. All samples are small
## DSP loops written in GDScript at load time (16-bit mono PCM, 22050 Hz):
## no audio assets to import, web-export safe. Playback goes through an
## "SFX" audio bus so the settings slider controls everything at once.
## Headless runs use Godot's dummy audio driver; building these streams is
## plain data math and safe there.

const RATE := 22050

const COLOR_PAPER := Color("#EEE5D3")

static var _streams: Dictionary = {}


static func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = samples.size()
	return s


static func _tone(freq: float, seconds: float, attack := 0.005, decay_pow := 3.0) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := minf(t / attack, 1.0) * pow(1.0 - float(i) / float(n), decay_pow)
		out[i] = 0.6 * sin(TAU * freq * t) * env
	return out


static func _mix(a: PackedFloat32Array, b: PackedFloat32Array, offset_seconds := 0.0) -> PackedFloat32Array:
	var off := int(offset_seconds * RATE)
	var total := maxi(a.size(), off + b.size())
	var out := PackedFloat32Array()
	out.resize(total)
	for i in a.size():
		out[i] += a[i]
	for i in b.size():
		out[off + i] += b[i]
	return out


static func _noise_burst(seconds: float, decay_pow := 6.0, lp := 0.25) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	for i in n:
		var white := randf() * 2.0 - 1.0
		prev = prev + lp * (white - prev)  # cheap one-pole low-pass
		out[i] = prev * pow(1.0 - float(i) / float(n), decay_pow)
	return out


## Build (and cache) one stream per name. Unknown names return null.
static func stream(sound: String) -> AudioStreamWAV:
	if _streams.has(sound):
		return _streams[sound]
	var s: AudioStreamWAV = null
	match sound:
		"grab":
			s = _wav(_noise_burst(0.05, 8.0, 0.6))
		"place":
			s = _wav(_mix(_tone(85.0, 0.12, 0.002, 5.0), _noise_burst(0.02, 9.0, 0.7)))
		"beep":
			s = _wav(_mix(_tone(660.0, 0.07), _tone(990.0, 0.09, 0.005, 3.0), 0.08))
		"chime":
			s = _wav(_mix(_mix(_tone(523.25, 0.16), _tone(659.25, 0.16), 0.09),
				_tone(783.99, 0.24), 0.18))
		"buzz":
			var n := int(0.3 * RATE)
			var out := PackedFloat32Array()
			out.resize(n)
			for i in n:
				var t := float(i) / RATE
				var sq := 1.0 if fmod(t * 110.0, 1.0) < 0.5 else -1.0
				out[i] = 0.28 * sq * pow(1.0 - float(i) / float(n), 1.5)
			s = _wav(out)
		"cash":
			s = _wav(_mix(_tone(1318.5, 0.08, 0.002, 4.0), _tone(1760.0, 0.14, 0.002, 4.0), 0.07))
		"click":
			s = _wav(_tone(1900.0, 0.03, 0.001, 6.0))
		"upgrade":
			s = _wav(_mix(_tone(440.0, 0.08), _tone(880.0, 0.14, 0.005, 3.0), 0.07))
		"hum":
			# Looping printer ambience: mains-frequency drone + soft hiss.
			var n := int(0.5 * RATE)
			var out := PackedFloat32Array()
			out.resize(n)
			var prev := 0.0
			for i in n:
				var t := float(i) / RATE
				prev += 0.05 * ((randf() * 2.0 - 1.0) - prev)
				out[i] = 0.16 * sin(TAU * 120.0 * t) + 0.5 * prev
			# Crossfade the tail into the head so the loop seam is inaudible.
			var fade := int(0.02 * RATE)
			for i in fade:
				var k := float(i) / float(fade)
				out[n - fade + i] = lerpf(out[n - fade + i], out[i], k)
			s = _wav(out, true)
		_:
			pass
	_streams[sound] = s
	return s


static func stream_lengths() -> Dictionary:
	var out: Dictionary = {}
	for key in ["grab", "place", "beep", "chime", "buzz", "cash", "click", "upgrade", "hum"]:
		var s := stream(key)
		if s != null:
			out[key] = s.data.size() / 2.0 / RATE
	return out


## --- playback node ----------------------------------------------------------

var _bus := ""
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	_bus = bus_name()
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = _bus
		add_child(p)
		_players.append(p)


## Create (once) and return the name of the shared SFX bus.
static func bus_name() -> String:
	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "SFX")
		AudioServer.set_bus_send(idx, "Master")
	return "SFX"


static func set_volume(linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name())
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0001, 1.0)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


## Fire-and-forget one-shot; round-robins a small player pool so overlapping
## sounds (grab + beep) never cut each other off.
func play(sound: String, volume_linear := 1.0, pitch := 1.0) -> void:
	var s := stream(sound)
	if s == null or _players.is_empty():
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = s
	p.volume_db = linear_to_db(maxf(volume_linear, 0.0001))
	p.pitch_scale = pitch
	p.play()


func click() -> void:
	play("click", 0.5)
