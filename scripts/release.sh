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
# GitHub can take a moment to serve a new tag's tarball. Never accept an
# empty or failed download.
tarball="$(mktemp)"
for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsSL "$url" -o "$tarball" && [ -s "$tarball" ] && tar -tzf "$tarball" >/dev/null 2>&1; then
    break
  fi
  rm -f "$tarball"; tarball="$(mktemp)"
  sleep 6
done
[ -s "$tarball" ] && tar -tzf "$tarball" >/dev/null 2>&1 ||
  { echo "couldn't download $url (is the repo public?). The formula was not updated." >&2; exit 1; }
sha="$(shasum -a 256 < "$tarball" | awk '{print $1}')"
rm -f "$tarball"
sed -i '' "s|^  url \".*\"|  url \"$url\"|; s|^  sha256 \".*\"|  sha256 \"$sha\"|" "$formula"
git commit -qam "Formula: v$v"
git push origin HEAD
echo "Released v$v ($sha)"
