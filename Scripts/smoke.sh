#!/bin/bash
# End-to-end check of the engine: download part of Sintel (Blender Foundation, CC BY)
# for 40 s, simulate a crash with SIGKILL, restart, and confirm progress came back from
# resume data. Everything lives in /tmp/freshet-smoke and is removed afterwards.
set -u
cd "$(dirname "$0")/.."
swift build --product freshet-smoke || exit 1
BIN="$(swift build --show-bin-path)/freshet-smoke"
ROOT=/tmp/freshet-smoke
rm -rf "$ROOT"
echo "== run 1: download for 40 s, then SIGKILL"
"$BIN" --root "$ROOT" --seconds 40 --kill
echo "run 1 exit: $?"
echo "== run 2: restart from resume data"
"$BIN" --root "$ROOT" --seconds 15 --expect-resume
code=$?
echo "run 2 exit: $code"
rm -rf "$ROOT"
exit $code
