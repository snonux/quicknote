# GitHub Actions workflows

These belong in `.github/workflows/`. They live here only because the tool
that created this repository could not push workflow files; move them over
with:

```sh
git mv docs/workflows/ci.yml docs/workflows/release.yml .github/workflows/
```

- `ci.yml` -- analyze, test, and build the Android and Linux release targets
  on every push and pull request.
- `release.yml` -- on a `vX.Y.Z` tag, build the signed per-ABI APKs and attach
  them to the GitHub release (see AGENTS.md, "Releasing").
