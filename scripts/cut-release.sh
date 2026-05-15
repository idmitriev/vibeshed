#!/usr/bin/env bash
# Cut a new release: tag, push, wait for the GitHub Actions release workflow,
# then print the cask update snippet (sha256 + version).
#
# Usage: scripts/cut-release.sh 0.2.0

set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <version>  e.g. $0 0.2.0" >&2
  exit 1
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]]; then
  echo "Version must be semver (e.g. 0.2.0 or 0.2.0-rc1), got: $VERSION" >&2
  exit 1
fi

TAG="v${VERSION}"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree dirty — commit or stash first." >&2
  exit 1
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG already exists." >&2
  exit 1
fi

echo "Tagging $TAG..."
git tag -a "$TAG" -m "Release $TAG"
git push origin "$TAG"

echo
echo "Tag pushed. The 'Release' workflow on GitHub Actions will build, sign,"
echo "notarize, and publish the GitHub Release."
echo
echo "Once the release is live, update the Homebrew cask:"
echo "  1. Download Vibeshed-${VERSION}.zip from the release"
echo "  2. sha256: shasum -a 256 Vibeshed-${VERSION}.zip"
echo "  3. Update scripts/Casks/vibeshed.rb (version + sha256) and PR it to your homebrew tap"
