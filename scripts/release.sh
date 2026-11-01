#!/usr/bin/env bash
# Usage: scripts/release.sh VERSION
# Bumps the version, tags it, pushes, and points the Homebrew formula at the
# new tag's tarball.
set -euo pipefail
cd "$(dirname "$0")/.."

v="${1:?usage: scripts/release.sh VERSION (e.g. 0.1.1)}"
v="${v#v}"
repo="pattont/RexAgentRestore"
formula="Formula/rex-agent-restore.rb"

[ -z "$(git status --porcelain)" ] || { echo "commit your changes first" >&2; exit 1; }

sed -i '' "s/^VERSION=\".*\"/VERSION=\"$v\"/" bin/rex-agent-restore
git commit -qam "Release v$v" || true
git tag "v$v"
git push origin HEAD "v$v"

url="https://github.com/$repo/archive/refs/tags/v$v.tar.gz"
sha="$(curl -fsSL "$url" | shasum -a 256 | awk '{print $1}')"
sed -i '' "s|^  url \".*\"|  url \"$url\"|; s|^  sha256 \".*\"|  sha256 \"$sha\"|" "$formula"
git commit -qam "Formula: v$v"
git push origin HEAD
echo "Released v$v ($sha)"
