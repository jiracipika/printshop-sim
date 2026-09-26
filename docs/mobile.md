# printshop-sim on Android

The `Android` export preset (added as prep work, mirroring Friday
Evacuation's proven config) produces an **unsigned** APK at
`builds/printshop-sim.apk`. Godot's internal signer is disabled
(`package/signed=false`) on purpose — sign afterwards with the
repo-committed `android/debug.keystore` so every build installs and
upgrades cleanly. That key is debug-only; never ship it to a store.

## One-time toolchain

The CampaignGoal mobile toolchain lives on the external SSD. Source it first:

```bash
source /Volumes/ADATA/Android/env.sh
```

That gives you `ANDROID_HOME` (`/Volumes/ADATA/Android/sdk`), a JDK 21
`JAVA_HOME`, `adb`/`emulator`/`apksigner` on PATH, and the `campaign_test`
AVD. Godot 4.7.1 export templates are already installed at
`~/Library/Application Support/Godot/export_templates/4.7.1.stable/`.

## Build, sign, install

```bash
cd /Volumes/HARD/projects/printshop-sim
mkdir -p builds
# Godot writes the unsigned APK and then exits non-zero (no editor keystore
# configured) — the APK on disk is complete, like FE's CI does.
godot --headless --path . --export-release "Android" || true
test -f builds/printshop-sim.apk

BT=34.0.0
zipalign -f 4 builds/printshop-sim.apk /tmp/printshop-aligned.apk
apksigner sign --ks android/debug.keystore --ks-key-alias androiddebugkey \
  --ks-pass pass:android --key-pass pass:android \
  --out /tmp/printshop-signed.apk /tmp/printshop-aligned.apk
mv /tmp/printshop-signed.apk builds/printshop-sim.apk
apksigner verify builds/printshop-sim.apk

# Install + run on the emulator (see /Volumes/ADATA/mobile-setup/README.md
# for the full boot/screencap loop)
adb install -r builds/printshop-sim.apk
adb shell monkey -p com.jiracipika.printshopsim 1
```

Package: `com.jiracipika.printshopsim` · versionCode 1 · arm64-v8a
(gradle build off — prebuilt-template export, same as FE).
