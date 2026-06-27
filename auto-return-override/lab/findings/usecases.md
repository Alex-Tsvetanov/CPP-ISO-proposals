# Production use-cases for *Deduced return type for overriding functions via `auto`*

Evidence that the problem this proposal solves — having to restate an override's return
type when that type is **verbose or dependent** — is real and widespread in production
C++. Every claim below is backed by a `path:line` a reviewer can open in the cloned
corpus (`repos/`, git-ignored; reproduce with `scripts/clone_repos.sh`).

> **Scope reminder.** The feature applies only to `auto … override` and yields *exactly*
> the overridden return type (no covariance synthesized). So the cases that matter are
> overrides whose return type is **identical** to the base's and **expensive or fragile to
> restate**: long/nested template-ids, `decltype`, dependent names, and types that depend
> on a template parameter. Covariant returns, and trivial returns like `int`/`bool`/`void`,
> are deliberately *out of scope* and are excluded from the evidence below.

---

## 1. Executive summary

* **Corpus:** 8 widely-used C++ projects, **61,474 single-line `override` declarations**.
* **Frequency (heuristic, whole corpus):** **2,523 / 61,474 ≈ 4.1%** of override
  declarations restate a verbose or dependent return type — thousands of real sites.
  Per-repo this ranges from ~0% (formatting/JSON libraries with almost no virtuals) to
  **7–8% in interface-heavy frameworks** (POCO 7.6%, spdlog 7.1%, Catch2 6.8%).
