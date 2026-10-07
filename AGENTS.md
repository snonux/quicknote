# Working on Quicknote

Quicknote is a Flutter app (Android primary, Linux desktop for development)
that edits every Markdown file in one configured notes folder. It is a sibling
of snonux/quicklog and shares its toolchain, signing and release conventions,
but has no S3 or any other network code: the Android release manifest has no
`INTERNET` permission, and nothing should add one.

Before calling anything done: `flutter analyze` and `flutter test` must both be
clean. For anything touching the Android build, build a release APK too --
`flutter build apk --release --split-per-abi` -- because the debug build hides
signing and packaging problems. CI does all three plus a Linux release build.

Toolchain: JDK **17 or 21** only. Gradle 8.14 rejects JDK 25 outright.

## Layout

- `lib/services/note_store.dart` -- the `NoteStore` interface. Notes are
  addressed by relative POSIX paths (`projects/todo.md`), validated by
  `normalizeNotePath`. Two implementations: `DirectoryNoteStore` (dart:io,
  atomic writes) and `SafNoteStore` (Android document tree via the
  `org.buetow.quicknote/saf-notes` channel, implemented in
  `android/.../SafNotes.kt`). Keep their behaviour identical: same filtering
  (`.md`/`.markdown`, no dot-folders), `create` and `rename` never overwrite.
- `lib/editor/` -- the WYSIWYG editor. `MarkdownStyler` paints the Markdown
  source; it must emit exactly one character per source character (a few are
  substituted 1:1, like `-` -> `•`), or the caret and selection drift. The
  test `emits exactly one character per source character` guards that. Never
  replace this with a converter to another document model: a lossy round trip
  silently reformats people's notes.
- `lib/services/fuzzy.dart` -- the fuzzy matcher behind the finder.
- `lib/screens/home_screen.dart` -- tree plus editor side by side at 760 px
  and wider; narrower, a note opens on its own `NotePage`. Note dialogs
  (path prompt, delete confirmation) live in `lib/widgets/note_dialogs.dart`,
  snackbars and user-facing error text in `lib/widgets/feedback.dart`.

## Releasing

Same scheme as Quicklog. The traps:

**Bump the build number.** `version:` in `pubspec.yaml` is `<semver>+<counter>`.

**The per-ABI version code scheme is `counter * 10 + abi`** (1 armeabi-v7a,
2 arm64-v8a, 3 x86_64), set by the `applicationVariants` block at the bottom of
`android/app/build.gradle.kts`. Do not drop that block.

**Write the changelog three times**, as `n1.txt`, `n2.txt`, `n3.txt` under
`fastlane/metadata/android/en-US/changelogs/` for counter `n`.

**Never remove the `dependenciesInfo` block from `android/app/build.gradle.kts`**:
F-Droid's scanner rejects the Google Play dependency-metadata signing block.

**Release builds are path-sensitive** if they are ever to be reproducible on
F-Droid: build from `/tmp/build` against an SDK at `/opt/android-sdk`
(`flutter config --android-sdk`), as `.github/workflows/release.yml` does.

**Pushing a `vX.Y.Z` tag** runs `.github/workflows/release.yml` (for now in `docs/workflows/`; see the README there), which builds
the signed per-ABI APKs and attaches them to the GitHub release. It needs the
secrets `ANDROID_KEYSTORE` (base64 of the keystore), `ANDROID_KEY_ALIAS`,
`ANDROID_KEYSTORE_PASSWORD` and `ANDROID_KEY_PASSWORD`;
`FDROID_DISPATCH_TOKEN` is optional. Quicknote needs its **own** keystore
(`keys/quicknote-release.jks`, git-ignored): it is the app's identity, and
losing it means existing installs can never be updated.

## Signing

`android/key.properties` is git-ignored and optional. When present all four of
`storeFile`, `storePassword`, `keyAlias`, `keyPassword` are required and the
build fails loudly if any are missing; a relative `storeFile` resolves against
`android/app/`. Without it, release builds fall back to the debug keys and say
so.

## Testing gotchas

**No `dart:io` directly in a `testWidgets` body.** The body runs on a fake
clock where those futures never complete, and the test hangs. Widget tests use
`test/support/memory_note_store.dart`; filesystem tests are plain `test()`s
(`test/note_store_test.dart`).

**`pumpAndSettle` times out while a save is pending**: the Save button shows a
spinner, which never settles. Pump a fixed duration instead.
