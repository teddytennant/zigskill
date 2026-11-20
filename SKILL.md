---
name: zigskill
description: Write Zig that compiles on the installed version and reads like Zig. Use before writing or editing any .zig file, build.zig or build.zig.zon, when a Zig compile fails with "no member named" or "no field or member function named", and when porting code to a newer Zig. Your memory of std is several releases old and this is the fast way to correct it.
---

# zigskill

The Zig you remember is a blend of 0.11 to 0.15. The std you are compiling against is newer, and the parts you reach for first all moved: stdout, allocators, files, ArrayList, JSON, mutexes, time, `@typeInfo`. Measured on 0.17.1, six ordinary programs written from memory: none compiled, and every first error was `no member named X`. The compiler tells you the name is gone and never where it went.

Checking costs less than remembering. Typechecking one file takes 0.25s on a desktop CPU. So do not study std up front. Read one short file, write the code, compile, and look up only what fails.

## The loop

1. **Find zig and its version.** `zig version`. A project's `build.zig.zon` `.minimum_zig_version` is the one that counts. If zig is not on PATH, `export ZIG=/path/to/zig` and use `$ZIG`; the lookup script reads the same variable.
2. **Read `references/card.zig` once per session.** About 250 lines. Each section shows the old spelling you would have written and the current one, and the whole file is compiled and run, so it is not someone's recollection. In an existing repo, also open the file nearest to what you are writing and copy its shape.
3. **Write the code.** All of it, not line by line.
4. **Check, cheapest first.**

   | Command | Time | Catches |
   |---|---|---|
   | `zig ast-check f.zig` | 3 ms | syntax, unused locals, shadowing |
   | `zig build-exe f.zig -fno-emit-bin` | 0.25 s | types and std names, single file |
   | `zig test f.zig` | 0.4 s | the same plus behaviour and leaks |
   | `zig build test -Dtest-filter=<name>` | seconds to minutes | the project's own gate |

5. **On `no member named` or `no field or member function named`, run one lookup:** `scripts/zig-lookup heap.GeneralPurposeAllocator`. It takes 0.2s and prints the signature if the name exists. If it does not, it prints what that namespace holds now and where else in std the name lives. Pick from that list. Do not guess a second name from memory.
6. **Format.** `zig fmt` on the files you touched.

`build.zig` is the file most often written wrong from memory. Copy the one zig ships, `$(zig env | grep -o '/[^"]*lib/std')/../init/build.zig`, and edit it.

## Time

- No reading std or the langref (1 MB of HTML) before there is an error to answer. The card plus the compiler is enough to start.
- Zig stops at the first layer of errors, so a new file takes two to four compile rounds, not one. Fix everything a round reports before the next.
- Same error after one lookup: stop trying names. Open the std file at the line `zig-lookup` printed and read the function and the `test` under it. Std tests are the usage examples.
- Three rounds on one error: write down what you tried and take the plainest alternative that compiles, or say you are stuck. Do not start a fourth guess.
- In a big tree a full build is minutes. Run `ast-check` per edit, build once per batch of edits, and filter tests to the ones you touched. Start a long build once and wait on it. Do not rebuild to see whether one line helped.

## Green is not done

- **Zig only compiles what something references.** A function no test or caller reaches is never analyzed, and its errors stay hidden behind a passing build. Confirmed on 0.17.1: a file whose only uncalled function was nonsense built with exit 0. Call new code from a test, or add `test { std.testing.refAllDecls(@This()); }` where the project does that. `zig test` on its own never compiles `main`: with that block it does, otherwise run `build-exe` as well.
- **A filtered test run can match nothing and still pass.** Break one expected value, see it fail, put it back.
- **Use `std.testing.allocator` in tests.** A leak fails the test, which is the cheapest check that your `defer` and `errdefer` are right.

## Taste

These compile and still read as another language wearing Zig.

- The allocator is a parameter, not a field. Name it for what it is: `gpa`, `arena`.
- `var list: std.ArrayList(u8) = .empty;` and `.init(...)` on a typed binding, not `T{}` or `T.init()` repeated. The result type does not flow through `catch`: `var s: T = .init(x) catch ...` fails, write `T.init(x) catch ...` there.
- `errdefer` directly after every acquisition in a function that can still fail.
- No `catch unreachable` on an error that can happen. No `anyerror` in a public signature.
- Tagged union and an exhaustive `switch`. No `else =>` over an enum you own.
- Slices and indexes before pointers. No getters and setters, no vtable for one implementation, no builder objects. An options struct with defaults is the idiom.
- A stack buffer before the heap. Before each allocation, know who frees it.
- Take `*std.Io.Writer`, not `anytype`.
- `std.debug.assert` for what must be true, an error for what the caller can cause.
- Comments say why. None that restate the line below.
- The file around you outranks this list.

## Another version

The card is for 0.17. `zig test references/card.zig` takes under a second and its failures tell you which sections are wrong for your zig. On an older pinned project the "was" line may be the right spelling. When a new release lands, fix the card until it passes again and move the old spelling into the "was" line. That is the whole maintenance.
