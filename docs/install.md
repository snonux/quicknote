# Installing and building TurboNotes

The easy way to install TurboNotes on Android is the
[snonux F-Droid repository](https://github.com/snonux/fdroid); see the
[README](../README.md#install). This page covers everything else: installing
an APK by hand, the Linux desktop build, and building from source.

## An APK by hand

Every [GitHub release](https://github.com/snonux/turbonotes/releases) has
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
targets on every push and pull request.

## Releases

How to cut a release and publish it to F-Droid is in [release.md](release.md).
