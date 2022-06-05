const std = @import("std");
const debug = std.debug;

const Bot = @import("Bot.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);// std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = arena.allocator();
    defer arena.deinit();//if (gpa.deinit()) @panic("memory leaked");

    var bot = try Bot.init(allocator);
    defer bot.deinit(allocator);

    // try bot.run(allocator);
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
    // _ = @import("Bot/commands/TypingTest.zig");
}
