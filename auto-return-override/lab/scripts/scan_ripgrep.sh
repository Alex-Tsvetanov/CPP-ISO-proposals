#!/usr/bin/env bash
# Fast heuristic pre-filter: find overriding methods whose WRITTEN return type looks
# verbose/dependent (the cases the proposal helps). Recall-oriented; expect false
# positives and confirm with the clang-query pass (scan_clang_query.sh).
#
# Usage: ./scripts/scan_ripgrep.sh [target_dir]   (default: all of repos/)
#
# Method (one traversal, then in-memory classification):
#   1. Traverse the corpus ONCE collecting every line that ends a declarator in
#      `override` (the heuristic DENOMINATOR: all single-line override declarations).
#   2. Classify those lines into the verbose/dependent NUMERATOR buckets with cheap
#      in-memory greps (decltype / typename / template-id / long std:: container).
#   3. Emit per-pattern and per-repo counts plus a denominator, so findings/usecases.md
#      can quote a heuristic "verbose overrides / total overrides" ratio per repo.
#
# IMPORTANT: the corpora live under repos/ which is git-ignored on purpose, so ripgrep
# is told `--no-ignore` (otherwise it honours lab/.gitignore's `repos/*` and finds
# nothing) and to skip the heavy `.git/` object stores.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="${1:-$here/repos}"
raw="$here/findings/raw"; mkdir -p "$raw"
summary="$here/findings/ripgrep-summary.md"

# Resolve a usable searcher. ripgrep is preferred, but note: inside some shells `rg`
# is only a shell function (e.g. Claude Code wraps ripgrep), which is invisible to this
# non-interactive script, so we test it and fall back to GNU `grep -P` (validated to give
# identical counts). EITHER WAY we must pass --no-ignore / skip VCS-ignored files: the
# corpus lives under repos/ which is git-ignored on purpose, so a naive ripgrep finds
# NOTHING (it honours lab/.gitignore's `repos/*`).
SEARCHER=""
if command -v rg >/dev/null 2>&1 && rg --version >/dev/null 2>&1; then SEARCHER="rg"
elif echo | grep -qP 'x?' 2>/dev/null;                                then SEARCHER="grep"
else echo "ERROR: need ripgrep (rg) or GNU grep with -P (PCRE)"; exit 1; fi
echo "Searcher: $SEARCHER" >&2

C_GLOBS_RG=(--type cpp --type c)
scan_repo() { # repo_dir pattern -> path:line:text on stdout
  # Exclude .git AND any build/ tree: generating a compile_commands.json (scan_clang_query)
  # creates repos/<repo>/build/_deps/ holding *downloaded dependencies* (e.g. spdlog's
  # build pulls a full copy of Catch2), which would otherwise pollute the override counts.
  local repo="$1" pat="$2"
  if [ "$SEARCHER" = rg ]; then
    rg -n --no-heading --no-ignore -g '!**/.git/**' -g '!**/build/**' "${C_GLOBS_RG[@]}" -e "$pat" "$repo" 2>/dev/null
  else
    grep -rnP --exclude-dir='.git' --exclude-dir='build' \
      --include='*.h' --include='*.hpp' --include='*.hh' --include='*.hxx' --include='*.ipp' \
      --include='*.cpp' --include='*.cc' --include='*.cxx' --include='*.c++' --include='*.c' \
      -e "$pat" "$repo" 2>/dev/null
  fi
}

# DENOMINATOR: a single-line declarator ending in `override` (optionally cv / ref /
# noexcept / final qualified, with or without a trailing `;`/`{`/`= 0`).
pat_override_decl='\)\s*(const\s+)?(&{1,2}\s*)?(noexcept(\([^)]*\))?\s*)?(final\s+)?override\b'

# NUMERATOR buckets (each is also an override declaration, hence a subset of the above):
pat_decltype='\bdecltype\s*\('                                     # decltype(...) on the decl
pat_typename='\btypename\b'                                        # dependent typename ...
pat_templated='[A-Za-z_][A-Za-z0-9_]*\s*<[^;{=<>]{3,}>\s*[A-Za-z_][A-Za-z0-9_]*\s*\('  # Foo<...> name(
pat_stl='\bstd::(unique_ptr|shared_ptr|weak_ptr|vector|map|unordered_map|set|optional|variant|function|tuple|pair|span|basic_string|string)\s*<'

