const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const testing = std.testing;

const Message = @import("../Message.zig");
const Client = @import("../../matrix.zig").Client;
const commands = @import("../commands.zig").commands;
const Help = @This();

pub fn run(self: Help, allocator: mem.Allocator, client: *Client, message: Message) !void {
    _ = self;
    comptime var body: []const u8 =
        \\Commands:<ul>
    ;
    inline for (commands) |command| {
        body = body ++ if (command.short_description) |description|
            fmt.comptimePrint(
                "<li>{s}: {s}</li>\n",
                .{ list(command.names, "or", true), @as([]const u8, description) },
            )
        else
            fmt.comptimePrint(
                "<li>{s}</li>\n",
                .{list(command.names, "or", true)},
            );
    }
    body = body ++ "</ul>";
    try client.sendMessage(allocator, message.room_id, body, body, false);
}

fn list(comptime items: []const []const u8, final_separator: []const u8, serial_comma: bool) []const u8 {
    if (items.len == 1) return items[0];

    comptime var result: []const u8 = "";
    for (items) |item, index| {
        result = result ++ item;
        if (index == items.len - 2) {
            if (serial_comma and items.len >= 3)
                result = result ++ ",";
            result = result ++ " " ++ final_separator ++ " ";
        } else if (index != items.len - 1) {
            result = result ++ ", ";
        }
    }
    return result;
}

test "listing items" {
    try testing.expectEqualStrings("A, B, and C", comptime list(&.{ "A", "B", "C" }, "and", true));
    try testing.expectEqualStrings("A, B & C", comptime list(&.{ "A", "B", "C" }, "&", false));
    try testing.expectEqualStrings("A and B", comptime list(&.{ "A", "B" }, "and", true));
    try testing.expectEqualStrings("A & B", comptime list(&.{ "A", "B" }, "&", false));
    try testing.expectEqualStrings("A", comptime list(&.{"A"}, "and", true));
}
