# Implementation experience — Clang prototype

A complete prototype of this proposal was implemented in Clang (LLVM `main`,
self-identifying as clang 23.0.0git, built Release + assertions). It passes the full
positive/negative conformance suite in [`../tests`](../tests) (12/12) and an in-tree
`-verify` lit test, leaves pre-C++26 behaviour and all existing override/covariance
handling unchanged, and is a **156-line additive diff** across six files
([`clang-prototype.patch`](clang-prototype.patch)).

## Paragraph for the paper ("Implementation experience")

> The proposal has been prototyped in Clang. The change is small and reuses machinery the
> compiler already has: override resolution (which runs while the member is declared) and
> the existing `auto` return-type deduction. When a member function is declared with the
> bare `auto` placeholder and `override`, the prototype takes the return type from the
> function it overrides and fixes it at the declaration — so vtable layout, override
> checking, and out-of-line definitions proceed exactly as for a written-out type — and
> checks each `return` statement against that type with no implicit conversion. Mixing
> `auto` and the written-out type across declarations is reconciled in the existing
> redeclaration-merging step; a disagreeing written-out type is diagnosed. `decltype(auto)`,
> constrained placeholders, and the no-`override` case remain ill-formed. The whole feature
> is a 156-line additive diff to Sema, gated behind `-std=c++2c`, with a new feature-test
> macro `__cpp_deduced_virtual_override_return`. No new analysis was required, supporting
> the claim that this is a narrow, low-risk extension. Branch:
> `github.com/Alex-Tsvetanov/llvm-project` (branch `auto-return-override`).

## What changed and why (maps to the paper's "Proposed wording")

| Proposal change | Where in Clang | What the prototype does |
| --- | --- | --- |
| Relax the virtual-`auto` prohibition for `auto … override` (Change 1) | `SemaDeclCXX.cpp` `CheckOverridingFunctionReturnType` | For an undeduced bare-`auto` return type, **defer** the "different return type" diagnostic; the type is fixed later (C++26 only). |
| Return type is the overridden function's, fixed at declaration (Change 2) | `SemaDeclCXX.cpp` new `ActOnDeducedAutoOverrideReturnType`, called from `ActOnCXXMemberDeclarator` once `override` + the overridden set are known | Compute the common overridden return type `T`, `setType` to `T`, record the function so its `return`s are checked. Multiple bases that disagree → `err_auto_override_ambiguous_return`. `decltype(auto)`/constrained/no-`override` → existing `err_auto_fn_virtual` ("cannot be virtual"). |
| Each `return` must already yield `T`, no conversion ([design.returns]) | `SemaStmt.cpp` `BuildReturnStmt` | For a recorded function, compute the type `auto` would deduce from the operand (`DeduceAutoType`) and require it to equal `T`; otherwise `err_auto_override_return_mismatch` ("does not match"). |
| Mix `auto` / written-out across declarations; disagreement ill-formed (Change 3) | `SemaDecl.cpp` `MergeFunctionDecl` | For an overriding function, reconcile: a redeclaration spelled `auto` adopts `T`; a written-out type equal to `T` is accepted; a disagreeing written-out type → "does not match". This relaxes the `[dcl.spec.auto]p13` "repeat the placeholder" rule exactly where the paper says it is safe. |
| Feature-test macro (Change 4) | `InitPreprocessor.cpp` | `__cpp_deduced_virtual_override_return = 202606L`, defined under `-std=c++2c`. |

Two new diagnostics were added (`DiagnosticSemaKinds.td`):
`err_auto_override_return_mismatch` and `err_auto_override_ambiguous_return`.

## Conformance results (`scripts/run_tests.sh`, `-std=c++2c`)

`12 passed, 0 failed`. The suite mirrors the paper's cases:

| | case | result |
| --- | --- | --- |
| p01 | basic `auto test() override` → `int` | PASS |
| p02–p04 | out-of-line: auto/auto, auto/written, written/auto | PASS |
| p05 | dependent/verbose base return type | PASS |
| p06 | `const` / `noexcept` qualifiers | PASS |
| n01 | `return "pumpkin"` vs `bool` → "does not match" | PASS (rejected) |
| n02 | `return 0` vs `long` → "does not match" | PASS (rejected) |
| n03 | no `override` → "cannot be virtual" | PASS (rejected) |
| n04 | multiple bases disagree → "does not match a unique type" | PASS (rejected) |
| n05 | out-of-line written-out `long` vs `int` → "does not match" | PASS (rejected) |
| n06 | `decltype(auto)` override → "cannot be virtual" | PASS (rejected) |

Regression spot-checks (all behave as before): normal non-virtual `auto` functions,
covariant overrides, written-out overrides, plain `virtual`. The proposal's own examples
also behave as specified — `auto f() override { return 0L; }` against a `long` base
compiles, `return 0;` against `long` is rejected, and an explicit `static_cast<long>` is
accepted. Under `-std=c++17` the same `auto … override` remains ill-formed, confirming the
feature is correctly gated.

## Build notes (Windows)

Built with `clang-cl` + `lld-link` + Ninja, `-DLLVM_TARGETS_TO_BUILD=host`,
`-DLLVM_DISABLE_ASSEMBLY_FILES=ON` (avoids the MASM dependency for BLAKE3). The patched
translation units (`SemaDecl.cpp`, `SemaDeclCXX.cpp`, `SemaStmt.cpp`, `InitPreprocessor.cpp`)
compile cleanly; the diff is purely additive (no existing line removed except one guarded
`if` condition extended). A Compiler Explorer "custom build" of this branch can host the
before/after demonstration referenced in the paper.

## Known limitations of the prototype (not the proposal)

- `virtual auto f() override` (redundant `virtual` keyword written *with* `override`) still
  hits the early `err_auto_fn_virtual` check that fires on the written `virtual` specifier
  before override resolution; the canonical spelling `auto f() override` is what the paper
  uses and is fully supported. Lifting this is a few lines in `SemaDecl.cpp`'s
  function-declarator path and is left as a follow-up.
- The fixed return type is stored on the `FunctionDecl` while its `TypeSourceInfo` still
  spells `auto`; this is invisible to semantics but means a diagnostic's return-type
  *source range* may underline `auto`. Cosmetic only.
- Tracking of which functions are `auto … override` uses a `Sema`-side set, so it is not
  serialized into PCH/modules. Fine for a single-TU prototype / Compiler Explorer; a
  production patch would store a bit on `FunctionDecl`.
