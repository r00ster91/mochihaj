const std = @import("std");
const mem = std.mem;
const debug = std.debug;
const testing = std.testing;

const Bot = @import("Bot.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator); // std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = arena.allocator();
    defer arena.deinit(); //if (gpa.deinit()) @panic("memory leaked");

    var bot = try Bot.init(allocator);
    defer bot.deinit(allocator);

    try bot.run(allocator);
}

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    debug.assert(scope == .default);

    debug.getStderrMutex().lock();
    defer debug.getStderrMutex().unlock();
    const stderr = std.io.getStdErr().writer();

    // The timestamp is UTC and is useful as a reference
    const epoch_seconds = std.time.epoch.EpochSeconds{
        .secs = @intCast(u64, std.time.timestamp()),
    };
    const day_seconds = epoch_seconds.getDaySeconds();
    nosuspend stderr.print("[{d}:{d}] ", .{
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
    }) catch return;

    nosuspend stderr.print(
        @tagName(level) ++ ": " ++ format ++ "\n",
        args,
    ) catch return;
}

test {
    _ = @import("http.zig");
    _ = @import("matrix.zig");
    _ = @import("Bot/CommandInput.zig");
    _ = @import("Bot/commands/Help.zig");
}

/// Inserts `sprinkle` into `sprinklee` at every position
/// so that e.g. `sprinkleSlice(..., u8, "abc", " ")` is "a b c".
fn sprinkleSlice(allocator: mem.Allocator, comptime T: type, sprinklee: []const T, sprinkle: []const T) ![]const T {
    var sprinkled = try allocator.alloc(T, sprinklee.len + (sprinklee.len - 1) * sprinkle.len);
    var index: usize = 0;
    while (index < sprinklee.len) : (index += 1) {
        const offset = sprinkle.len + 1;
        sprinkled[index * offset] = sprinklee[index];

        if (index == sprinklee.len - 1)
            break;
        var sprinkle_index: usize = 0;
        while (sprinkle_index < sprinkle.len) : (sprinkle_index += 1)
            sprinkled[index * offset + (sprinkle_index + 1)] = sprinkle[sprinkle_index];
    }
    return sprinkled;
}

test "sprinkling slices" {
    var sprinkled = try sprinkleSlice(testing.allocator, u8, "hello world", " ");
    try testing.expectEqualSlices(u8, "h e l l o   w o r l d", sprinkled);
    testing.allocator.free(sprinkled);

    sprinkled = try sprinkleSlice(testing.allocator, u8, "hello", "__");
    try testing.expectEqualSlices(u8, "h__e__l__l__o", sprinkled);
    testing.allocator.free(sprinkled);

    sprinkled = try sprinkleSlice(testing.allocator, u8, "abc", " ");
    try testing.expectEqualSlices(u8, "a b c", sprinkled);
    testing.allocator.free(sprinkled);
}
