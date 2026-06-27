#!/usr/bin/env bash
# Precise AST pass: run clang-query matchers over a repo that has a compile_commands.json.
# Produces per-repo counts of (all overrides) vs (verbose/dependent-return overrides),
# DEDUPED across translation units.
#
# Usage: ./scripts/scan_clang_query.sh <repo_dir> [compile_db_dir]
#   <repo_dir>        e.g. repos/Catch2
#   [compile_db_dir]  dir containing compile_commands.json (default: <repo_dir>/build)
#
# Prereqs: clang-query + python3 on PATH, and a compile_commands.json
#   (generate with: cmake -S <repo> -B <repo>/build -G Ninja \
#                         -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
#                         -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_C_COMPILER=clang)
#
# WHY DEDUP: a virtual override declared in a header is parsed once per TU that includes
# that header, so a naive `grep -c 'binding for'` multiply-counts the same declaration.
# We key each match on the CANONICAL (normalized-path, line) of the bound CXXMethodDecl
# and count distinct declarations only. The matcher's "v" binding (see matchers/
# verbose_overrides.txt) already restricts to template-specialization / decltype /
# dependent RETURN types as written, so "v" is the verbose/dependent numerator and "o"
# (all overrides) is the denominator.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="${1:?usage: scan_clang_query.sh <repo_dir> [compile_db_dir]}"
db="${2:-$repo/build}"
matcher="$here/scripts/matchers/verbose_overrides.txt"
raw="$here/findings/raw"; mkdir -p "$raw"
name="$(basename "$repo")"

command -v clang-query >/dev/null || { echo "clang-query not on PATH"; exit 1; }
command -v python3      >/dev/null || { echo "python3 not on PATH"; exit 1; }
[ -f "$db/compile_commands.json" ] || {
  echo "No $db/compile_commands.json. Generate it first:"
  echo "  cmake -S $repo -B $db -G Ninja -DCMAKE_EXPORT_COMPILE_COMMANDS=ON"; exit 1; }

# absolute, normalized repo source root — used to keep only the repo's OWN declarations
# (so STL/system-header overrides pulled in via #include do not inflate the denominator).
repo_root="$(cd "$repo" && pwd)"

# Drive clang-query and dedup in python (robust on Windows paths with ..\ segments).
python3 - "$name" "$db" "$matcher" "$raw" "$here/findings/clang-query-summary.tsv" "$repo_root" <<'PY'
import json, os, re, subprocess, sys
name, db_dir, matcher, raw, sumtsv, repo_root = sys.argv[1:7]
db = os.path.join(db_dir, "compile_commands.json")
# Keep only the repo's OWN declarations (so STL/system-header overrides pulled in via
# #include do not inflate the denominator). Match on the `/repos/<name>/` path segment —
# robust to MSYS vs Windows drive spellings (/d/.. vs d:/..) — and drop the build dir.
seg   = "/repos/" + name.lower() + "/"
build = seg + "build/"
tus = sorted({e["file"] for e in json.load(open(db, encoding="utf-8"))
              if e["file"].lower().endswith((".cpp",".cc",".cxx",".c++",".c"))})

# clang-query's -f parser rejects `//` comments and blank lines (a single bad line
# silently kills ALL matches). Strip the human-readable matcher down to commands only.
import tempfile
cmds = [ln for ln in open(matcher, encoding="utf-8").read().splitlines()
        if ln.strip() and not ln.lstrip().startswith("//")]
mf = tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8")
mf.write("\n".join(cmds) + "\n"); mf.close(); matcher = mf.name

DECL = re.compile(r'CXXMethodDecl 0x[0-9a-f]+ <([^,>]+)')
def norm(loc):
    m = re.match(r'(.*):(\d+):(\d+)$', loc) or re.match(r'(.*):(\d+)$', loc)
    if not m: return None
    path = os.path.normpath(m.group(1)).replace("\\","/").lower()
    if seg not in path or build in path:   # repo-owned, non-generated only
        return None
    return (path, m.group(2))

uniq = {"o": {}, "v": {}}
# Small batches: clang-query aborts an ENTIRE invocation if one TU fails to load from the
# compile DB, so large batches silently lose every TU behind a single bad one. Per-batch
# isolation keeps a bad TU from zeroing the whole repo.
B = 12
for i in range(0, len(tus), B):
    chunk = tus[i:i+B]
    try:
        out = subprocess.run(["clang-query","-p",db_dir,"-f",matcher,*chunk],
                             capture_output=True, text=True, timeout=2400).stdout
    except Exception as ex:
        sys.stderr.write(f"[{name}] batch {i}: {ex}\n"); continue
    cur = None
    for ln in out.splitlines():
        s = ln.strip()
        if   s.startswith('Binding for "o"'): cur="o"; continue
        elif s.startswith('Binding for "v"'): cur="v"; continue
        elif s.startswith('Binding for "root"'): cur=None; continue
        if cur and s.startswith("CXXMethodDecl"):
            m = DECL.search(s)
            if not m: continue
            k = norm(m.group(1).strip())
            if not k: continue
            tm = re.search(r"'([^']*\))'", s)
            ret = tm.group(1).split("(")[0].strip() if tm else ""
            uniq[cur].setdefault(k, (f"{k[0]}:{k[1]}", ret))
    sys.stderr.write(f"[{name}] TUs {i+1}..{i+len(chunk)}/{len(tus)} o={len(uniq['o'])} v={len(uniq['v'])}\n")

with open(os.path.join(raw, f"clang-query-{name}-verbose.txt"), "w", encoding="utf-8") as f:
    for disp, ret in sorted(uniq["v"].values()):
        f.write(f"{disp}\t{ret}\n")
no, nv = len(uniq["o"]), len(uniq["v"])
pct = 100.0*nv/no if no else 0.0
line = f"{name}\t{len(tus)}\t{no}\t{nv}\t{pct:.1f}"
print(f"{name}: TUs={len(tus)} overrides(unique)={no} verbose/dependent(unique)={nv} ({pct:.1f}%)")
hdr = "repo\tTUs\toverrides_unique\tverbose_unique\tpct\n"
need_hdr = not os.path.exists(sumtsv) or os.path.getsize(sumtsv)==0
with open(sumtsv, "a", encoding="utf-8") as f:
    if need_hdr: f.write(hdr)
    f.write(line+"\n")
PY
