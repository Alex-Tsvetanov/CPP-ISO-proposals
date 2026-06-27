# lab/ — evidence workbench for the `auto … override` proposal

This directory exists to produce the two things WG21 reviewers (Peter Dimov, Vassil
Vassilev) asked for before this proposal can progress in EWG:

1. **A solid, public use-case** — real production code where restating an override's
   return type is painful, with counts, not just a private anecdote.
2. **A working implementation** — the feature prototyped in a real compiler (Clang),
   used to verify the proposal's positive and negative cases.

Everything here is driven by [`CLAUDE.md`](./CLAUDE.md), which is the operational guide
for running the three workflows. Start there.

```
lab/
├── CLAUDE.md          # ← the guide: how to mine use-cases, patch Clang, verify
├── repos.txt          # curated public repos to clone & scan
├── scripts/           # clone / scan / test automation
├── tests/             # positive (should compile) and negative (should be rejected)
├── findings/          # scan reports (the use-case evidence)
├── repos/             # (gitignored) cloned corpora land here
└── clang/             # (gitignored) the llvm-project fork + build lives here
```

Nothing large is committed: `repos/` and `clang/` are git-ignored. Only scripts,
matchers, tests, and findings are tracked. The proposal itself is one level up at
[`../auto-return-override.md`](../auto-return-override.md).
