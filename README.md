# zigskill

A Claude Code skill for writing Zig against the version that is installed, not the one the model remembers.

- `SKILL.md`: the loop (read the card, write, compile, look up what fails), time limits, and a short taste list.
- `references/card.zig`: current idioms next to the old spellings. It is a test file, so every example is compiled and run.
- `scripts/zig-lookup`: answers a `no member named` error from the std that ships with your zig.

## Install

```
ln -s "$PWD" ~/.claude/skills/zigskill
```

## Check the card against your zig

```
zig test references/card.zig
scripts/zig-lookup heap.GeneralPurposeAllocator
```

Verified on Zig 0.17.1. Set `ZIG=/path/to/zig` if zig is not on PATH.
