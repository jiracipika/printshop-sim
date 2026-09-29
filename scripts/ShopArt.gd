class_name ShopArt
extends RefCounted

## Task 12 art pass — procedural texture factory.
## Every texture is generated at runtime from FastNoiseLite + per-pixel Image
## writes: no external assets, nothing to import, web-export safe. Sizes stay
## <= 256 px and each texture is generated once (callers should cache via
## ShopArt.tex()). Mipmaps are generated so 3D surfaces minify cleanly.

const SIZE := 256

static var _cache: Dictionary = {}


## Cached entry point: key must encode every parameter (e.g. "wood:#C3A076:5").
static func tex(key: String, builder: Callable) -> ImageTexture:
	if _cache.has(key):
		return _cache[key]
	var t: ImageTexture = builder.call()
	_cache[key] = t
	return t


static func _noise(seed_value: int, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = freq
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.fractal_octaves = 3
	return n


static func _finish(img: Image) -> ImageTexture:
	# RGBA8 uncompressed always supports mipmaps; compress if possible.
	if img.is_compressed():
		img.decompress()
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Painted plaster wall: low-contrast value noise over the base color.
## size=512 adds faint stains near the bottom for rooms-scale realism.
static func plaster(base: Color, size := SIZE) -> ImageTexture:
	return tex("plaster:%s:%d" % [base.to_html(), size], func() -> ImageTexture:
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var n := _noise(21, 0.06)
		var fine := _noise(22, 0.5)
		var stain := _noise(23, 0.03)
		for y in size:
			for x in size:
				var v := 0.94 + 0.05 * n.get_noise_2d(x, y) + 0.02 * fine.get_noise_2d(x, y)
				var bottom := float(y) / float(size)
				v -= 0.05 * bottom * clampf(0.6 + stain.get_noise_2d(x, y), 0.0, 1.6)
				var c := base.darkened(1.0 - clampf(v, 0.0, 1.0))
				img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
		return _finish(img))


## Plywood / workbench top: sinusoidal ring bands warped by stretched noise.
## size=512 adds plank gaps and a couple of darker knots.
static func wood(base: Color, planks := 5, size := SIZE) -> ImageTexture:
	return tex("wood:%s:%d:%d" % [base.to_html(), planks, size], func() -> ImageTexture:
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var warp := _noise(11, 0.02)
		var fine := _noise(12, 0.4)
		var knot := _noise(13, 0.08)
		var band := float(size) / float(planks)
		for y in size:
			for x in size:
				var wx := warp.get_noise_2d(x, y) * band * 0.35
				var ring := 0.5 + 0.5 * sin((float(x) + wx) / band * TAU)
				var streak := fine.get_noise_2d(x * 6.0, float(y) * 0.8)
				var v := clampf(0.78 + 0.16 * ring + 0.09 * streak, 0.0, 1.0)
				# Plank gaps: dark seam every `band` px on X.
				var seam := absf(fmod(float(x), band))
				if seam < 2.0:
					v *= 0.55
				# Occasional knots where the knot noise peaks.
				if knot.get_noise_2d(x, y) > 0.72:
					v *= 0.72
				var c := base.darkened(1.0 - v)
				img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
		return _finish(img))


## Workshop floor: tile grid with grout lines, grime and scuffs.
## size=512 doubles the resolution and adds dark scuff streaks along X.
static func floor_tiles(base: Color, tiles := 4, size := SIZE) -> ImageTexture:
	return tex("floor:%s:%d:%d" % [base.to_html(), tiles, size], func() -> ImageTexture:
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var grime := _noise(31, 0.09)
		var fine := _noise(32, 0.7)
		var scuff := _noise(33, 0.25)
		var step := float(size) / float(tiles)
		for y in size:
			for x in size:
				var gx := absf(fmod(float(x), step) - step * 0.5)
				var gy := absf(fmod(float(y), step) - step * 0.5)
				var edge := minf(gx, gy)  # 0 at grout lines, ~step/2 at centers
				var grout := clampf(edge / 5.0, 0.0, 1.0)
				var v := clampf(0.86 + 0.10 * grime.get_noise_2d(x, y) + 0.05 * fine.get_noise_2d(x, y), 0.0, 1.0)
				v *= lerpf(0.55, 1.0, grout)
				# Scuffs: soft dark streaks where the scuff noise peaks.
				if scuff.get_noise_2d(x * 0.5, y * 2.0) > 0.62:
					v *= 0.85
				var c := base.darkened(1.0 - v)
				img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
		return _finish(img))


## Brushed metal: vertical streaks (X-frequency high, Y low).
static func metal(base: Color) -> ImageTexture:
	return tex("metal:%s" % base.to_html(), func() -> ImageTexture:
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		var streak := _noise(41, 0.5)
		var blotch := _noise(42, 0.05)
		for y in SIZE:
			for x in SIZE:
				var v := clampf(0.92 + 0.10 * streak.get_noise_2d(x * 3.0, float(y) * 0.2) \
					+ 0.06 * blotch.get_noise_2d(x, y), 0.0, 1.0)
				var c := base.darkened(1.0 - v)
				img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
		return _finish(img))


## Cardboard: fibrous noise stretched along X with lighter flecks.
static func cardboard(base: Color) -> ImageTexture:
	return tex("cardboard:%s" % base.to_html(), func() -> ImageTexture:
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		var fiber := _noise(51, 0.25)
		var fleck := _noise(52, 0.9)
		for y in SIZE:
			for x in SIZE:
				var v := clampf(0.88 + 0.12 * fiber.get_noise_2d(x * 0.5, float(y) * 2.0) \
					+ (0.08 if fleck.get_noise_2d(x, y) > 0.55 else 0.0), 0.0, 1.0)
				var c := base.darkened(1.0 - v)
				img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
		return _finish(img))


## Poster art: flat background, big accent shapes, paper-grain noise.
## Bars describe extra rectangles: [x0, y0, x1, y1] in 0..1 UV space.
static func poster(bg: Color, accent: Color, bars: Array) -> ImageTexture:
	return tex("poster:%s:%s:%s" % [bg.to_html(), accent.to_html(), str(bars.hash())],
		func() -> ImageTexture:
			var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
			var grain := _noise(61, 0.8)
			for y in SIZE:
				for x in SIZE:
					var u := float(x) / float(SIZE)
					var v := float(y) / float(SIZE)
					var c := bg
					if u > 0.12 and u < 0.88 and v > 0.30 and v < 0.62:
						c = accent
					for b in bars:
						if u > float(b[0]) and u < float(b[2]) and v > float(b[1]) and v < float(b[3]):
							c = bg.lerp(accent, 0.35)
					var g := 0.94 + 0.06 * grain.get_noise_2d(x, y)
					c = c.darkened(1.0 - clampf(g, 0.0, 1.0))
					img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
			return _finish(img))


## Woven rug: two-direction fine noise reads as fabric at room scale.
static func weave(base: Color) -> ImageTexture:
	return tex("weave:%s" % base.to_html(), func() -> ImageTexture:
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		var n := _noise(71, 0.9)
		for y in SIZE:
			for x in SIZE:
				var thread := 0.5 + 0.5 * sin(float(x) * 1.8) * sin(float(y) * 1.8)
				var v := clampf(0.82 + 0.10 * thread + 0.10 * n.get_noise_2d(x, y), 0.0, 1.0)
				var c := base.darkened(1.0 - v)
				img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
		return _finish(img))


## Soft radial vignette overlay (black at edges, transparent center).
static func vignette() -> ImageTexture:
	return tex("vignette", func() -> ImageTexture:
		var size := 256
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var half := float(size) * 0.5
		for y in size:
			for x in size:
				var d := Vector2(float(x) - half, float(y) - half).length() / half
				var a := clampf((d - 0.55) / 0.45, 0.0, 1.0)
				a = a * a  # ease-in so the center stays clean
				img.set_pixel(x, y, Color(0.02, 0.03, 0.03, 0.55 * a))
		return _finish(img))


## Pegboard: perforated tool wall — grid of dark holes on a panel base.
static func pegboard(base: Color) -> ImageTexture:
	return tex("pegboard:%s" % base.to_html(), func() -> ImageTexture:
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		var n := _noise(81, 0.3)
		var step := 32
		for y in SIZE:
			for x in SIZE:
				var v := 0.9 + 0.08 * n.get_noise_2d(x, y)
				var hx := absi(x % step - step / 2)
				var hy := absi(y % step - step / 2)
				if hx < 4 and hy < 4:
					v *= 0.35  # hole
				elif hx < 7 and hy < 7:
					v *= 0.75  # hole rim
				var c := base.darkened(1.0 - clampf(v, 0.0, 1.0))
				img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
		return _finish(img))


## Printer build plate: dark honey plate with alignment grid and worn edges.
static func bed_grid(base: Color) -> ImageTexture:
	return tex("bedgrid:%s" % base.to_html(), func() -> ImageTexture:
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		var wear := _noise(91, 0.2)
		for y in SIZE:
			for x in SIZE:
				var v := 0.95 + 0.06 * wear.get_noise_2d(x, y)
				var on_grid := (x % 32) < 2 or (y % 32) < 2
				if on_grid:
					v *= 0.6
				var edge := minf(minf(x, SIZE - 1 - x), minf(y, SIZE - 1 - y))
				if edge < 8:
					v *= 0.8  # worn border
				var c := base.darkened(1.0 - clampf(v, 0.0, 1.0))
				img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
		return _finish(img))


## Wall calendar: paper sheet with a red header band and a date grid.
static func calendar() -> ImageTexture:
	return tex("calendar", func() -> ImageTexture:
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		var paper := Color("#EFE8D8")
		var red := Color("#DA623A")
		var line := Color("#B9B2A0")
		var header := int(SIZE / 6.0)
		var col_w := int(SIZE / 7.0)
		var row_h := int((SIZE - header) / 8.0)
		for y in range(SIZE):
			for x in range(SIZE):
				var c := paper
				if y < header:
					c = red
				elif y > header + 4 and y < SIZE - 12:
					var gx := x % maxi(col_w, 1)
					var gy := (y - header) % maxi(row_h, 1)
					if gx < 2 or gy < 2:
						c = line
				img.set_pixel(x, y, c)
		return _finish(img))


## --- outside view (v0.25.0) ---------------------------------------------------
##
## The shop window is a light box: a procedural day view by day and a night
## sky by night, both drawn as textures so the whole "outside" costs two
## quads. The night sky features one REAL constellation per month (Orion in
## January, Leo in March, Scorpius in July...) over a city skyline, plus a
## moon whose phase follows the real date.

const SKY_W := 512
const SKY_H := 320

## One featured constellation per real-world month (evening sky, northern
## hemisphere, approximate). Patterns follow the real asterisms.
const MONTH_SKY: Array[String] = [
	"orion", "gemini", "leo", "ursa_major", "bootes", "scorpius",
	"lyra", "cygnus", "pegasus", "andromeda", "perseus", "taurus",
]

## Simplified real constellations: normalized star positions in their sky
## box plus connecting segments (star index pairs).
const CONSTELLATIONS := {
	"orion": {"stars": [[0.62, 0.18], [0.38, 0.22], [0.52, 0.48], [0.47, 0.52],
		[0.42, 0.56], [0.55, 0.82], [0.28, 0.85]],
		"lines": [[0, 2], [1, 4], [2, 3], [3, 4], [2, 5], [4, 6]]},
	"gemini": {"stars": [[0.30, 0.12], [0.55, 0.16], [0.28, 0.38], [0.52, 0.42],
		[0.30, 0.62], [0.55, 0.66], [0.26, 0.85], [0.58, 0.88]],
		"lines": [[0, 2], [2, 4], [4, 6], [1, 3], [3, 5], [5, 7], [2, 3]]},
	"leo": {"stars": [[0.30, 0.58], [0.36, 0.44], [0.44, 0.38], [0.50, 0.26],
		[0.40, 0.22], [0.70, 0.50], [0.58, 0.44]],
		"lines": [[0, 1], [1, 5], [5, 6], [6, 2], [2, 3], [3, 4], [4, 1]]},
	"ursa_major": {"stars": [[0.15, 0.55], [0.25, 0.50], [0.35, 0.52], [0.44, 0.57],
		[0.52, 0.66], [0.68, 0.70], [0.80, 0.62]],
		"lines": [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 6]]},
	"bootes": {"stars": [[0.50, 0.75], [0.38, 0.58], [0.50, 0.42], [0.64, 0.48],
		[0.60, 0.66], [0.48, 0.28]],
		"lines": [[0, 1], [1, 2], [2, 3], [3, 4], [4, 0], [2, 5]]},
	"scorpius": {"stars": [[0.45, 0.30], [0.25, 0.22], [0.22, 0.34], [0.50, 0.38],
		[0.56, 0.52], [0.52, 0.66], [0.44, 0.78], [0.32, 0.86], [0.20, 0.88]],
		"lines": [[0, 3], [3, 4], [4, 5], [5, 6], [6, 7], [7, 8], [1, 0], [2, 0]]},
	"lyra": {"stars": [[0.40, 0.20], [0.46, 0.34], [0.58, 0.40], [0.52, 0.56],
		[0.40, 0.50]],
		"lines": [[0, 1], [1, 2], [2, 3], [3, 4], [4, 1]]},
	"cygnus": {"stars": [[0.50, 0.18], [0.50, 0.40], [0.50, 0.78], [0.28, 0.52],
		[0.72, 0.44]],
		"lines": [[0, 1], [1, 2], [3, 1], [1, 4]]},
	"pegasus": {"stars": [[0.35, 0.35], [0.62, 0.32], [0.66, 0.58], [0.38, 0.60],
		[0.18, 0.75], [0.80, 0.80]],
		"lines": [[0, 1], [1, 2], [2, 3], [3, 0], [0, 4], [2, 5]]},
	"andromeda": {"stars": [[0.55, 0.25], [0.45, 0.42], [0.35, 0.58], [0.25, 0.75],
		[0.52, 0.36]],
		"lines": [[0, 1], [1, 2], [2, 3], [1, 4]]},
	"perseus": {"stars": [[0.30, 0.30], [0.42, 0.38], [0.52, 0.52], [0.60, 0.66],
		[0.55, 0.82]],
		"lines": [[0, 1], [1, 2], [2, 3], [3, 4]]},
	"taurus": {"stars": [[0.55, 0.40], [0.48, 0.46], [0.40, 0.52], [0.32, 0.46],
		[0.36, 0.38], [0.68, 0.30], [0.15, 0.62]],
		"lines": [[0, 1], [1, 2], [2, 3], [3, 4], [1, 5]]},
}


