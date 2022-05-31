const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const testing = std.testing;

const matrix = @import("../matrix.zig");
const Bot = @import("../Bot.zig");
const CommandInput = @import("CommandInput.zig");

const Parameter = struct {
    name: []const u8,
    optional: bool,
};

const Command = struct {
    names: []const []const u8,
    parameters: ?[]const Parameter = null,
    short_description: ?[]const u8 = null,
    long_description: ?[]const u8 = null,
    implementation: type,
};

pub const commands = &[_]Command{
    .{
        .names = &.{ "blåhaj", "blahaj" },
        .implementation = @import("commands/Blåhaj.zig"),
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
        .long_description = "I will show you all the commands I have to offer.",
        .implementation = @import("commands/Help.zig"),
    },
};
