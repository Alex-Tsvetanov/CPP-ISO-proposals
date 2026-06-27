#!/usr/bin/env bash
# Verify the patched Clang against the proposal's positive and negative cases.
#
#   tests/positive/*.cpp   annotated  // EXPECT-PASS              -> must compile
#   tests/negative/*.cpp   annotated  // EXPECT-FAIL: <substring> -> must be rejected,
#                                                                    diagnostic must contain <substring>
#
# Set CLANGXX to the patched compiler (default: the in-tree build under clang/).
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLANGXX="${CLANGXX:-$here/clang/llvm-project/build/bin/clang++}"
STD="${STD:-c++2c}"
pass=0; fail=0

command -v "$CLANGXX" >/dev/null 2>&1 || [ -x "$CLANGXX" ] || {
  echo "CLANGXX not found: $CLANGXX"; echo "Build it (Workflow B) or set CLANGXX."; exit 1; }

echo "Using: $CLANGXX  (-std=$STD)"; echo

for f in "$here"/tests/positive/*.cpp; do
  [ -e "$f" ] || continue
  if "$CLANGXX" -std="$STD" -fsyntax-only "$f" 2>/dev/null; then
    echo "PASS  $(basename "$f")"; pass=$((pass+1))
  else
    echo "FAIL  $(basename "$f")  (expected to compile, but was rejected)"; fail=$((fail+1))
  fi
done

for f in "$here"/tests/negative/*.cpp; do
  [ -e "$f" ] || continue
  want="$(sed -nE 's@.*//[[:space:]]*EXPECT-FAIL:[[:space:]]*(.*)@\1@p' "$f" | head -1)"
  err="$("$CLANGXX" -std="$STD" -fsyntax-only "$f" 2>&1)"
  if [ $? -eq 0 ]; then
    echo "FAIL  $(basename "$f")  (expected rejection, but it compiled)"; fail=$((fail+1))
  elif [ -n "$want" ] && ! grep -qF "$want" <<<"$err"; then
    echo "FAIL  $(basename "$f")  (rejected, but diagnostic missing: \"$want\")"; fail=$((fail+1))
  else
    echo "PASS  $(basename "$f")"; pass=$((pass+1))
  fi
done

echo; echo "=== $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
