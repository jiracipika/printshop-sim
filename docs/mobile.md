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

## RUNTIME CAVEAT (pre-existing, not a game bug)

On the API-36 (Android 16) emulator the app boots and renders ~34 s,
then dies: SIGSEGV SEGV_ACCERR in the AudioTrack thread —
`libgodot_android.so` via `libwilhelm` (OpenSL `onMoreData`). The
PRE-3.0 baseline (bbc0648, v0.57.0) crashes IDENTICALLY on the same
emulator — this is Godot 4.7.1's OpenSL driver vs that image, outside
game scope. `-no-audio` on the emulator does NOT help (the guest HAL
still drives the app's OpenSL client). Pick mobile verification up on:
an older-API emulator image (the 2026-09-29 verification predates API
36), a real arm64 device, or Godot's Android audio-driver option.
