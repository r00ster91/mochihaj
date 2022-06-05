const std = @import("std");
const log = std.log;
const mem = std.mem;
const ascii = std.ascii;
const testing = std.testing;

const Bot = @import("../Bot.zig");
const CommandInput = @This();

/// This is lowercase.
name: []const u8,
arguments: []const []const u8,

const whitespace = &[_]u8{ ' ', '\n' };

pub fn parse(allocator: mem.Allocator, body: []const u8, mention: []const u8) (error{OnlyMention} || anyerror)!?CommandInput {
    var trimmed_body = mem.trim(u8, body, whitespace);

    trimmed_body = mem.trimLeft(u8, trimmed_body, "@");

    var tokens = mem.tokenize(u8, trimmed_body, whitespace);
    if (ascii.startsWithIgnoreCase(trimmed_body, mention)) {
        const mention_token = tokens.next().?;
        _ = mention_token;

        const command_name = if (tokens.next()) |name|
            try ascii.allocLowerString(allocator, name)
        else
            return error.OnlyMention;
        errdefer allocator.free(command_name);

        var arguments = std.ArrayList([]const u8).init(allocator);
        while (tokens.next()) |argument|
            try arguments.append(argument);

        return CommandInput{
            .name = command_name,
            .arguments = arguments.toOwnedSlice(),
        };
    } else if (ascii.endsWithIgnoreCase(trimmed_body, mention)) {
        const command_name = try ascii.allocLowerString(allocator, tokens.next().?);

        var arguments = std.ArrayList([]const u8).init(allocator);
        while (tokens.next()) |argument|
            try arguments.append(argument);

        const mention_token = arguments.popOrNull() orelse return error.OnlyMention;
        _ = mention_token;

        return CommandInput{
            .name = command_name,
            .arguments = arguments.toOwnedSlice(),
        };
    } else return null;
}

fn deinit(self: CommandInput, allocator: mem.Allocator) void {
    allocator.free(self.arguments);
    allocator.free(self.name);
}

test "parsing command name and arguments starting with mention" {
    const command = (try CommandInput.parse(testing.allocator, "mention name argument", "mention")).?;
    defer command.deinit(testing.allocator);
    try testing.expectEqualStrings(command.name, "name");
    try testing.expectEqualStrings(command.arguments[0], "argument");
    try testing.expectEqual(@as(usize, 1), command.arguments.len);
}

test "parsing command name and arguments ending with mention" {
    const command = (try CommandInput.parse(testing.allocator, "name argument mention", "mention")).?;
    defer command.deinit(testing.allocator);
    try testing.expectEqualStrings(command.name, "name");
    try testing.expectEqualStrings(command.arguments[0], "argument");
    try testing.expectEqual(@as(usize, 1), command.arguments.len);
}

test "parsing command name and arguments with whitespace" {
    const command = (try CommandInput.parse(
        testing.allocator,
        "\n mention  \n\n name  \n  argument\n name \n\nargument\n ",
        "mention",
    )).?;
    defer command.deinit(testing.allocator);
    try testing.expectEqualStrings(command.name, "name");
    try testing.expectEqualStrings(command.arguments[0], "argument");
    try testing.expectEqualStrings(command.arguments[1], "name");
    try testing.expectEqualStrings(command.arguments[2], "argument");
    try testing.expectEqual(@as(usize, 3), command.arguments.len);
}

test "parsing case-insensitive command name" {
    {
        const command = (try CommandInput.parse(testing.allocator, "mention nAmE", "mention")).?;
        defer command.deinit(testing.allocator);
        try testing.expectEqualStrings(command.name, "name");
    }
    {
        const command = (try CommandInput.parse(testing.allocator, "mention NaMe", "mention")).?;
        defer command.deinit(testing.allocator);
        try testing.expectEqualStrings(command.name, "name");
    }
}

test "parsing no command name or arguments" {
    try testing.expectError(error.OnlyMention, CommandInput.parse(
        testing.allocator,
        "mention",
        "mention",
    ));
    try testing.expectError(error.OnlyMention, CommandInput.parse(
        testing.allocator,
        " \n mention \n ",
        "mention",
    ));
}

test "parsing no command" {
    try testing.expectEqual(@as(?CommandInput, null), try CommandInput.parse(
        testing.allocator,
        "",
        "mention",
    ));
}
