# CLAUDE.md — `auto … override` evidence & implementation lab

This is the operational guide for an agent (Claude Code) working in `lab/`. It also serves
as the project description (PROJECT.md). The parent directory contains the proposal
**"Deduced return type for overriding functions via `auto`"**
([`../auto-return-override.md`](../auto-return-override.md)). Read that paper first — the
normative rules below come from it.

## What this proposal says (the spec you are implementing & testing)

A function declared with the **bare `auto`** placeholder **and** `override` takes its
return type from the function it overrides. Precisely:

- Let `T` be the overridden function's return type. The override's return type **is** `T`,
  fixed at the declaration (so vtable layout / override checking are unaffected).
- **Every `return` statement must already yield `T`.** The type `auto` would deduce from a
  `return` statement must equal `T`; otherwise the program is **ill-formed**. No implicit
  conversion is applied (e.g. `bool` base + `return "pumpkin"` is rejected, not coerced).
- Covariance is **not** synthesized: `auto f() override` yields exactly `T`, never a
  derived pointer/reference. Covariant returns must still be written out.
- `auto` and the written-out `T` may be **mixed** across the in-class declaration and an
  out-of-line definition; a written-out type that disagrees with `T` is ill-formed.
- `decltype(auto)` and constrained placeholders remain ill-formed (out of scope).

## Ground rules (read before doing anything)

- **The patch must be genuinely correct and owned by the author**, not plausible-looking
  filler. Reviewers explicitly asked that the implementation be real and understood. Prefer
  **minimal, surgical diffs**; explain every change; never claim a build/test passed that
  you did not actually run.
- **Every use-case claim must be backed by a `file:line` a reviewer can open.** No
  aggregate number goes in `findings/` without the underlying hits saved alongside it.
- **Do not commit large directories.** `repos/` and `clang/` are git-ignored; keep it that
  way. Commit only scripts, matchers, tests, and findings.
- **Line numbers in Clang drift between versions.** Locate code by the *search anchors*
  given below (`rg "anchor" clang/llvm-project/clang`), not by hard-coded line numbers.
- Work in three independent workflows (A, B, C). A and B can proceed in parallel; C needs B.

---

## Workflow A — mine production use-cases

Goal: a `findings/usecases.md` report showing real overrides whose return type is verbose
or dependent, with counts and citations, to answer "is the problem real and widespread?"

### A1. Clone the corpus
```bash
./scripts/clone_repos.sh            # shallow-clones every entry in repos.txt into repos/
```

### A2. Fast heuristic pass (ripgrep — no build required)
```bash
./scripts/scan_ripgrep.sh           # writes findings/raw/ripgrep-*.txt and a summary
```
This finds overrides whose written return type contains `decltype`, `typename`, a
template-id, or a long `std::` container — the painful-to-restate cases. It is a
*pre-filter*: fast, recall-oriented, with false positives. Use it to rank repos and to
spot-check candidates by hand.

### A3. Precise AST pass (clang-query — needs a compile DB)
The accurate measurement uses Clang's AST matchers, which see the *real* return type
(including covariance and dependence), not text.

1. Generate a compilation database for a repo that uses CMake:
   ```bash
   cmake -S repos/<repo> -B repos/<repo>/build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
   # (configure only; a full build is usually unnecessary for AST matching)
   ```
2. Run the matchers:
   ```bash
   ./scripts/scan_clang_query.sh repos/<repo>
   ```
   This applies `scripts/matchers/verbose_overrides.txt`, which binds:
   - all overriding methods (the denominator),
   - overriding methods whose return type is a template-specialization / dependent /
     `decltype` type and is **identical** to the base (the candidates this feature helps).

### A4. Write up `findings/usecases.md`
For each strong hit record: repo, `path:line`, the base declaration, the override as
written today, the equivalent under the proposal, and one sentence on why the current form
is fragile (e.g. "renaming `Base` silently desyncs the `decltype`"). End with a table:
per repo — total overrides, overrides with dependent/verbose identical return types, and
the percentage. That percentage is the headline number for the paper's
"Motivation and Scope" section.

> Quality bar: a handful of *compelling* dependent-return-type examples plus one solid
> frequency number beats a long list of `int`-returning overrides (which the committee
> will dismiss as mere keystroke-saving).

---

## Workflow B — implement the feature in Clang (fork + branch)

Goal: a buildable Clang on a public branch that accepts the proposal's syntax and enforces
its rules, so the paper can link a prototype and Compiler Explorer can host it.

### B1. Fork & branch
Fork `llvm/llvm-project` to the author's account (**github.com/Alex-Tsvetanov**) via the
GitHub UI or `gh repo fork`, then:
```bash
cd clang
git clone https://github.com/Alex-Tsvetanov/llvm-project.git
cd llvm-project
git remote add upstream https://github.com/llvm/llvm-project.git
git checkout -b auto-return-override
```

