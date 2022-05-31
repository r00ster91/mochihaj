const std = @import("std");
const log = std.log;
const mem = std.mem;
const ascii = std.ascii;
const testing = std.testing;
const fmt = std.fmt;

const matrix = @import("../matrix.zig");
const Bot = @import("../Bot.zig");
const CommandInput = @import("CommandInput.zig");
const commands = @import("commands.zig").commands;
const Message = @This();

room_id: []const u8,
body: []const u8,
sender: matrix.ID,

pub fn handle(self: Message, allocator: mem.Allocator, client: *matrix.Client) !void {
    inline for (commands) |command| {
        if (@hasDecl(command.implementation, "handleMessage")) {
            const handled = command.handleMessage(allocator, client, self);
            if (handled) return;
        }
    }

    const command_input = CommandInput.parse(allocator, self.body, Bot.username) catch |@"error"| {
        switch (@"error") {
            error.OnlyMention => {
                try client.sendMessage(
                    allocator,
                    self.room_id,
                    "Hello! Use mochihaj help to get to know me.",
                    "Hello! Use <b><code>mochihaj help</code></b> to get to know me.",
                    false,
                );
                return;
            },
            else => return @"error",
        }
    } orelse return;

    inline for (commands) |command| {
        for (command.names) |command_name| {
            if (mem.eql(u8, command_input.name, command_name)) {
                const implementation = if (@hasDecl(command.implementation, "init"))
                    command.implementation.init()
                else
                    command.implementation{};
                return implementation.run(allocator, client, self);
            }
        }
    }
}
