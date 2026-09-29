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
		"servo":
			# Printer stepper blip (v0.16.0): tiny high tick, played quietly
			# and rate-limited by Main while a print runs.
			s = _wav(_tone(2350.0, 0.035, 0.001, 7.0))
		"music":
			s = _music_loop()
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
	for key in ["grab", "place", "beep", "chime", "buzz", "cash", "click", "upgrade", "hum", "servo", "music"]:
		var s := stream(key)
		if s != null:
			out[key] = s.data.size() / 2.0 / RATE
	return out


## --- music (v0.16.0) ------------------------------------------------------------
##
## Runtime-synthesized lo-fi loop: one soft chord per bar over a vinyl hiss
## floor, ~72 BPM, 4 bars, seamless loop. Deliberately simple and QUIET —
## background texture, not a production.

const MUSIC_BPM := 72.0
const MUSIC_BARS := 4
## Dm7 -> G7 -> Cmaj7 -> Am7 (ii-V-I-vi): each bar's [bass root + chord tones]
## in Hz. Register kept low for warmth.
const MUSIC_CHORDS: Array[Array] = [
	[146.83, 220.0, 261.63, 329.63],
	[98.0, 196.0, 246.94, 293.66],
	[130.81, 196.0, 261.63, 329.63],
	[110.0, 220.0, 261.63, 329.63],
]

static func _music_loop() -> AudioStreamWAV:
	var bar := 4.0 * 60.0 / MUSIC_BPM
	var total := int(bar * MUSIC_BARS * RATE)
	var out := PackedFloat32Array()
	out.resize(total)
	var prev := 0.0
	for i in total:
		prev += 0.02 * ((randf() * 2.0 - 1.0) - prev)
		out[i] = 0.012 * prev  # vinyl hiss floor
	for b in MUSIC_BARS:
		var chord: Array = MUSIC_CHORDS[b]
		var start := int(b * bar * RATE)
		var n := int(bar * RATE)
		for i in n:
			var t := float(i) / RATE
			# Half-sine swell per bar: silent seams, no clicks between chords.
			var env := pow(sin(PI * float(i) / float(n)), 1.5) * 0.05
			var sample := 0.0
			for f in chord.size():
				sample += sin(TAU * float(chord[f]) * t) * (1.0 if f == 0 else 0.8)
			out[start + i] += env * sample / float(chord.size())
	# Crossfade the tail into the head so the loop seam is inaudible.
	var fade := int(0.05 * RATE)
	for i in fade:
		var k := float(i) / float(fade)
		out[total - fade + i] = lerpf(out[total - fade + i], out[i], k)
	return _wav(out, true)

## Create (once) and return the name of the shared Music bus.
static func music_bus_name() -> String:
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Music")
		AudioServer.set_bus_send(idx, "Master")
	return "Music"

static func set_music_volume(linear: float) -> void:
	var idx := AudioServer.get_bus_index(music_bus_name())
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0001, 1.0)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


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