static func featured_constellation(month: int) -> String:
	return MONTH_SKY[clampi(month, 1, 12) - 1]


## Approximate moon phase 0..1 (0 = new, 0.5 = full) from the real date,
## anchored to the known new moon of 2000-01-06 18:14 UTC.
static func moon_phase(now_unix: int = -1) -> float:
	if now_unix < 0:
		now_unix = int(Time.get_unix_time_from_system())
	var days := float(now_unix - 947182440) / 86400.0
	return fposmod(days / 29.530588, 1.0)


static func _sky_dot(img: Image, cx: float, cy: float, r: float, c: Color) -> void:
	for y in range(int(cy - r), int(cy + r) + 1):
		for x in range(int(cx - r), int(cx + r) + 1):
			if x < 0 or y < 0 or x >= SKY_W or y >= SKY_H:
				continue
			var d := Vector2(float(x) - cx, float(y) - cy).length()
			if d <= r:
				img.set_pixel(x, y, c)


static func _sky_line(img: Image, a: Vector2, b: Vector2, c: Color) -> void:
	var steps := int(a.distance_to(b)) + 1
	for i in steps + 1:
		var p := a.lerp(b, float(i) / float(maxi(steps, 1)))
		var x := int(p.x)
		var y := int(p.y)
		if x >= 0 and y >= 0 and x < SKY_W and y < SKY_H:
			img.set_pixel(x, y, c)


