const std = @import("std");

const Bot = @import("Bot.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);// std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = arena.allocator();
    defer arena.deinit();//if (gpa.deinit()) @panic("memory leaked");

    var bot = try Bot.init(allocator);
    defer bot.deinit(allocator);

    try bot.run(allocator);
}

test {
    _ = @import("http.zig");
    _ = @import("matrix.zig");
    _ = @import("Bot/CommandInput.zig");
    _ = @import("Bot/handlers.zig");
}