allhits="$raw/_all_override_decls.txt"

echo "Scanning $target (per-repo traversal) ..." >&2
# ---- one traversal PER top-level repo: every single-line override declaration ----
# (Per-repo rather than one giant rg over the whole tree: faster per call, robust, and
#  the repo name is recoverable from each hit's path for the per-repo breakdown.)
: > "$allhits"
for repo in "$target"/*/; do
  [ -d "$repo" ] || continue
  rname="$(basename "$repo")"
  echo "  - $rname" >&2
  scan_repo "$repo" "$pat_override_decl" >> "$allhits" 2>/dev/null || true
done
total="$(wc -l < "$allhits" | tr -d ' ')"

# ---- in-memory classification into numerator buckets ----
classify() { # name pattern
  local name="$1" pat="$2"
  local out="$raw/ripgrep-$name.txt"
  grep -E "$pat" "$allhits" > "$out" 2>/dev/null || true
  wc -l < "$out" | tr -d ' '
}
n_decltype="$(classify decltype "$pat_decltype")"
n_typename="$(classify typename "$pat_typename")"
n_templated="$(classify templated "$pat_templated")"
n_stl="$(classify stl-container "$pat_stl")"

# Union of all verbose buckets (dedup lines) = heuristic numerator.
union="$raw/ripgrep-verbose-union.txt"
cat "$raw/ripgrep-decltype.txt" "$raw/ripgrep-typename.txt" \
    "$raw/ripgrep-templated.txt" "$raw/ripgrep-stl-container.txt" 2>/dev/null \
  | sort -u > "$union"
n_union="$(wc -l < "$union" | tr -d ' ')"

# ---- per-repo breakdown (repo = first path component under target/) ----
repo_table="$(
  awk -v t="$target" '
    { line=$0
      sub("^"t"[/\\\\]","",line)               # drop target prefix
      n=split(line, p, /[\/\\]/); repo=p[1]
      tot[repo]++ }
    END{ for (r in tot) printf "%s\t%d\n", r, tot[r] }
  ' "$allhits" | sort
)"
repo_verbose="$(
  awk -v t="$target" '
    { line=$0; sub("^"t"[/\\\\]","",line)
      n=split(line, p, /[\/\\]/); repo=p[1]; v[repo]++ }
    END{ for (r in v) printf "%s\t%d\n", r, v[r] }
  ' "$union" | sort
)"

{
  echo "# ripgrep heuristic scan"
  echo
  echo "_Heuristic single-line pre-filter (recall-oriented; confirm magnitudes with"
  echo "scan_clang_query.sh). Target: \`$target\`._"
  echo
  echo "**Denominator** = single-line declarators ending in \`override\`: **$total**."
  echo "**Numerator** = those whose written return type is verbose/dependent (union of"
  echo "the four buckets below, deduplicated): **$n_union**."
  echo
  echo "| bucket | hits | raw file |"
  echo "| --- | ---: | --- |"
  echo "| decltype(...) | $n_decltype | findings/raw/ripgrep-decltype.txt |"
  echo "| typename ... | $n_typename | findings/raw/ripgrep-typename.txt |"
  echo "| template-id \`Foo<...>\` | $n_templated | findings/raw/ripgrep-templated.txt |"
  echo "| long \`std::\` container | $n_stl | findings/raw/ripgrep-stl-container.txt |"
  echo "| **verbose union** | **$n_union** | findings/raw/ripgrep-verbose-union.txt |"
  echo
  echo "## Per-repo (heuristic)"
  echo
  echo "| repo | override decls | verbose/dependent | % |"
  echo "| --- | ---: | ---: | ---: |"
  join -t $'\t' -a1 -e 0 -o '0,1.2,2.2' \
    <(printf '%s\n' "$repo_table") \
    <(printf '%s\n' "$repo_verbose") 2>/dev/null \
  | awk -F'\t' '{ pct = ($2>0)? 100*$3/$2 : 0; printf "| %s | %d | %d | %.1f%% |\n", $1,$2,$3,pct }'
} | tee "$summary"

echo >&2
echo "Summary -> $summary ; raw buckets + union under $raw/" >&2