static func _draw_constellation(img: Image, id: String, box: Rect2, star_r: float,
		star_c: Color, line_c: Color) -> void:
	var data: Dictionary = CONSTELLATIONS[id]
	var pts: Array[Vector2] = []
	for st in data.stars:
		pts.append(Vector2(
			box.position.x + float(st[0]) * box.size.x,
			box.position.y + float(st[1]) * box.size.y))
	for ln in data.lines:
		_sky_line(img, pts[int(ln[0])], pts[int(ln[1])], line_c)
	for pt in pts:
		_sky_dot(img, pt.x, pt.y, star_r, star_c)


static func window_night(month: int) -> ImageTexture:
	return tex("window_night:%d" % clampi(month, 1, 12), func() -> ImageTexture:
		var img := Image.create(SKY_W, SKY_H, false, Image.FORMAT_RGBA8)
		var top := Color("#0B1626")
		var bottom := Color("#24354F")
		for y in SKY_H:
			var row := top.lerp(bottom, pow(float(y) / float(SKY_H), 1.4))
			for x in SKY_W:
				img.set_pixel(x, y, Color(row.r, row.g, row.b, 1.0))
		# Field stars, deterministic per month.
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("printshop-sky-%d" % clampi(month, 1, 12))
		for i in range(170):
			var sx := rng.randf_range(2.0, SKY_W - 2.0)
			var sy := rng.randf_range(2.0, SKY_H * 0.72)
			var b := rng.randf_range(0.25, 0.95)
			_sky_dot(img, sx, sy, 1.0 if b < 0.8 else 1.6,
				Color(0.92, 0.95, 1.0, b))
		# Featured constellation front and center; regulars faint in the
		# corners so the sky reads as real wherever you look.
		var featured := featured_constellation(month)
		_draw_constellation(img, featured,
			Rect2(0.30 * SKY_W, 0.10 * SKY_H, 0.46 * SKY_W, 0.62 * SKY_H),
			2.4, Color(0.98, 0.97, 0.88), Color(0.55, 0.68, 0.85, 0.85))
		if featured != "ursa_major":
			_draw_constellation(img, "ursa_major",
				Rect2(0.02 * SKY_W, 0.30 * SKY_H, 0.22 * SKY_W, 0.28 * SKY_H),
				1.4, Color(0.85, 0.90, 1.0, 0.8), Color(0.45, 0.55, 0.72, 0.5))
		if featured != "ursa_major" and featured != "pegasus":
			_draw_constellation(img, "cygnus" if featured == "pegasus" else "pegasus",
				Rect2(0.66 * SKY_W, 0.06 * SKY_H, 0.30 * SKY_W, 0.30 * SKY_H),
				1.3, Color(0.85, 0.90, 1.0, 0.75), Color(0.45, 0.55, 0.72, 0.45))
		# Moon with its real phase: per-pixel terminator — the shadow circle
		# slides across the disc (left while waxing, right while waning) and
		# the lit fraction lands on the real phase at every step.
		var phase := moon_phase()
		var mx := 0.12 * SKY_W
		var my := 0.16 * SKY_H
		var mr := 13.0
		_sky_dot(img, mx, my, mr + 1.5, Color(0.9, 0.93, 1.0, 0.35))
		var side := -1.0 if phase < 0.5 else 1.0
		var shift := side * mr * (1.0 - cos(TAU * phase))
		for y in range(int(my - mr - 1), int(my + mr + 2)):
			for x in range(int(mx - mr - 1), int(mx + mr + 2)):
				if x < 0 or y < 0 or x >= SKY_W or y >= SKY_H:
					continue
				var dm := Vector2(float(x) - mx, float(y) - my).length()
				if dm > mr:
					continue
				var ds := Vector2(float(x) - mx - shift, float(y) - my).length()
				var lit := clampf((ds - mr * 0.92) / (mr * 0.16), 0.0, 1.0)
				var c := Color(0.93, 0.94, 0.90).lerp(
					Color(top.r, top.g, top.b), lit)
				img.set_pixel(x, y, c)
		# City skyline with a few lit windows, haze band above it.
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = hash("printshop-skyline")
		var hx := 0
		while hx < SKY_W:
			var bw := int(rng2.randf_range(24.0, 58.0))
			var bh := int(rng2.randf_range(18.0, 58.0))
			for y in range(SKY_H - bh, SKY_H):
				for x in range(hx, mini(hx + bw, SKY_W)):
					img.set_pixel(x, y, Color(0.05, 0.08, 0.12))
			for w in range(int(bw * bh / 260.0)):
				var wx := hx + 3 + int(rng2.randf_range(0.0, float(bw) - 6.0))
				var wy := SKY_H - bh + 3 + int(rng2.randf_range(0.0, float(bh) - 6.0))
				if wx < SKY_W and wy < SKY_H:
					img.set_pixel(wx, wy, Color(1.0, 0.85, 0.55, rng2.randf_range(0.5, 0.95)))
			hx += bw + int(rng2.randf_range(2.0, 10.0))
		return _finish(img))


