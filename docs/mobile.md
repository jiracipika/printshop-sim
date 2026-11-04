# printshop-sim on Android

The `Android` export preset produces `builds/printshop-sim.apk`
(arm64-v8a + x86_64 — x86_64 is required for emulator images, see the
preset comment). Debug signing is wired INTO the preset since the
 signing rework: `keystore/debug = res://android/debug.keystore`,
`package/signed=true` — the repo-committed key is DEBUG-ONLY; never
ship it to a store (release builds need a separate, non-committed
release keystore). `version/name` tracks the game version.

## Linux box toolchain (verified 2026-10-30)

- Godot 4.7 binary: `~/tools/godot`; Android export templates at
  `~/.local/share/godot/export_templates/4.7.stable/`.
- SDK: `~/Android/Sdk` — platform-tools (`adb`), emulator,
  build-tools/36.0.0 (`zipalign`, `apksigner`). System Java 17 is fine
  for apksigner; no gradle build (prebuilt-template export).

## Build, sign, install

```bash
cd <repo>
mkdir -p builds
# Godot writes the complete APK and then exits non-zero (its post-export
# adb step cannot connect — no daemon running). The APK on disk is fine.
~/tools/godot --headless --path . --export-release "Android" || true
test -f builds/printshop-sim.apk

BT=~/Android/Sdk/build-tools/36.0.0
$BT/zipalign -f 4 builds/printshop-sim.apk /tmp/printshop-aligned.apk
$BT/apksigner sign --ks android/debug.keystore --ks-key-alias androiddebugkey \
  --ks-pass pass:android --key-pass pass:android \
  --out /tmp/printshop-signed.apk /tmp/printshop-aligned.apk
mv /tmp/printshop-signed.apk builds/printshop-sim.apk
$BT/apksigner verify builds/printshop-sim.apk

A=~/Android/Sdk/platform-tools/adb
$A devices                      # emulator-5554 once booted
$A install -r builds/printshop-sim.apk
$A shell monkey -p com.jiracipika.printshopsim 1
```

Emulator: `Pixel7_API36` exists (`~/Android/Sdk/emulator/emulator -avd
Pixel7_API36`); boot takes ~1 min, then `adb devices` shows
`emulator-5554 device`.

## RUNTIME VERDICT (2026-11-04): two independent engine-vs-emulator crashes

Probed live on both AVDs (`Pixel7_API36` Android 16, `Pixel7_API34`
Android 14, headless + SwiftShader) with the v0.61.0 APK. The PRE-3.0
baseline (bbc0648, v0.57.0) also crashes identically — none of this is
game-code scope, but the second crash is a real portability signal.

**Crash 1 — audio (OpenSL), both images.** SIGSEGV SEGV_ACCERR in the
`AudioTrack` thread ~30–90 s after launch: Android's
`AudioTrack::processAudioBuffer → onMoreData → wilhelm` calls INTO
`libgodot_android.so` (Godot's OpenSL data callback) and that faults.
This Godot 4.7 Android build compiles exactly two audio drivers —
`AudioDriverOpenSL` and `AudioDriverDummy` (no AAudio/Oboe; upstream
still has only a draft PR for it). Emulator-side mitigations are all
neutralized: `emulator -no-audio` doesn't help (verified earlier), and
engine args via the launch intent are impossible — GodotActivity.kt
`sanitizeLaunchIntent()` strips the `command_line_params` extra from
exported activities by design.

**Verified workaround for crash 1:** repack the APK appending
`--audio-driver Dummy` to `assets/_cl_` (the boot command-line asset:
`int32 LE argc`, then per-arg `int32 LE length + UTF-8`). Recipe:
`~/ps_harness/repack_dummy.py` (python zipfile, preserves compress_type)
→ `zipalign -f 4` → `apksigner sign` (repo debug keystore) → installs
as `builds/printshop-sim-dummy.apk` (the shipped APK is untouched).
Live result on BOTH images: GodotActivity logs the Dummy arg, zero
`libOpenSLES` lines, zero AudioTrack SIGSEGVs.

**Crash 2 — render (GLES3 uniform overflow), both images.** The scene
shaders fail to link on SwiftShader: `SceneShaderGLES3`/`SkyShaderGLES3
Program linking failed: Fragment shader active uniforms exceed
GL_MAX_FRAGMENT_UNIFORM_VECTORS (261)`. On API-34 the GLThread exits
and GodotActivity force-quits (~10 s, SIG 9, no native crash); on
API-36 the GLThread itself SIGSEGVs (~40 s — previously masked because
the audio thread crashed first at ~34 s). Not worked around by the
audio repack.

*Game-side uniform diet attempted and rejected (2026-11-04):* capping
`rendering/limits/opengl/max_renderable_lights=16` and
`max_lights_per_object=4` in project.godot changed nothing — same
overflow, same death — and later logcat showed `CanvasShaderGLES3`
(the 2D HUD shader) failing too. The overflow lives in Godot 4.7's
base Compatibility shaders (scene/sky/canvas), not in game-side light
counts, so no project setting or scene light diet fixes it. The caps
were reverted. This is engine-level; it would need an engine-side
shader-diet (or the Oboe/AAudio-era renderer work) upstream. The web
build is unaffected — Chrome's WebGL2 exposes a far higher limit.

**Bottom line:** there is currently NO emulator image that runs this
Godot 4.7 build for more than ~40 s — mobile verification requires a
real device (human task). The Dummy APK remains useful for audio-free
emulator experiments and as the airtight causality proof for crash 1.
AVD note on this box: avdmanager wrote `Pixel7_API34` into
`~/.config/.android/avd` (XDG) while `Pixel7_API36` lives in the legacy
`~/.android/avd`, and emulator 37.2 only searches one of them — set
`ANDROID_AVD_HOME` to whichever actually holds the AVD.
