#!/usr/bin/env bash
# Make a GitHub release that WowUp can install for WoW Forever.
# Usage: scripts/release.sh "Short notes for friends"
# Before running: bump ADDON_VERSION (TwizCrew/Core/Init.lua) and "## Version" (TwizCrew/TwizCrew.toc), commit.
set -euo pipefail
cd "$(dirname "$0")/.."
notes="${1:-}"

v=$(sed -n 's/^## Version: *//p' TwizCrew/TwizCrew.toc | tr -d '\r')
code_v=$(sed -n 's/^local ADDON_VERSION = "\(.*\)"/\1/p' TwizCrew/Core/Init.lua)
[ -n "$v" ] && [ "$v" = "$code_v" ] || { echo "Version mismatch: toc '$v', Init.lua '$code_v'"; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Commit everything first."; exit 1; }
if git rev-parse -q --verify "refs/tags/v$v" >/dev/null; then echo "v$v is already released. Bump the version."; exit 1; fi
tests/run.sh | tail -1 | grep -q "ALL PASSED" || { echo "Tests fail. Not releasing."; exit 1; }

# WowUp picks the zip whose name ends in -forever, or reads release.json (flavor "forever").
rm -rf dist && mkdir dist
zip="TwizCrew-$v-forever.zip"
git archive --format=zip --prefix=TwizCrew/ -o "dist/$zip" HEAD:TwizCrew
cat > dist/release.json <<EOF
{"releases":[{"name":"TwizCrew","version":"$v","filename":"$zip","nolib":false,"metadata":[{"flavor":"forever","interface":16001}]}]}
EOF

git tag -a "v$v" -m "TwizCrew v$v"
git push origin master "v$v"
gh release create "v$v" "dist/$zip" dist/release.json --title "TwizCrew v$v" --notes "$notes"
echo "Released v$v"
