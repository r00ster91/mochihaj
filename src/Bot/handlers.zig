const std = @import("std");
const log = std.log;
const mem = std.mem;
const ascii = std.ascii;
const testing = std.testing;
const fmt = std.fmt;

const matrix = @import("../matrix.zig");
const Bot = @import("../Bot.zig");
const CommandInput = @import("CommandInput.zig");

pub const Message = struct {
    room_id: []const u8,
    body: []const u8,
    sender: matrix.ID,

    pub fn handle(self: Message, allocator: mem.Allocator, bot: *Bot) !void {
        const command_input = CommandInput.parse(allocator, self.body, Bot.username) catch |@"error"| {
            switch (@"error") {
                error.OnlyMention => {
                    try bot.client.sendMessage(allocator, self.room_id, "Hello!", null, false);
                    return;
                },
                else => return @"error",
            }
        };
        if (command_input) |command|
            try handleCommand(bot, allocator, command, self);
    }
};

fn handleCommand(bot: *Bot, allocator: mem.Allocator, command_input: CommandInput, message: Message) !void {
    for (commands) |command|
        for (command.names) |command_name|
            if (mem.eql(u8, command_input.name, command_name))
                return command.action(bot, allocator, message);
}

const Parameter = struct {
    name: []const u8,
    optional: bool,
};

const Command = struct {
    names: []const []const u8,
    parameters: []const Parameter,
    short_description: ?[]const u8 = null,
    long_description: ?[]const u8 = null,
    action: fn (*Bot, mem.Allocator, Message) anyerror!void,
};

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

const commands = &[_]Command{
    .{
        .names = &.{ "blåhaj", "blahaj" },
        .parameters = &.{},
        .short_description = "List all my commands.",
        .action = struct {
            fn action(bot: *Bot, allocator: mem.Allocator, message: Message) !void {
                // mochihaj is a blåhaj in disguise
                try bot.client.sendMessage(
                    allocator,
                    message.room_id,
                    \\Please adopt one of my siblings today for only $19.99!
                    \\https://www.ikea.com/us/en/p/blahaj-soft-toy-shark-90373590/
                ,
                    null,
                    false,
                );
            }
        }.action,
    },
    .{
        .names = &.{"help"},
        .parameters = &.{
            .{
                .name = "command name",
                .optional = true,
            },
        },
        .short_description = "List all my commands.",
        .long_description = "I will show you all the commands I have to offer!",
        .action = struct {
            fn action(bot: *Bot, allocator: mem.Allocator, message: Message) !void {
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
                try bot.client.sendMessage(allocator, message.room_id, body, body, false);
            }
        }.action,
    },
};

test "listing items" {
    try testing.expectEqualStrings("A, B, and C", comptime list(&.{ "A", "B", "C" }, "and", true));
    try testing.expectEqualStrings("A, B & C", comptime list(&.{ "A", "B", "C" }, "&", false));
    try testing.expectEqualStrings("A and B", comptime list(&.{ "A", "B" }, "and", true));
    try testing.expectEqualStrings("A & B", comptime list(&.{ "A", "B" }, "&", false));
    try testing.expectEqualStrings("A", comptime list(&.{"A"}, "and", true));
}
