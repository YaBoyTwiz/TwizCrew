#!/usr/bin/env bash
# Runs the TwizCrew tests. Usage: tests/run.sh [pattern]   (pattern: Lua pattern or plain text, "a|b" = either)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if command -v lua5.1 >/dev/null 2>&1; then LUA=lua5.1; else LUA="$ROOT/tools/lua-5.1.5/src/lua"; fi
cd "$ROOT" || exit 1
exec "$LUA" tests/run.lua "$@"
