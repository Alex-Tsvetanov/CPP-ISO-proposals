# ripgrep heuristic scan

_Heuristic single-line pre-filter (recall-oriented; confirm magnitudes with
scan_clang_query.sh). `build/` trees excluded. Target: `repos/`._

**Denominator** = single-line declarators ending in `override`: **61474**.
**Numerator** = verbose/dependent return (dedup union of buckets): **2523**.

| bucket | hits |
| --- | ---: |
| decltype(...) | 2 |
| typename ... | 11 |
| template-id `Foo<...>` | 1826 |
| long `std::` container | 1177 |
| **verbose union** | **2523** |

## Per-repo (heuristic)

| repo | override decls | verbose/dependent | % |
| --- | ---: | ---: | ---: |
| llvm-project | 40628 | 1568 | 3.9% |
| godot | 15890 | 620 | 3.9% |
| poco | 3455 | 262 | 7.6% |
| Catch2 | 916 | 62 | 6.8% |
| fmt | 279 | 0 | 0.0% |
| json | 163 | 0 | 0.0% |
| spdlog | 126 | 9 | 7.1% |
| range-v3 | 17 | 2 | 11.8% |
| **total** | **61474** | **2523** | **4.1%** |
