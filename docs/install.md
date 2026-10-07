# Installing and building Quicknote

The easy way to install Quicknote on Android is the
[snonux F-Droid repository](https://github.com/snonux/fdroid); see the
[README](../README.md#install). This page covers everything else: installing
an APK by hand, the Linux desktop build, and building from source.

## An APK by hand

Every [GitHub release](https://github.com/snonux/quicknote/releases) has
signed APKs, one per CPU type. Most phones want `app-arm64-v8a-release.apk`.
Download it on the phone and open it, or install it from a computer:

```sh
adb install -r app-arm64-v8a-release.apk
```

## Building from source

Requirements:

- [Flutter](https://flutter.dev), stable channel, version pinned in
  `.flutter-version`.
- Android: the Android SDK and JDK 17 or 21 (Gradle 8.14 rejects JDK 25):
  `flutter config --jdk-dir=$HOME/jdk21`.
- Linux: `gtk3-devel`, `clang`, `cmake`, `ninja-build`, `pkg-config` and
  `xz-devel` (Fedora package names).

```sh
# Linux desktop
flutter run -d linux                          # development, with hot reload
flutter build linux --release                 # build/linux/x64/release/bundle/

# Android
flutter run -d <device-id>                    # development on a device
flutter build apk --release --split-per-abi   # per-ABI release APKs
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk

# Checks
flutter analyze
flutter test
```

The CI workflow runs these checks and builds the Android and Linux release
targets on every push and pull request. It is in `docs/workflows/` for now and
only runs once moved to `.github/workflows/`; see the README there.

## Releases

The version lives in one place, the `version:` line of `pubspec.yaml`
(`<semver>+<buildNumber>`). Bump the build number by one per release and tag
the release commit `vX.Y.Z`. Split APKs get the version code
`buildNumber * 10 + abi`, so `0.1.0+1` ships as 11, 12 and 13. Store text and
screenshots live in `fastlane/metadata/android/en-US/`. The details, and the
traps, are in [AGENTS.md](../AGENTS.md).

The logo is drawn by `tool/draw_logo.py`.
