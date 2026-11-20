//! Zig 0.17 idioms, each one compiled and run by `zig test references/card.zig`.
//! If this file fails on your zig, the card is wrong for that version: trust
//! the compiler and `scripts/zig-lookup`, not this file.
//!
//! Left column of each comment is what models write from memory. It is gone.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const testing = std.testing;

// was: pub fn main() !void, std.io.getStdOut().writer(), std.process.argsAlloc,
//      GeneralPurposeAllocator(.{}){}, std.os.getenv
// main takes `std.process.Init`. It hands you io, gpa, an arena, args and env.
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa; // leak-checked in Debug
    const arena = init.arena.allocator(); // freed at exit

    const args = try init.minimal.args.toSlice(arena);
    const home = init.environ_map.get("HOME") orelse "?";

    var buf: [4096]u8 = undefined;
    var stdout_writer: Io.File.Writer = .init(.stdout(), io, &buf);
    const out = &stdout_writer.interface; // *Io.Writer
    try out.print("{d} args, home {s}\n", .{ args.len, home });
    try out.flush(); // nothing appears without this

    const text = try std.fmt.allocPrint(gpa, "{d}", .{args.len});
    defer gpa.free(text);
}

// was: std.io.getStdErr().writer(), std.os.exit
// Diagnostics go to stderr with std.debug.print, unbuffered. `std.process.fatal`
// does the print and the exit(1) in one call.
pub fn usage(program: []const u8) noreturn {
    std.debug.print("usage: {s} <path>\n", .{program});
    std.process.exit(2);
}

// was: std.ArrayList(T).init(allocator), list.append(x), list.deinit()
// Containers do not store an allocator. Start from `.empty`, pass gpa per call.
test "ArrayList and hash maps" {
    const gpa = testing.allocator;

    var list: std.ArrayList(u32) = .empty;
    defer list.deinit(gpa);
    try list.append(gpa, 1);
    try list.appendSlice(gpa, &.{ 2, 3 });
    try testing.expectEqual(3, list.pop().?);

    var map: std.StringHashMapUnmanaged(u32) = .empty;
    defer map.deinit(gpa);
    try map.put(gpa, "a", 1);
    const entry = try map.getOrPut(gpa, "b");
    if (!entry.found_existing) entry.value_ptr.* = 0;
    try testing.expectEqual(2, map.count());

    var ordered: std.AutoArrayHashMapUnmanaged(u32, []const u8) = .empty;
    defer ordered.deinit(gpa);
    try ordered.put(gpa, 7, "seven");
    try testing.expectEqualStrings("seven", ordered.values()[0]);
}

// was: std.heap.GeneralPurposeAllocator(.{}){} then gpa.deinit() == .leak
// Only needed outside main and tests, which already give you one.
test "allocators" {
    var safe: std.heap.SafeAllocator = .init(std.heap.page_allocator, .{});
    defer std.debug.assert(safe.deinit() == 0); // returns the leak count
    const gpa = safe.allocator();

    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    _ = try arena.alloc(u8, 16);

    var stack: [64]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&stack);
    _ = try fba.allocator().alloc(u8, 8);
}

// was: std.fs.cwd().openFile(path, .{}), file.readToEndAlloc, file.writer()
// Files and dirs live under std.Io and every call takes `io`.
test "files" {
    const io = testing.io;
    const gpa = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = tmp.dir; // Io.Dir.cwd() in real code

    try dir.writeFile(io, .{ .sub_path = "a.txt", .data = "one\ntwo\n" });

    const all = try dir.readFileAlloc(io, "a.txt", gpa, .limited(1 << 20));
    defer gpa.free(all);
    try testing.expectEqualStrings("one\ntwo\n", all);

    // Streaming: a File.Reader owns the buffer, `.interface` is the *Io.Reader.
    const file = try dir.openFile(io, "a.txt", .{});
    defer file.close(io);
    var buf: [256]u8 = undefined;
    var file_reader = file.reader(io, &buf);
    const r = &file_reader.interface;
    var lines: usize = 0;
    while (try r.takeDelimiter('\n')) |_| lines += 1;
    try testing.expectEqual(2, lines);

    const created = try dir.createFile(io, "b.txt", .{});
    defer created.close(io);
    var wbuf: [256]u8 = undefined;
    var file_writer = created.writer(io, &wbuf);
    try file_writer.interface.writeAll("hi");
    try file_writer.interface.flush();
}

// was: anytype writers, std.io.fixedBufferStream, list.writer(), fn format(
//      self, comptime fmt, options, writer)
// One concrete type, *Io.Writer. Custom format takes only the writer and is
// printed with {f}.
const Point = struct {
    x: i32,
    y: i32,

    pub fn format(p: Point, w: *Io.Writer) Io.Writer.Error!void {
        try w.print("({d}, {d})", .{ p.x, p.y });
    }
};

