# Deduced return type for overriding functions via `auto`

A proposal for WG21 (the ISO C++ Standards Committee) to let a virtual override
written with the bare `auto` placeholder and the `override` specifier deduce its
return type from the function it overrides, removing the need to restate or
reconstruct the base return type.

```cpp
struct A { virtual int test() { return 5; } };

struct B : A {
    auto test() override { return 6; }   // deduces int, the type of A::test
};
```

Audience: **EWG** (Evolution Working Group).
Author: Alex Tsvetanov (<alex_tsvetanov_2002@abv.bg>).

## Files

| Path | Description |
| --- | --- |
| [`auto-return-override.md`](auto-return-override.md) | The proposal source (Markdown, mpark/wg21 format). |
| [`examples/before.cpp`](examples/before.cpp) | Today's boilerplate; compiles with `-std=c++20`. |
| [`examples/after.cpp`](examples/after.cpp)   | The proposed syntax (does not yet compile). |

## Building the paper (HTML / PDF)

The proposal is written for the [mpark/wg21](https://github.com/mpark/wg21)
Pandoc-based framework, which produces the WG21 cover page, side-by-side Tony
tables, and live stable-label links to the standard draft.

### This repo (Windows / Git Bash, or Linux / macOS)

[`build.sh`](build.sh) drives the framework's Pandoc command directly, so it
works on Windows where the framework's own `make`/install scripts do not. It
clones `mpark/wg21` (as a sibling `../wg21`), sets up a Python venv, downloads
the citation and stable-label databases on first run, then builds all formats:

```sh
./build.sh              # build auto-return-override.{html,latex,pdf}
./build.sh html         # build a single format (html | latex | pdf)
REFRESH=1 ./build.sh    # re-download the citation / stable-label databases
WG21_DIR=/path ./build.sh   # reuse an existing mpark/wg21 checkout
```

Requirements: Pandoc **3.9.0.2** (the version the framework pins), Python 3, and
a LaTeX engine with `xelatex` (MiKTeX or TeX Live) for the PDF. Open network is
needed on the first run only — the databases are cached in the `wg21` checkout.

### Canonical path (Linux / macOS with `make`)

```sh
git clone https://github.com/mpark/wg21.git
make -C /path/to/wg21 "$(pwd)/auto-return-override.pdf"   # or .html / .latex
```

See the framework's [README](https://github.com/mpark/wg21/blob/master/README.md)
for dependency details.

## Status

Draft **R0**. The document number `DnnnnR0` is a placeholder until a `P`-number is
assigned by the committee. See
[How To Submit a Proposal](https://isocpp.org/std/submit-a-proposal).
