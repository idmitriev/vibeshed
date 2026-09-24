# Releasing Vibeshed

Public releases are tagged from `main`, built by the GitHub Actions [`Release`](.github/workflows/release.yml) workflow, and published as GitHub Releases. Homebrew users install via a separate tap that points at those release assets.

Release builds are **ad-hoc signed and not notarized** — no Apple Developer account or repository secrets are needed. The trade-offs:

- Gatekeeper blocks the first launch of a downloaded copy. Users either click **Open Anyway** in System Settings → Privacy & Security, or run `xattr -dr com.apple.quarantine /Applications/Vibeshed.app`. The release notes spell this out.
- An ad-hoc signature has no stable identity, so macOS treats every release as a new app for TCC: Accessibility, Input Monitoring, Screen Recording, Automation, Full Disk Access, and Calendar permissions have to be re-granted after each update.

## One-time setup

### Homebrew tap (optional)

Create a repo named `homebrew-tap` (literal prefix `homebrew-`) under your GitHub account. The cask template lives at [`scripts/Casks/vibeshed.rb`](scripts/Casks/vibeshed.rb) in this repo — copy it into `Casks/vibeshed.rb` in the tap repo on each release, updating `version` and `sha256`.

Users then install with `brew install --cask idmitriev/tap/vibeshed`. The Gatekeeper first-launch step above still applies.

## Cutting a release

```sh
scripts/cut-release.sh 0.2.0
```

This tags `v0.2.0` and pushes it. The Release workflow takes a few minutes: build → ad-hoc codesign → zip → upload to a fresh GitHub Release.

Then update the Homebrew tap:

```sh
shasum -a 256 Vibeshed-0.2.0.zip   # download from the release first
```

PR the new `sha256` and `version` into `homebrew-tap/Casks/vibeshed.rb`.

## Versioning

Semver. The Makefile derives the version from the latest `git describe --tags`, so tagged builds embed the right version into `Info.plist` without a manual bump.

## Pre-release builds

Tags containing `-` (e.g. `v0.2.0-rc1`) are uploaded as **prereleases** automatically.

## Manual / local release builds

`make build` produces a locally-signed `.build/Vibeshed.app` using your Apple Development cert — that's for testing, not distribution. To reproduce a release build locally, run the workflow's "Build and sign .app" step by hand (it signs with `codesign --sign -`).

## Switching to notarized builds

Notarization needs a paid Apple Developer account: a **Developer ID Application** certificate plus an App Store Connect API key, stored as repository secrets. The workflow that did this — importing the cert into a temporary keychain, signing with `--timestamp`, then `notarytool submit --wait` and `stapler staple` — is in the history at commit `9cc79e4` (`chore: release prep`); restore those steps and their secrets to go back.