### B2. Build (Release + assertions; expect a large, slow first build)
```bash
cmake -S llvm -B build -G Ninja \
  -DLLVM_ENABLE_PROJECTS=clang \
  -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_ASSERTIONS=ON \
  -DLLVM_TARGETS_TO_BUILD=host \
  -DLLVM_USE_LINKER=lld -DLLVM_CCACHE_BUILD=ON
ninja -C build clang        # first build: tens of minutes + many GB; incremental is fast
```
Resulting compiler: `clang/llvm-project/build/bin/clang++`.

### B3. Where to change it (locate by anchor, then read the surrounding logic)

1. **Lift the prohibition for `auto` + `override`.**
   Anchor: `rg "err_auto_fn_virtual" clang/include clang/lib`
   (diagnostic "function with deduced return type cannot be virtual"). Find where Sema
   emits it (in `clang/lib/Sema/SemaDecl.cpp`, function-declarator checking). Suppress it
   when the method carries the `override` specifier *and* overrides a base virtual.

2. **Resolve the overridden method and set the return type to its type `T`.**
   Anchors: `Sema::AddOverriddenMethods`, `CXXMethodDecl::begin_overridden_methods`
   (in `clang/lib/Sema/SemaDeclCXX.cpp`). Override resolution already runs; reuse its
   result. If multiple overridden methods disagree on return type, diagnose (your
   `[class.virtual]` multi-base rule).

3. **Replace body-based deduction with the exact-match check.**
   Anchors: `DeduceFunctionTypeFromReturnExpr`, `DeduceReturnType` (in
   `clang/lib/Sema/SemaStmt.cpp` / `SemaDecl.cpp`). For an `auto`-override, do **not**
   deduce from the body; instead, for each `return`, compute the type `auto` would deduce
   and require it to equal `T`. On mismatch emit a **new** diagnostic.

4. **Add the new diagnostic.**
   In `clang/include/clang/Basic/DiagnosticSemaKinds.td` add e.g.
   `err_auto_override_return_mismatch : Error<"returned type %0 does not match the "
   "overridden function %1">;` Phrase it in terms of the overridden function (the author
   asked for "does not match `long A::f()`", not an ambiguous-deduction error).

5. **Relax the redeclaration rule for overriding functions** (the out-of-line cases).
   Anchors: `MergeFunctionDecl`, `err_auto_different_redeclaration` /
   `err_auto_fn_different_deduction`. Allow an overriding function's declarations to mix
   `auto` and the written-out `T`; diagnose only when two written-out types differ.

6. **Feature-test macro.**
   Anchor: `rg "__cpp_explicit_this_parameter|InitializeCPlusPlusFeatureTestMacros" clang/lib/Frontend/InitPreprocessor.cpp`
   Define `__cpp_deduced_virtual_override_return` (value `202600L` placeholder) alongside
   the other `__cpp_` macros. Gate the feature behind `-std=c++2c` for now.

### B4. Iterate
Rebuild with `ninja -C build clang` after each change (incremental builds are quick).
Keep the diff minimal and commented. Run Workflow C continuously.

---

## Workflow C — verify with the patched Clang

Goal: prove the prototype implements the spec — accepting every legal form and rejecting
every illegal one with the right diagnostic.

```bash
export CLANGXX="$PWD/clang/llvm-project/build/bin/clang++"
./scripts/run_tests.sh              # runs tests/positive + tests/negative, prints PASS/FAIL
```

- `tests/positive/*.cpp` must compile (`-std=c++2c -fsyntax-only`). Each file is annotated
  `// EXPECT-PASS`.
- `tests/negative/*.cpp` must be **rejected**, and the diagnostic must contain the
  annotated substring: `// EXPECT-FAIL: <substring>`.

The seed tests mirror the proposal's cases (basic, out-of-line ×4 combinations,
dependent-return, qualifiers; pumpkin mismatch, int-vs-long, missing-`override`,
multi-base disagreement, out-of-line concrete mismatch, `decltype(auto)`). **Expand them to
full coverage** as you implement — add a test for every rule and every diagnostic, and add
the interesting hits found in Workflow A as real-world regression cases.

When the feature stabilizes, also add lit tests under
`clang/llvm-project/clang/test/SemaCXX/` so the work is upstreamable and reviewers can run
it in-tree.

### Definition of done
- `run_tests.sh` is green on the full positive/negative suite.
- `findings/usecases.md` cites real overrides with a frequency number.
- The branch builds cleanly from scratch and a short `clang++` invocation on Compiler
  Explorer (custom build) demonstrates before/after.
- A one-paragraph "Implementation experience" update is ready to fold back into the paper.
