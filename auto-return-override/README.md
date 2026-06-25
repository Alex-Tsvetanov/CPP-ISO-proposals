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
Author: Alex Tsvetanov (<Alex.Tsvetanov@acronis.com>).

## Files

| Path | Description |
| --- | --- |
| [`auto-return-override.md`](auto-return-override.md) | The proposal source (Markdown, mpark/wg21 format). |
| [`examples/before.cpp`](examples/before.cpp) | Today's boilerplate; compiles with `-std=c++20`. |
| [`examples/after.cpp`](examples/after.cpp)   | The proposed syntax (does not yet compile). |

## Building the paper (HTML / PDF)

The proposal is written for the [mpark/wg21](https://github.com/mpark/wg21)
Pandoc-based framework.

```sh
# one-time: clone the framework somewhere
git clone https://github.com/mpark/wg21.git

# from this directory, point the framework's Makefile at this file
make -C /path/to/wg21 \
     "$(pwd)/auto-return-override.pdf"   # or .html
```

See the framework's [README](https://github.com/mpark/wg21/blob/master/README.md)
for dependency installation (Pandoc, a LaTeX distribution for PDF output).

## Status

Draft **R0**. The document number `DnnnnR0` is a placeholder until a `P`-number is
assigned by the committee. See
[How To Submit a Proposal](https://isocpp.org/std/submit-a-proposal).
