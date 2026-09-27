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