fn greet(w: *Io.Writer, name: []const u8) Io.Writer.Error!void {
    try w.print("hello {s}", .{name});
}

test "writers and formatting" {
    const gpa = testing.allocator;

    var buf: [64]u8 = undefined;
    var fixed: Io.Writer = .fixed(&buf);
    try greet(&fixed, "zig");
    try testing.expectEqualStrings("hello zig", fixed.buffered());

    var growing: Io.Writer.Allocating = .init(gpa);
    defer growing.deinit();
    try growing.writer.print("{f}", .{Point{ .x = 1, .y = 2 }});
    try testing.expectEqualStrings("(1, 2)", growing.written());

    var reader: Io.Reader = .fixed("k=v");
    try testing.expectEqualStrings("k", try reader.takeDelimiterExclusive('='));
}

// was: std.json.stringify(value, .{}, writer), std.json.stringifyAlloc
test "json" {
    const gpa = testing.allocator;
    const Config = struct { name: []const u8, port: u16 = 8080 };

    const parsed = try std.json.parseFromSlice(Config, gpa, "{\"name\":\"svc\"}", .{});
    defer parsed.deinit();
    try testing.expectEqual(8080, parsed.value.port);

    const text = try std.json.Stringify.valueAlloc(gpa, parsed.value, .{});
    defer gpa.free(text);
    try testing.expectEqualStrings("{\"name\":\"svc\",\"port\":8080}", text);

    var buf: [64]u8 = undefined;
    const printed = try std.fmt.bufPrint(&buf, "{f}", .{std.json.fmt(parsed.value, .{})});
    try testing.expectEqualStrings(text, printed);
}

// was: std.Thread.Mutex, std.time.sleep, std.time.milliTimestamp, std.time.Timer
// Locks, clocks and sleeping go through `io`.
const Counter = struct {
    mutex: Io.Mutex = .init,
    n: u64 = 0,

    fn bump(c: *Counter, io: Io) void {
        c.mutex.lockUncancelable(io);
        defer c.mutex.unlock(io);
        c.n += 1;
    }
};

fn bumpMany(c: *Counter, io: Io) void {
    for (0..1000) |_| c.bump(io);
}

test "time, locks, tasks" {
    const io = testing.io;

    const start: Io.Timestamp = .now(io, .awake);
    try io.sleep(.fromMilliseconds(1), .awake);
    const elapsed = start.durationTo(.now(io, .awake));
    try testing.expect(elapsed.toMicroseconds() >= 1000);

    var counter: Counter = .{};
    var group: Io.Group = .init;
    for (0..4) |_| group.async(io, bumpMany, .{ &counter, io });
    try group.await(io);
    try testing.expectEqual(4000, counter.n);

    // One task with a result. `async` may run it inline; `concurrent` may not.
    var future = io.async(add, .{ 2, 3 });
    try testing.expectEqual(5, future.await(io));

    // OS threads still exist when you want them.
    const t = try std.Thread.spawn(.{}, bumpMany, .{ &counter, io });
    t.join();
}

fn add(a: u32, b: u32) u32 {
    return a + b;
}

// was: std.rand, std.crypto.random
test "random" {
    var prng: std.Random.DefaultPrng = .init(42);
    const random = prng.random();
    try testing.expect(random.intRangeAtMost(u8, 1, 6) <= 6);

    var seed: [8]u8 = undefined;
    testing.io.random(&seed); // OS entropy comes from io
}

// was: @typeInfo(T).Struct.fields, .@"struct".fields[i].name, std.meta.fields
// Type info is struct-of-arrays now: field_names, field_types, field_attrs.
fn fieldNames(comptime T: type) []const [:0]const u8 {
    return @typeInfo(T).@"struct".field_names;
}

test "reflection" {
    try testing.expectEqualStrings("y", fieldNames(Point)[1]);
    const info = @typeInfo(Point).@"struct";
    inline for (info.field_names, info.field_types) |name, T| {
        try testing.expect(name.len == 1 and T == i32);
    }
    try testing.expect(@hasDecl(Point, "format"));
}

// was: std.ChildProcess.exec, std.process.Child.run(.{ .allocator = ... })
test "run a process" {
    const gpa = testing.allocator;
    const result = try std.process.run(gpa, testing.io, .{ .argv = &.{ "echo", "hi" } });
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);
    try testing.expectEqualStrings("hi\n", result.stdout);
}

// Zig only analyzes code something references. Without this, a function no
// test calls is never compiled and its errors stay hidden.
test {
    testing.refAllDecls(@This());
}