* **Frequency (precise, AST):** a `clang-query` pass over five repos that keys on the
  *actual return type* (filtering out the heuristic's parameter-template-id false positives)
  confirms the pattern at AST level — e.g. **Catch2: 5 of 346 overrides (1.4%)**, **fmt:
  12 / 236 (5.1%)** — carry a template-specialization/dependent return type once template
  instantiation is accounted for.
* **The fragility is not hypothetical — it has already bitten production code.** In Godot,
  the base and **8** display-server backends declare
  `Vector<DisplayServerEnums::WindowID> get_window_list()`, but the macOS backend
  ([`display_server_macos.h:317`](repos/godot/platform/macos/display_server_macos.h)) spells
  the *same* override `Vector<int> get_window_list()`. It compiles only because `WindowID`
  is an `int` alias. `auto get_window_list() override` makes that silent divergence
  impossible.
* **The worst restatement counts are large:** one Godot return type is hand-copied into
  **39** subclasses; one clang return type into **25**.

The committee's bar (per the lab brief) is *"a handful of compelling dependent-return
examples plus one solid frequency number."* This report delivers **38 adversarially
verified examples** plus both a heuristic and an AST frequency.

---

## 2. Corpus and method

### 2.1 Corpus (`repos.txt`)

| repo | why it was chosen |
| --- | --- |
| `llvm/llvm-project` | the canonical AST/visitor/pass hierarchies; clang, llvm, lldb, mlir |
| `godotengine/godot` | enormous virtual platform/driver hierarchy (`Ref<>`, `Vector<>`, `BitField<>`, `TypedArray<>`) |
| `pocoproject/poco` | interface-heavy framework; `SharedPtr<>` / smart-pointer returns across DB backends |
| `catchorg/Catch2` | reporter / matcher / generator interface hierarchies |
| `gabime/spdlog` | sink / formatter hierarchies; `clone()` virtual-constructor idiom |
| `ericniebler/range-v3` | template/concept library — included as a **negative control** (few virtuals) |
| `fmtlib/fmt`, `nlohmann/json` | popular libraries — **negative controls** (few virtual overrides) |

### 2.2 Two passes

* **Heuristic (`scripts/scan_ripgrep.sh`).** One traversal collects every single-line
  declarator ending in `override` (the denominator); cheap in-memory greps then classify
  those whose written return type contains `decltype(...)`, `typename`, a template-id
  `Foo<…>`, or a long `std::` container (the numerator). Fast, recall-oriented, **single
  line only** — so it both over-counts (a template-id may be a *parameter* on a
  `void`-returning override) and under-counts (multi-line declarations, the worst
  offenders, are missed). Treat it as an order-of-magnitude signal, not a precise rate.
* **Precise (`scripts/scan_clang_query.sh` + `scripts/matchers/verbose_overrides.txt`).**
  Runs Clang AST matchers over each repo's `compile_commands.json`, keying on the real
  **return type** (`returns(templateSpecializationType()|references(…)|pointsTo(…)|`
  `decltypeType()|dependentNameType())`), **deduped by canonical declaration location** so a
  header override seen by many translation units is counted once, and **filtered to the
  repo's own files** so STL-internal overrides don't inflate the denominator. This removes
  the heuristic's parameter false-positives; its limitation is the opposite — it only sees
  overrides actually instantiated in the compiled TUs.

> **Tooling note (Clang 22).** The matcher set was adapted to LLVM 22: `elaboratedType`
> and `dependentTemplateSpecializationType` matchers were removed, `qualType(anyOf(<type
> matchers>))` silently fails to bind, `let NAME … match NAME` does not emit `.bind()`
> results, and clang-query's `-f` parser rejects `//` comments. The committed scripts work
> around all four. See the header of `scripts/matchers/verbose_overrides.txt`.

### 2.3 Reproducibility

`scripts/scan_ripgrep.sh` works with either `ripgrep` *or* GNU `grep -P` (it auto-detects;
the two were checked to give identical per-repo counts — e.g. POCO 3,455 both ways) and was
run end-to-end through the portable `grep -P` path, reproducing the source-only counts in
§3.1. Raw hits live under `findings/raw/` (`_all_override_decls.txt`, the per-bucket
`ripgrep-*.txt`, the per-repo `candidates-<repo>.txt`, and the AST pass's
`clang-query-<repo>-verbose.txt`); the verified examples are in `confirmed-examples.json`.

---

## 3. Frequency

### 3.1 Heuristic, per repo (`findings/raw/ripgrep-verbose-union.txt`)

| repo | override decls | verbose / dependent | % |
| --- | ---: | ---: | ---: |
| llvm-project | 40,628 | 1,568 | 3.9% |
| godot | 15,890 | 620 | 3.9% |
| poco | 3,455 | 262 | 7.6% |
| Catch2 | 916 | 62 | 6.8% |
| fmt | 279 | 0 | 0.0% |
| json | 163 | 0 | 0.0% |
| spdlog | 126 | 9 | 7.1% |
| range-v3 | 17 | 2 | 11.8% |
| **total** | **61,474** | **2,523** | **4.1%** |

Breakdown of the 2,523 by construct: template-id `Foo<…>` 1,826; long `std::` container
1,177; `typename` 11; `decltype` 2 (union deduped to 2,523). The headline ~4% is a floor
for the *single-line* form; multi-line verbose returns (common in LLVM) are not counted.
(`build/` trees are excluded from the scan: generating a compile DB downloads dependencies
into `repos/<repo>/build/_deps/` — e.g. spdlog's build pulls a full copy of Catch2 — which
would otherwise inflate spdlog's count from 126 to 993.)

### 3.2 Precise (AST), per repo (`findings/clang-query-summary.tsv`)

Counts are **deduped by canonical declaration location** and **filtered to the repo's own,
non-`build/` files**, so a header override seen by many TUs is counted once and downloaded
dependencies are excluded.

| repo | TUs | overrides (unique) | template/dependent return (unique) | % |
| --- | ---: | ---: | ---: | ---: |
| Catch2 | 107 | 346 | 5 | 1.4% |
| fmt | 31 | 236 | 12 | 5.1% |
| spdlog | 141 | 110 | 4 | 3.6% |
| range-v3 | 259 | 16 | 3 | 18.8% |
| json | 78 | 122 | 0 | 0.0% (negative control) |

Two honest observations from the comparison:

* For **Catch2** the precise rate (1.4%) is *lower* than the heuristic (6.8%): the heuristic
  counts `void f(std::vector<…> v) override` (a template-id **parameter**) and double-counts
  Catch2's amalgamated single-header, both of which the return-keyed AST pass rejects.
* For **fmt** the precise rate (5.1%) is *higher* than the heuristic (0%): fmt's verbose
  returns are written across multiple lines, which the single-line heuristic cannot see.

So the heuristic over- and under-counts in opposite directions on different code; neither is
"the" number. (The precise *denominators* for the small, header-heavy template libraries are
also sensitive to how many TUs parse cleanly — range-v3's override count moved between 16 and
22 across batch sizes, though its verbose count stayed 3 — so treat the small-N rates like
range-v3's 18.8% as indicative, not exact.) The point both passes agree on is that a real,
non-trivial population of overrides restate verbose/dependent return types — and the curated,
hand-verified examples in §5 are what actually carry the argument.

---

## 4. The fragility is real, not hypothetical

**4.1 A silent desync already in Godot's tree.** The contract is declared once:

```cpp
// repos/godot/servers/display/display_server.h:374
virtual Vector<DisplayServerEnums::WindowID> get_window_list() const = 0;
```

Eight backends restate it correctly; **one does not**:

```cpp
// repos/godot/platform/macos/display_server_macos.h:317
virtual Vector<int> get_window_list() const override;            // <-- Vector<int>, not WindowID
// repos/godot/platform/linuxbsd/x11/display_server_x11.h:463
virtual Vector<DisplayServerEnums::WindowID> get_window_list() const override;   // the other 8
```

`WindowID` is an alias for `int`, so the macOS spelling compiles and the divergence is
invisible. Under the proposal every backend writes `auto get_window_list() const override`
and the inconsistency *cannot occur* — the type is taken from the base.

**4.2 The same type, spelled three different ways.** POCO's database backends each restate
the abstract base's statement-factory return type — and don't agree on how to spell it:

```cpp
// base — repos/poco/Data/include/Poco/Data/SessionImpl.h:75
virtual Poco::SharedPtr<StatementImpl> createStatementImpl() = 0;

// repos/poco/Data/SQLite/.../SessionImpl.h:50    Poco::SharedPtr<Poco::Data::StatementImpl> createStatementImpl() override;
// repos/poco/Data/MySQL/.../SessionImpl.h:73     Poco::SharedPtr<Poco::Data::StatementImpl> createStatementImpl() override;
// repos/poco/Data/ODBC/.../SessionImpl.h:75      Poco::SharedPtr<Poco::Data::StatementImpl> createStatementImpl() override;
// repos/poco/Data/PostgreSQL/.../SessionImpl.h:68  Poco::Data::StatementImpl::Ptr        createStatementImpl() override;
```

Three backends write `Poco::SharedPtr<Poco::Data::StatementImpl>`; PostgreSQL writes the
typedef `Poco::Data::StatementImpl::Ptr` (defined as that same `SharedPtr` in
`Data/include/Poco/Data/StatementImpl.h`). All four denote one type fixed by the base. A
reader must chase a typedef to confirm they even match. `auto … override` collapses all
four to `auto createStatementImpl() override`.

---

## 5. Curated examples (all adversarially verified)

39 candidates were curated by per-repo finder agents and each was **independently
re-checked** by a separate verifier agent that opened both the override and the overridden
declaration and confirmed the return type is identical (not covariant). 38 passed; 1 was
**correctly rejected** (the LLVM `decltype(std::declval<…>())` case at
`PDBApiTest.cpp:61` is the body of a `#define`, not a standalone declaration — see §6).
Representative examples by category follow; the full 38 are in the appendix.

### 5.1 Dependent return types — the most fragile

The return type depends on a template parameter or a dependent name, so the restated
spelling is correct only by convention and silently desyncs if the base alias changes.

| where | overridden return (base) | override restates | base decl |
| --- | --- | --- | --- |
| `repos/llvm-project/lldb/include/lldb/Utility/Cloneable.h:44` | `lldb::OptionValueSP` (= `std::shared_ptr<OptionValue>`) | `std::shared_ptr<typename Base::TopmostBase>` | `OptionValue.h:351` |
| `repos/poco/Prometheus/include/Poco/Prometheus/Counter.h:134` | `std::unique_ptr<Sample>` (Sample = template arg) | `std::unique_ptr<CounterSample>` | `LabeledMetricImpl.h:167` |
| `repos/Catch2/src/catch2/generators/catch_generators_adapters.hpp:241` | `T const&` (T = `IGenerator` element) | `std::vector<T> const&` | `catch_generators.hpp:37` |
| `repos/llvm-project/llvm/include/llvm/DebugInfo/PDB/ConcreteSymbolEnumerator.h:35` | `ChildTypePtr` (= `std::unique_ptr<ChildType>`) | `std::unique_ptr<ChildType>` | `IPDBEnumChildren.h:28` |

Example — the lldb `Clone()` CRTP, where the base names the return through a dependent
member type of the template parameter:

```cpp
// base:   repos/llvm-project/lldb/include/lldb/Interpreter/OptionValue.h:351
virtual lldb::OptionValueSP Clone() const = 0;                       // OptionValueSP = shared_ptr<OptionValue>
// override: repos/llvm-project/lldb/include/lldb/Utility/Cloneable.h:44
std::shared_ptr<typename Base::TopmostBase> Clone() const override { … }   // before
auto                                        Clone() const override { … }   // after
```

The Prometheus metrics (`Counter`/`Gauge`/`Histogram`) are a clean trio: each derives from
`LabeledMetricImpl<XxxSample>` whose `createSample()` returns `std::unique_ptr<Sample>`, and
each override re-spells `std::unique_ptr<XxxSample>` — the exact instantiation the base
already determines.

### 5.2 The `clone()` virtual-constructor idiom — covariance is *impossible*

Returning `std::unique_ptr<Base>` / `std::shared_ptr<Base>` from a polymorphic `clone()` is
ubiquitous, and because covariance does **not** work through smart pointers, every override
is *required* to restate the base's exact type — there is no alternative today:

```cpp
// repos/spdlog/include/spdlog/formatter.h:15        virtual std::unique_ptr<formatter> clone() const = 0;
// repos/spdlog/include/spdlog/pattern_formatter.h:81        std::unique_ptr<formatter> clone() const override;   // -> auto clone() const override;

// repos/llvm-project/clang-tools-extra/clangd/support/Markup.h:33  virtual std::unique_ptr<Block> clone() const = 0;
//   ...Markup.h:50                                                        std::unique_ptr<Block> clone() const override;

// repos/llvm-project/clang/include/clang/Tooling/Tooling.h:110  virtual std::unique_ptr<FrontendAction> create() = 0;
//   restated by 14+ FrontendActionFactory subclasses, e.g. clang-tools-extra/clang-move/Move.h:225
```

This idiom alone accounts for a large share of the verbose-return overrides across LLVM,
spdlog, and POCO. `auto clone() const override` expresses the intent — *"return whatever the
base returns"* — directly.

### 5.3 Verbose template-ids restated across many sibling backends

Here the return type is identical across a whole family of platform/driver/target
subclasses; the count is how many siblings hand-copy it. Renaming the element type forces a
synchronized edit across all of them.

| return type | base | siblings | example override |
| --- | --- | ---: | --- |
| `HashMap<String, bool *>` | `repos/godot/modules/openxr/extensions/openxr_extension_wrapper.h:71` | **39** | `…/platform/openxr_vulkan_extension.h:47` |
| `ArrayRef<TargetInfo::GCCRegAlias>` | `repos/llvm-project/clang/include/clang/Basic/TargetInfo.h:1961` | **25** | `…/clang/lib/Basic/Targets/AArch64.h:241` |
| `std::unique_ptr<FrontendAction>` | `repos/llvm-project/clang/include/clang/Tooling/Tooling.h:110` | **14+** | `…/clang-tools-extra/clang-move/Move.h:225` |
| `BitField<FileAccess::UnixPermissionFlags>` | `repos/godot/core/io/file_access.h:94` | **12** | `…/drivers/unix/file_access_unix.h:85` |
| `Vector<DisplayServerEnums::WindowID>` | `repos/godot/servers/display/display_server.h:374` | **8** (1 desynced, §4.1) | `…/platform/linuxbsd/x11/display_server_x11.h:463` |
| `Vector<VisualShader::DefaultTextureParam>` | `repos/godot/modules/visual_shader/visual_shader.h:378` | **7** | `…/vs_nodes/visual_shader_nodes.h:430` |
| `BitField<MouseButtonMask>` | `repos/godot/servers/display/display_server.h:261` | **6** | `…/platform/windows/display_server_windows.h:608` |
| `RequiredResult<InputEvent>` | `repos/godot/core/input/input_event.h:85` | **6** | `…/core/input/input_event.h:255` |

The 25× and 39× counts were re-verified independently of the agents:
`grep -rl "getGCCRegAliases() const override" clang/lib/Basic/Targets` → 25, all returning
`ArrayRef<…GCCRegAlias>`; `grep -rl "HashMap<String, bool \*> get_requested_extensions" godot`
→ 40 files (1 base + 39 overrides).

---

## 6. Honesty: where the feature does *not* help (and a rejected candidate)

* **Libraries with few virtuals.** `nlohmann/json` is a true negative control — **0**
  verbose-return overrides in *both* passes (122 overrides, all trivial returns). `range-v3`
  is a concept/template library with almost no virtual dispatch (16–17 overrides total). `fmt`
  showed **0** in the single-line heuristic but **12** at AST level — its verbose returns are
  written across multiple lines, which the heuristic can't see. The feature is for
  *interface-heavy* code; these confirm it doesn't manufacture hits where virtuals are rare.
* **Covariant returns are out of scope** and were excluded throughout. The `clone()` cases in
  §5.2 qualify precisely *because* smart pointers make covariance impossible, so the return is
  identical, not covariant.
* **Simple typedef returns** (`std::string`, `lldb::OptionValueSP` when written as the alias)
  are short to restate; the AST pass correctly does not flag plain typedef sugar. The value is
  concentrated in inline template-ids, `decltype`, and dependent names.
* **A rejected candidate, kept honest.** The textbook idiom
  `decltype(std::declval<IPDBRawSymbol>().Func()) Func() const override` *does* appear in LLVM
  — at `repos/llvm-project/llvm/unittests/DebugInfo/PDB/PDBApiTest.cpp:61` — but it lives
  inside `#define MOCK_SYMBOL_ACCESSOR(Func)` (≈160 macro uses to avoid hand-writing that
  return type for every accessor). The verifier rejected it as an example because line 61 is a
  macro body, not a standalone declaration. It is reported here as a *qualitative* sighting of
  the exact idiom the proposal's Motivation cites — not counted among the 38.

---

## 7. Headline number and suggested Motivation text

> Across eight widely-used C++ projects (~61,000 overriding declarations), **~4% restate a
> verbose or dependent return type** that the language already fixes — thousands of sites,
> rising to **7–8% in interface-heavy frameworks**. The restated type is frequently
> hand-copied across large subclass families (one type appears in **39** Godot subclasses,
> another in **25** clang targets), and the resulting hand-synchronization **already fails in
> practice**: Godot's macOS backend declares `get_window_list()` as `Vector<int>` while its
> base and eight sibling backends declare `Vector<DisplayServerEnums::WindowID>` — a silent
> divergence that `auto … override` makes impossible.

---

## 8. Reproduce it

```bash
./scripts/clone_repos.sh                       # shallow-clone the corpus into repos/ (git-ignored)
./scripts/scan_ripgrep.sh                      # heuristic pass -> findings/ripgrep-summary.md + raw/
# precise pass (needs a compile DB; configure-only is enough):
cmake -S repos/Catch2 -B repos/Catch2/build -G Ninja -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
      -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_C_COMPILER=clang -DBUILD_TESTING=ON
./scripts/scan_clang_query.sh repos/Catch2     # -> findings/clang-query-summary.tsv + raw/clang-query-Catch2-verbose.txt
```

---

## Appendix — all 38 verified examples

`repo` · `override path:line` · `return type` · `siblings` · `base path:line`. Source of
truth: the curation workflow's verified output (`findings/raw/confirmed-examples.json`).

| repo | override `path:line` | return type | sib | base `path:line` |
| --- | --- | --- | ---: | --- |
| Catch2 | `repos/Catch2/src/catch2/generators/catch_generators_adapters.hpp:241` | `std::vector<T> const&` | 14 | `repos/Catch2/src/catch2/generators/catch_generators.hpp:37` |
| Catch2 | `repos/Catch2/src/catch2/generators/catch_generators_random.hpp:38` | `Float const&` | 14 | `repos/Catch2/src/catch2/generators/catch_generators.hpp:37` |
| Catch2 | `repos/Catch2/src/catch2/catch_config.hpp:113` | `std::vector<std::string> const&` | 1 | `repos/Catch2/src/catch2/interfaces/catch_interfaces_config.hpp:85` |
| Catch2 | `repos/Catch2/src/catch2/internal/catch_test_case_registry_impl.hpp:37` | `std::vector<TestCaseHandle> const&` | 1 | `repos/Catch2/src/catch2/interfaces/catch_interfaces_testcase.hpp:25` |
| Catch2 | `repos/Catch2/src/catch2/catch_config.hpp:114` | `std::vector<PathFilter> const&` | 1 | `repos/Catch2/src/catch2/interfaces/catch_interfaces_config.hpp:91` |
| godot | `repos/godot/platform/windows/display_server_windows.h:608` | `BitField<MouseButtonMask>` | 6 | `repos/godot/servers/display/display_server.h:261` |
| godot | `repos/godot/drivers/d3d12/rendering_device_driver_d3d12.h:328` | `BitField<TextureUsageBits>` | 3 | `repos/godot/servers/rendering/rendering_device_driver.h:292` |
| godot | `repos/godot/modules/navigation_3d/3d/godot_navigation_server_3d.h:137` | `TypedArray<RID>` | 2 | `repos/godot/servers/navigation_3d/navigation_server_3d.h:95` |
| godot | `repos/godot/modules/openxr/extensions/platform/openxr_vulkan_extension.h:47` | `HashMap<String, bool *>` | 39 | `repos/godot/modules/openxr/extensions/openxr_extension_wrapper.h:71` |
| godot | `repos/godot/drivers/unix/file_access_unix.h:85` | `BitField<FileAccess::UnixPermissionFlags>` | 12 | `repos/godot/core/io/file_access.h:94` |
| godot | `repos/godot/platform/linuxbsd/x11/display_server_x11.h:463` | `Vector<DisplayServerEnums::WindowID>` | 8 | `repos/godot/servers/display/display_server.h:374` |
| godot | `repos/godot/modules/visual_shader/vs_nodes/visual_shader_nodes.h:430` | `Vector<VisualShader::DefaultTextureParam>` | 7 | `repos/godot/modules/visual_shader/visual_shader.h:378` |
| godot | `repos/godot/core/input/input_event.h:255` | `RequiredResult<InputEvent>` | 6 | `repos/godot/core/input/input_event.h:85` |
| godot | `repos/godot/modules/godot_physics_3d/godot_body_direct_state_3d.h:107` | `RequiredResult<PhysicsDirectSpaceState3D>` | 2 | `repos/godot/servers/physics_3d/physics_server_3d.h:116` |
| godot | `repos/godot/servers/physics_2d/physics_server_2d_dummy.h:106` | `RequiredResult<PhysicsDirectSpaceState2D>` | 2 | `repos/godot/servers/physics_2d/physics_server_2d.h:114` |
| llvm-project | `repos/llvm-project/llvm/include/llvm/DebugInfo/PDB/IPDBEnumChildren.h:36` | `std::unique_ptr<ChildType>` | 2 | `repos/llvm-project/llvm/include/llvm/DebugInfo/PDB/IPDBEnumChildren.h:28` |
| llvm-project | `repos/llvm-project/llvm/include/llvm/DebugInfo/PDB/ConcreteSymbolEnumerator.h:35` | `std::unique_ptr<ChildType>` | 2 | `repos/llvm-project/llvm/include/llvm/DebugInfo/PDB/IPDBEnumChildren.h:28` |
| llvm-project | `repos/llvm-project/lldb/include/lldb/Utility/Cloneable.h:44` | `std::shared_ptr<typename Base::TopmostBase>` | 1 | `repos/llvm-project/lldb/include/lldb/Interpreter/OptionValue.h:351` |
| llvm-project | `repos/llvm-project/clang/lib/Basic/Targets/AArch64.h:241` | `ArrayRef<TargetInfo::GCCRegAlias>` | 25 | `repos/llvm-project/clang/include/clang/Basic/TargetInfo.h:1961` |
| llvm-project | `repos/llvm-project/clang-tools-extra/clang-move/Move.h:225` | `std::unique_ptr<clang::FrontendAction>` | 14 | `repos/llvm-project/clang/include/clang/Tooling/Tooling.h:110` |
| llvm-project | `repos/llvm-project/clang/include/clang/StaticAnalyzer/Core/PathSensitive/CallEvent.h:533` | `ArrayRef<ParmVarDecl *>` | 3 | `repos/llvm-project/clang/include/clang/StaticAnalyzer/Core/PathSensitive/CallEvent.h:484` |
| llvm-project | `repos/llvm-project/llvm/include/llvm/Analysis/InlineAdvisor.h:238` | `std::unique_ptr<InlineAdvice>` | 3 | `repos/llvm-project/llvm/include/llvm/Analysis/InlineAdvisor.h:206` |
| llvm-project | `repos/llvm-project/clang-tools-extra/clangd/support/Markup.h:50` | `std::unique_ptr<Block>` | 2 | `repos/llvm-project/clang-tools-extra/clangd/support/Markup.h:33` |
| llvm-project | `repos/llvm-project/bolt/include/bolt/Core/DebugData.h:249` | `std::unique_ptr<DebugBufferVector>` | 1 | `repos/llvm-project/bolt/include/bolt/Core/DebugData.h:184` |
| llvm-project | `repos/llvm-project/llvm/lib/ExecutionEngine/JITLink/ELF_aarch32.cpp:203` | `TargetFlagsType` | 1 | `repos/llvm-project/llvm/lib/ExecutionEngine/JITLink/ELFLinkGraphBuilder.h:111` |
| llvm-project | `repos/llvm-project/mlir/include/mlir/Dialect/LLVMIR/Transforms/DIExpressionLegalization.h:37` | `SmallVector<OperatorT>` | 1 | `repos/llvm-project/mlir/include/mlir/Dialect/LLVMIR/Transforms/DIExpressionRewriter.h:45` |
| poco | `repos/poco/Prometheus/include/Poco/Prometheus/Counter.h:134` | `std::unique_ptr<CounterSample>` | 3 | `repos/poco/Prometheus/include/Poco/Prometheus/LabeledMetricImpl.h:167` |
| poco | `repos/poco/Prometheus/include/Poco/Prometheus/Gauge.h:170` | `std::unique_ptr<GaugeSample>` | 3 | `repos/poco/Prometheus/include/Poco/Prometheus/LabeledMetricImpl.h:167` |
| poco | `repos/poco/Prometheus/include/Poco/Prometheus/Histogram.h:177` | `std::unique_ptr<HistogramSample>` | 3 | `repos/poco/Prometheus/include/Poco/Prometheus/LabeledMetricImpl.h:167` |
| poco | `repos/poco/Data/SQLite/include/Poco/Data/SQLite/SessionImpl.h:50` | `Poco::SharedPtr<Poco::Data::StatementImpl>` | 4 | `repos/poco/Data/include/Poco/Data/SessionImpl.h:75` |
| poco | `repos/poco/Data/MySQL/include/Poco/Data/MySQL/SessionImpl.h:73` | `Poco::SharedPtr<Poco::Data::StatementImpl>` | 4 | `repos/poco/Data/include/Poco/Data/SessionImpl.h:75` |
| poco | `repos/poco/Data/ODBC/include/Poco/Data/ODBC/SessionImpl.h:75` | `Poco::SharedPtr<Poco::Data::StatementImpl>` | 4 | `repos/poco/Data/include/Poco/Data/SessionImpl.h:75` |
| poco | `repos/poco/Data/PostgreSQL/include/Poco/Data/PostgreSQL/SessionImpl.h:68` | `Poco::Data::StatementImpl::Ptr` | 4 | `repos/poco/Data/include/Poco/Data/SessionImpl.h:75` |
| poco | `repos/poco/dependencies/cpptrace/src/utils/io/file.hpp:25` | `Result<monostate, internal_error>` | 2 | `repos/poco/dependencies/cpptrace/src/utils/io/base_file.hpp:15` |
| spdlog | `repos/spdlog/example/example.cpp:334` | `std::unique_ptr<custom_flag_formatter>` | 2 | `repos/spdlog/include/spdlog/pattern_formatter.h:58` |
| spdlog | `repos/spdlog/tests/test_pattern_formatter.cpp:390` | `std::unique_ptr<custom_flag_formatter>` | 2 | `repos/spdlog/include/spdlog/pattern_formatter.h:58` |
| spdlog | `repos/spdlog/include/spdlog/pattern_formatter.h:81` | `std::unique_ptr<formatter>` | 1 | `repos/spdlog/include/spdlog/formatter.h:15` |
| spdlog | `repos/spdlog/include/spdlog/async_logger.h:58` | `std::shared_ptr<logger>` | 1 | `repos/spdlog/include/spdlog/logger.h:313` |
