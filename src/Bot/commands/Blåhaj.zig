const std = @import("std");
const mem = std.mem;

const Message = @import("../Message.zig");
const Client = @import("../../matrix.zig").Client;

const @"Blåhaj" = @This();

pub fn run(self: @"Blåhaj", allocator: mem.Allocator, client: *Client, message: Message) !void {
    _ = self;
    try client.sendMessage(
        allocator,
        message.room_id,
        \\Please adopt one of my siblings today for only $19.99!
        \\https://www.ikea.com/us/en/p/blahaj-soft-toy-shark-90373590/
    ,
        null,
        false,
    );
}