static func window_day() -> ImageTexture:
	return tex("window_day", func() -> ImageTexture:
		var img := Image.create(SKY_W, SKY_H, false, Image.FORMAT_RGBA8)
		var top := Color("#AFCFC8")
		var bottom := Color("#DCEAE2")
		for y in SKY_H:
			var row := top.lerp(bottom, pow(float(y) / float(SKY_H), 1.2))
			for x in SKY_W:
				img.set_pixel(x, y, Color(row.r, row.g, row.b, 1.0))
		# Hazy sun glow.
		for y in range(int(SKY_H * 0.12), int(SKY_H * 0.42)):
			for x in range(int(SKY_W * 0.60), int(SKY_W * 0.92)):
				var d := Vector2(x - SKY_W * 0.76, y - SKY_H * 0.27).length()
				var glow := clampf(1.0 - d / (SKY_W * 0.2), 0.0, 1.0)
				if glow > 0.0:
					var c := img.get_pixel(x, y)
					img.set_pixel(x, y, c.lerp(Color(0.98, 0.99, 0.92), glow * 0.55))
		# Distant hill band, then rooftop silhouettes.
		for x in SKY_W:
			var hy := SKY_H * 0.72 + sin(float(x) * 0.012) * 6.0 + sin(float(x) * 0.05) * 3.0
			for y in range(int(hy), SKY_H):
				img.set_pixel(x, y, Color(0.52, 0.62, 0.56))
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("printshop-skyline-day")
		var hx := 0
		while hx < SKY_W:
			var bw := int(rng.randf_range(20.0, 50.0))
			var bh := int(rng.randf_range(12.0, 40.0))
			for y in range(SKY_H - bh - 8, SKY_H - 8):
				for x in range(hx, mini(hx + bw, SKY_W)):
					img.set_pixel(x, y, Color(0.42, 0.52, 0.47))
			hx += bw + int(rng.randf_range(2.0, 8.0))
		return _finish(img))


static func cloud() -> ImageTexture:
	return tex("cloud", func() -> ImageTexture:
		var size := 128
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var noise := _noise(77, 3.0)
		for y in size:
			for x in size:
				var d := Vector2(float(x) - 64.0, (float(y) - 64.0) * 1.6).length() / 52.0
				var n := 0.5 + 0.5 * noise.get_noise_2d(x, y)
				var a := clampf(1.0 - d, 0.0, 1.0) * n
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(a * 0.9, 0.0, 0.9)))
		return _finish(img))
