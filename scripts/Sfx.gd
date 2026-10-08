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
		"step1":
			# Footstep (v0.22.0): soft low thud + scuffed noise, alternating
			# with step2 so a walk doesn't sound like a metronome. Scaled
			# down — footsteps are texture, not percussion.
			var step := _mix(_tone(72.0, 0.09, 0.004, 3.0), _noise_burst(0.045, 6.0, 1.2))
			for i in step.size():
				step[i] *= 0.7
			s = _wav(step)
		"step2":
			var step2 := _mix(_tone(64.0, 0.1, 0.004, 3.0), _noise_burst(0.05, 5.0, 1.2))
			for i in step2.size():
				step2[i] *= 0.7
			s = _wav(step2)
		"bell":
			# Morning bell (v0.22.0): two soft partials, long release.
			var ring := _mix(_tone(880.0, 0.9, 0.01, 1.6), _tone(1318.5, 0.7, 0.01, 1.4), 0.35)
			for i in ring.size():
				ring[i] *= 0.7
			s = _wav(ring)
		"music":
			s = music_station_stream(0)
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
	for key in ["grab", "place", "beep", "chime", "buzz", "cash", "click", "upgrade", "hum", "servo", "music", "step1", "step2", "bell"]:
		var s := stream(key)
		if s != null:
			out[key] = s.data.size() / 2.0 / RATE
	return out


## --- music (v0.16.0, stations v0.21.0) ------------------------------------------
##
## Runtime-synthesized music: one soft chord per bar over a hiss floor, 4
## bars, seamless loop. Deliberately simple and QUIET — background texture,
## not a production. v0.21.0 added stations; v0.55.0 a fourth (Jazz).

const MUSIC_BARS := 4

## Per-station synth specs: name, tempo, hiss floor, per-bar swell shape
## (exponent + level), partials as [frequency-multiplier, amplitude] pairs
## layered on every chord voice, per-voice amps (bass first), and the chord
## chart ([bass root + chord tones] in Hz).
const STATIONS: Array[Dictionary] = [
	{
		"name": "Lo-fi", "bpm": 72.0, "hiss": 0.012, "env_pow": 1.5, "level": 0.05,
		"partials": [[1.0, 1.0]],
		"voices": [1.0, 0.8, 0.8, 0.8],
		"chords": [
			[146.83, 220.0, 261.63, 329.63],
			[98.0, 196.0, 246.94, 293.66],
			[130.81, 196.0, 261.63, 329.63],
			[110.0, 220.0, 261.63, 329.63],
		],
	},
	{
		"name": "Synthwave", "bpm": 100.0, "hiss": 0.006, "env_pow": 1.2, "level": 0.045,
		"partials": [[1.0, 1.0], [2.0, 0.4], [3.0, 0.22]],
		"voices": [0.75, 0.75, 0.75, 0.75],
		"chords": [
			[110.0, 220.0, 261.63, 329.63],
			[87.31, 174.61, 220.0, 261.63],
			[130.81, 196.0, 261.63, 329.63],
			[98.0, 196.0, 246.94, 293.66],
		],
	},
	{
		"name": "Ambient", "bpm": 56.0, "hiss": 0.008, "env_pow": 0.8, "level": 0.055,
		"partials": [[1.0, 1.0], [2.0, 0.18]],
		"voices": [1.0, 0.7, 0.7, 0.9],
		"chords": [
			[65.41, 130.81, 196.0, 246.94],
			[87.31, 174.61, 220.0, 261.63],
			[65.41, 130.81, 196.0, 246.94],
			[87.31, 174.61, 220.0, 261.63],
		],
	},
	{
		"name": "Jazz", "bpm": 96.0, "hiss": 0.014, "env_pow": 1.25, "level": 0.05,
		"partials": [[1.0, 1.0], [2.0, 0.28]],
		"voices": [1.0, 0.8, 0.7, 0.6],
		"chords": [
			[146.83, 174.61, 220.0, 261.63],
			[98.0, 123.47, 146.83, 174.61],
			[130.81, 164.81, 196.0, 246.94],
			[110.0, 138.59, 164.81, 196.0],
		],
	},
]

static func station_names() -> Array[String]:
	var out: Array[String] = []
	for s in STATIONS:
		out.append(str(s.name))
	return out


## The synthesized loop for radio `station` (clamped). One shared renderer;
## station 0 reproduces the v0.16 lo-fi loop exactly (same bpm/chords and a
## single 1.0 partial). Cached per station — Main compares streams by
## reference to decide whether to swap.
static var _station_cache: Dictionary = {}

static func music_station_stream(station: int) -> AudioStreamWAV:
	var idx := clampi(station, 0, STATIONS.size() - 1)
	if _station_cache.has(idx):
		return _station_cache[idx]
	var spec: Dictionary = STATIONS[idx]
	var bpm := float(spec.bpm)
	var chords: Array = spec.chords
	var partials: Array = spec.partials
	var voices: Array = spec.voices
	var env_pow := float(spec.env_pow)
	var level := float(spec.level)
	var bar := 4.0 * 60.0 / bpm
	var total := int(bar * MUSIC_BARS * RATE)
	var out := PackedFloat32Array()
	out.resize(total)
	var prev := 0.0
	for i in total:
		prev += 0.02 * ((randf() * 2.0 - 1.0) - prev)
		out[i] = float(spec.hiss) * prev  # hiss floor
	for b in MUSIC_BARS:
		var chord: Array = chords[b]
		var start := int(b * bar * RATE)
		var n := int(bar * RATE)
		for i in n:
			var t := float(i) / RATE
			# Swell per bar: silent seams, no clicks between chords.
			var env := pow(sin(PI * float(i) / float(n)), env_pow) * level
			var sample := 0.0
			for f in chord.size():
				var va := float(voices[f]) if f < voices.size() else 0.8
				for p in partials:
					sample += sin(TAU * float(chord[f]) * float(p[0]) * t) \
						* float(p[1]) * va
			out[start + i] += env * sample / float(chord.size())
	# Crossfade the tail into the head so the loop seam is inaudible.
	var fade := int(0.05 * RATE)
	for i in fade:
		var k := float(i) / float(fade)
		out[total - fade + i] = lerpf(out[total - fade + i], out[i], k)
	var wav := _wav(out, true)
	_station_cache[idx] = wav
	return wav

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
