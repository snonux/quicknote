#!/usr/bin/env bash
# One-time release setup for TurboNotes. Run it from anywhere in the checkout:
#
#   tool/setup_release.sh
#
# It is safe to run again; every step skips what is already done.
#
# 1. Creates the release keystore keys/turbonotes-release.jks with a random
#    password, unless it exists. BACK IT UP: it is the app's identity, and
#    losing it means existing installs can never be updated.
# 2. Writes android/key.properties for local release builds.
# 3. Sets the GitHub secrets the release workflow signs with
#    (ANDROID_KEYSTORE, ANDROID_KEY_ALIAS, ANDROID_KEYSTORE_PASSWORD,
#    ANDROID_KEY_PASSWORD), using the gh CLI.
# 4. Moves the workflows from docs/workflows/ to .github/workflows/ on main,
#    commits and pushes, if that has not happened yet.
#
# Needs keytool (any JDK), openssl, git and gh (logged in, `gh auth login`).
set -euo pipefail

repo=snonux/quicknote
alias=turbonotes
root=$(git rev-parse --show-toplevel)
cd "$root"
keystore=keys/turbonotes-release.jks
props=android/key.properties
# A keystore made before the rename (keys/quicknote-release.jks) stays the
# app's key: key.properties says where it is.
if [[ -f $props ]]; then
  stored=$(sed -n 's/^storeFile=//p' "$props")
  [[ -n $stored ]] && keystore=$(realpath -m --relative-to=. "android/app/$stored")
fi

for tool in keytool openssl gh git; do
  command -v "$tool" >/dev/null || { echo "missing: $tool" >&2; exit 1; }
done

prop() { sed -n "s/^$1=//p" "$props"; }

# 1 + 2: keystore and key.properties.
if [[ -f $keystore ]]; then
  echo "Keystore $keystore exists, keeping it."
  [[ -f $props ]] || {
    echo "But $props is missing; recreate it by hand (storeFile, storePassword," >&2
    echo "keyAlias, keyPassword) so this script can read the passwords." >&2
    exit 1
  }
else
  mkdir -p keys
  # PKCS12 keystores use one password for the store and the key.
  password=$(openssl rand -base64 30 | tr -d '/+=\n' | cut -c1-32)
  keytool -genkeypair -noprompt -keystore "$keystore" -storetype PKCS12 \
    -alias "$alias" -keyalg RSA -keysize 4096 -validity 10000 \
    -storepass "$password" -keypass "$password" \
    -dname "CN=TurboNotes, O=snonux"
  umask 077
  cat >"$props" <<EOF
storeFile=../../$keystore
storePassword=$password
keyAlias=$alias
keyPassword=$password
EOF
  echo "Created $keystore and $props. Back up both, e.g. to your password manager."
fi

# 3: GitHub secrets, read from key.properties so nothing is typed.
base64 -w0 "$keystore" | gh secret set ANDROID_KEYSTORE -R "$repo"
gh secret set ANDROID_KEY_ALIAS -R "$repo" --body "$(prop keyAlias)"
gh secret set ANDROID_KEYSTORE_PASSWORD -R "$repo" --body "$(prop storePassword)"
gh secret set ANDROID_KEY_PASSWORD -R "$repo" --body "$(prop keyPassword)"
echo "Set the four signing secrets on $repo."

# 4: workflows into place.
git fetch -q origin main
if git cat-file -e origin/main:.github/workflows/release.yml 2>/dev/null; then
  echo "Workflows already in .github/workflows on main."
else
  # In a temporary worktree, so this works from any branch and leaves the
  # current checkout alone.
  tmp=$(mktemp -d)
  trap 'git worktree remove --force "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT
  git worktree add -q "$tmp" origin/main
  (
    cd "$tmp"
    mkdir -p .github/workflows
    git mv docs/workflows/ci.yml docs/workflows/release.yml .github/workflows/
    git rm -q docs/workflows/README.md
    git commit -q -m "Move CI and release workflows into .github/workflows"
    git push -q origin HEAD:main
  )
  echo "Moved the workflows to .github/workflows and pushed main."
fi

echo
echo "Done. Optional: gh secret set FDROID_DISPATCH_TOKEN -R $repo"
echo "(a token with Contents read/write on snonux/fdroid) so F-Droid picks a"
echo "release up at once instead of within six hours."
