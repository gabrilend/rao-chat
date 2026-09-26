#!/usr/bin/env bash
# 038-run-tests.sh — runs every room-tree test and totals the results.
#
# Each test is a small Lua program that builds rooms in a scratch home
# folder in RAM and checks the answers.  This script runs each one against
# the stand-in room-folders module kept in this tests/ folder, and against
# the real room-folders module (issue 101) when it exists, then prints one
# line per test and a total.  It exits non-zero if any test failed, and
# exits 3 (after saying so plainly) if the real module was not there to
# test against, since a skipped run is not a passed one.
#
# Usage: 038-run-tests.sh [DIR] [stand-in|real|both]
#   DIR    the project folder (default: the hard-coded one below)
#   which  which room-folders module to test against (default: both)

DIR="/home/ritz/programs/rao-chat"
if [ -n "$1" ]; then
    DIR="$1"
fi
WHICH="both"
if [ -n "$2" ]; then
    WHICH="$2"
fi

TESTS="$DIR/src/room-tree/tests"
mkdir -p "$DIR/tmp/shared-memory/room-tree"

case "$WHICH" in
    both)     TARGETS="stand-in real" ;;
    stand-in) TARGETS="stand-in" ;;
    real)     TARGETS="real" ;;
    *)        echo "which must be stand-in, real or both, not '$WHICH'"; exit 2 ;;
esac

FAILED_FILES=0
SKIPPED=0
for target in $TARGETS; do
    if [ "$target" = "real" ] && [ ! -f "$DIR/src/room-folders/002-room-folders.lua" ]; then
        echo "SKIPPED real: src/room-folders/002-room-folders.lua is not there yet"
        SKIPPED=1
        continue
    fi
    # 032-035 and 037 run against either module; 036 meets the real
    # neighbours (members, people links) and so runs only on real.  The
    # patterns end in .lua, so retired -done files are never run.
    PATTERN="$TESTS/03[2-57]-test-*.lua"
    if [ "$target" = "real" ]; then
        PATTERN="$TESTS/03[2-7]-test-*.lua"
    fi
    for test in $PATTERN; do
        if ! luajit "$test" "$DIR" "$target"; then
            FAILED_FILES=$((FAILED_FILES + 1))
            echo "  ^ $(basename "$test") against $target FAILED"
        fi
    done
done

echo "test files failed: $FAILED_FILES"
if [ "$FAILED_FILES" -gt 0 ]; then
    exit 1
fi
if [ "$SKIPPED" -gt 0 ]; then
    echo "WARNING: the real room-folders module was not tested against"
    exit 3
fi
exit 0
