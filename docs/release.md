# Releasing TurboNotes to F-Droid

TurboNotes reaches phones through the
[snonux F-Droid repository](https://github.com/snonux/fdroid). Nothing is built
there: this repository builds and signs the APKs when a `vX.Y.Z` tag is pushed,
and the F-Droid repository picks up the GitHub release and publishes it.

```
git tag vX.Y.Z ──► Release workflow (this repo) ──► GitHub release with 3 APKs
                                                          │
             phones ◄── F-Droid index (snonux/fdroid) ◄───┘  every 6 h, or at once
```

## Once: signing setup

Do this before the first release only. Needs a JDK (`keytool`), `openssl`,
`git` and the [GitHub CLI](https://cli.github.com) logged in (`gh auth login`).

```sh
tool/setup_release.sh
```

The script:

1. creates the release keystore `keys/turbonotes-release.jks` with a random
   password (git-ignored),
2. writes `android/key.properties` for local release builds,
3. sets the four signing secrets on GitHub: `ANDROID_KEYSTORE`,
   `ANDROID_KEY_ALIAS`, `ANDROID_KEYSTORE_PASSWORD` and `ANDROID_KEY_PASSWORD`.

It is safe to run again; it keeps an existing keystore.

**Back up `keys/turbonotes-release.jks` and `android/key.properties`**, for
example in your password manager. The key is the app's identity: without it,
existing installs can never be updated.

Optional, so a release shows up in F-Droid at once instead of within six
hours: create a fine-grained GitHub token with *Contents: read and write* on
`snonux/fdroid` and store it as a secret here:

```sh
gh secret set FDROID_DISPATCH_TOKEN -R snonux/turbonotes
```

Check with `gh secret list -R snonux/turbonotes`.

## Every release

1. **Bump the version** in `pubspec.yaml`. It is `<semver>+<counter>`; raise
   the semver as you like and the counter by exactly one, e.g. `0.1.0+1` →
   `0.2.0+2`. Android version codes are `counter * 10 + abi`, so counter 2
   ships as 21, 22 and 23.
2. **Write the changelog three times**, one file per CPU type, with the same
   text: `fastlane/metadata/android/en-US/changelogs/<counter>1.txt`,
   `<counter>2.txt` and `<counter>3.txt` (e.g. `21.txt`, `22.txt`, `23.txt`).
   F-Droid shows it as "What's new". Keep it under 500 characters.
3. Optionally update the store text and screenshots in
   `fastlane/metadata/android/en-US/` (`short_description.txt`,
   `full_description.txt`, `images/phoneScreenshots/`). F-Droid reads them
   from the tagged commit.
4. **Commit and push to `main`**, and wait for CI to go green.
5. **Tag and push the tag.** The tag must be `v` plus the semver from
   `pubspec.yaml`, or the release workflow fails:

   ```sh
   git tag v0.2.0
   git push origin v0.2.0
   ```

6. **Watch the Release workflow** (Actions tab, or `gh run watch`). It builds
   the three signed APKs, checks they are not debug-signed, and attaches them
   to the GitHub release `v0.2.0` (created with generated notes if you have
   not written one by hand first).
7. **F-Droid picks it up.** The snonux/fdroid publish workflow runs every six
   hours (at once with `FDROID_DISPATCH_TOKEN`), downloads the APKs and the
   fastlane metadata at the tag, and re-signs the index. To publish right
   away without the token, run it by hand:

   ```sh
   gh workflow run publish.yml -R snonux/fdroid
   ```

   Phones then see the update after F-Droid refreshes its repositories (pull
   down in the F-Droid app's *Updates* tab).

## When something goes wrong

- **"Tag vX does not match version Y in pubspec.yaml"**: the tag and the
  `version:` line differ. Delete the tag (`git push --delete origin vX`,
  `git tag -d vX`), fix one of them, and tag again.
- **"The ANDROID_* signing secrets are not all set"**: run
  `tool/setup_release.sh`, then rebuild the existing tag without re-tagging:
  `gh workflow run release.yml -R snonux/turbonotes -f tag=v0.2.0`.
- **Warning about a missing changelog**: the release still works, but F-Droid
  shows no "What's new". Add the files on `main`; they appear with the next
  release.
- **The release is not in F-Droid**: drafts and pre-releases are skipped, and
  only the newest two releases are kept. Check the latest run of the
  [publish workflow](https://github.com/snonux/fdroid/actions/workflows/publish.yml).
- **F-Droid refuses the update** ("signature mismatch"): the APKs were signed
  with a different key than the installed app. Restore the backed-up keystore
  and run `tool/setup_release.sh` again; never generate a new key for an app
  that is already released.

The build traps (reproducible-build paths, the version-code block, the
F-Droid scanner) are in [AGENTS.md](../AGENTS.md#releasing).
