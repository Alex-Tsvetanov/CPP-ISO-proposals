#!/usr/bin/env bash
#
# Build the auto-return-override proposal (HTML, LaTeX, PDF) with the
# mpark/wg21 Pandoc framework.
#
# This invokes the framework's documented Pandoc command directly instead of
# going through its Makefile, which lets it run on Windows (Git Bash + native
# Pandoc + MiKTeX) where the framework's `make`/install scripts do not. It also
# works on Linux/macOS.
#
# Requirements (all already satisfied on this machine):
#   - Pandoc 3.9.0.2          (the exact version mpark/wg21 pins)
#   - Python 3 + venv
#   - A LaTeX engine with xelatex (MiKTeX or TeX Live) for PDF output
#   - Open network on first run (downloads the citation + stable-label DBs)
#
# Usage:
#   ./build.sh                  # build html, latex, and pdf
#   ./build.sh html             # build a single format (html | latex | pdf)
#   WG21_DIR=/path ./build.sh   # reuse an existing mpark/wg21 checkout
#   REFRESH=1 ./build.sh        # re-download the citation / stable-label DBs
#
set -euo pipefail

PAPER="auto-return-override"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Default: a sibling `wg21` checkout next to the repo root (../../wg21).
WG21_DIR="${WG21_DIR:-$(cd "$HERE/../.." && pwd)/wg21}"
DATA="$WG21_DIR/data"
VENV="$WG21_DIR/.venv"

# Pandoc and the filters emit UTF-8; force it so Windows' cp1252 default does
# not corrupt the citation database or the rendered output.
export PYTHONUTF8=1

if [ "$#" -gt 0 ]; then formats=("$@"); else formats=(html latex pdf); fi

# Translate a Git-Bash mount path (/d/...) to a native Windows path (D:/...) so
# the Windows pandoc.exe can read it. No-op on Linux/macOS.
winpath() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }

# --- 1. framework checkout --------------------------------------------------
if [ ! -d "$DATA" ]; then
  echo ">> cloning mpark/wg21 into $WG21_DIR"
  git clone --depth 1 https://github.com/mpark/wg21.git "$WG21_DIR"
fi

# --- 2. python venv with the framework's filter dependencies ----------------
if [ -x "$VENV/Scripts/python.exe" ]; then
  PY="$VENV/Scripts/python.exe"; BIN="$VENV/Scripts"          # Windows venv
elif [ -x "$VENV/bin/python3" ]; then
  PY="$VENV/bin/python3"; BIN="$VENV/bin"                     # POSIX venv
else
  echo ">> creating venv + installing framework requirements"
  python -m venv "$VENV"
  if [ -x "$VENV/Scripts/python.exe" ]; then PY="$VENV/Scripts/python.exe"; BIN="$VENV/Scripts";
  else PY="$VENV/bin/python3"; BIN="$VENV/bin"; fi
fi
"$PY" -m pip install -q --upgrade pip
"$PY" -m pip install -q -r "$WG21_DIR/deps/requirements.txt"
# Put the venv first on PATH so Pandoc's .py filters run with panflute, not the
# bare system Python.
export PATH="$BIN:$PATH"

# --- 3. live databases (cached in the framework checkout) -------------------
# Runs a framework generator script with a portable shim that defines
# signal.SIGPIPE when the platform (Windows) lacks it.
run_gen() { # run_gen <script.py> <outfile> [stdin-file]
  local out="$DATA/$2"
  "$PY" -c 'import sys,signal,runpy
if not hasattr(signal,"SIGPIPE"): signal.SIGPIPE=getattr(signal,"SIGTERM",15)
runpy.run_path(sys.argv[1], run_name="__main__")' "$DATA/$1" \
    ${3:+< "$3"} > "$out.tmp"
  mv "$out.tmp" "$out"
}

if [ "${REFRESH:-0}" = "1" ] || [ ! -f "$DATA/csl.json" ] || [ ! -f "$DATA/srefs.defs" ]; then
  echo ">> generating citation + stable-label databases (network required)"
  run_gen refs.py     csl.json                       # wg21.link citations
  run_gen srefs.py    srefs.json                      # eel.is stable labels
  run_gen srefs-md.py srefs.defs "$DATA/srefs.json"   # markdown defs
fi

# --- 4. build ---------------------------------------------------------------
build_one() { # build_one <format>
  local fmt="$1" extra=()
  if [ "$fmt" = "html" ]; then
    local depth; depth="$("$PY" "$DATA/toc-depth.py" < "$HERE/$PAPER.md")"
    [ -n "$depth" ] && extra=(--toc-depth "$depth")
  fi
  ( cd "$HERE" && pandoc \
      "$(winpath "$DATA")/srefs.defs" "$PAPER.md" -o "$PAPER.$fmt" \
      --data-dir="$(winpath "$DATA")" -M data-dir="$(winpath "$DATA")" \
      -d doc -d formatting "${extra[@]}" )
  echo "   built $PAPER.$fmt"
}

for fmt in "${formats[@]}"; do
  echo ">> building $fmt"
  build_one "$fmt"
done
echo ">> done"
