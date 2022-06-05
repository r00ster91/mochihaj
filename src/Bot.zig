const std = @import("std");
const log = std.log;
const json = std.json;
const mem = std.mem;

const matrix = @import("matrix.zig");
const Message = @import("Bot/Message.zig");
const Bot = @This();

next_batch: ?matrix.api.String = null,
client: matrix.Client,
filter_id: matrix.api.String,

const matrix_id = matrix.ID{ .value = "@mochihaj:catgirl.cloud" };
pub const username = matrix_id.getLocalpart();

pub fn init(allocator: mem.Allocator) !Bot {
    var matrix_client = try matrix.Client.init(allocator, matrix_id);
    errdefer matrix_client.deinit(allocator);

    const access_token = try matrix_client.login(
        allocator,
        .{
            .identifier = .{ .user = matrix_id.value },
            .password = @embedFile("../password"),
            .type = .@"m.login.password",
        },
    );
    defer allocator.free(access_token);

    const header_value = try std.fmt.allocPrint(allocator, "Bearer {s}", .{access_token});
    defer allocator.free(header_value);

    try matrix_client.http_client.setHeader(
        allocator,
        "Authorization",
        header_value,
    );

    // There are some bugs currently where using `0` for `limit` does not actually work.
    // To workaround this bug, we use `["none"]` for `types`.
    const filter_id = try matrix_client.uploadFilter(
        allocator,
        matrix_id,
        .{
            .account_data = .{ .types = &.{"none"} },
            .event_fields = &.{ "content.body", "sender" },
            .presence = .{ .types = &.{"none"} },
            .room = .{
                .account_data = .{ .types = &.{"none"} },
                .ephemeral = .{ .types = &.{"none"} },
                .timeline = .{
                    .types = &.{"m.room.message"},
                },
            },
        },
    );

    return Bot{
        .client = matrix_client,
        .filter_id = filter_id,
    };
}

pub fn deinit(self: Bot, allocator: mem.Allocator) void {
    self.client.deinit(allocator);
    if (self.next_batch) |next_batch_value|
        allocator.free(next_batch_value);
    allocator.free(self.filter_id);
}

pub fn run(self: *Bot, allocator: mem.Allocator) !void {
    var first_synchronization = true;
    while (true) {
        const state = try self.client.synchronize(
            allocator,
            self.filter_id,
            self.next_batch,
            5 * std.time.ms_per_min,
        );

        self.next_batch = try allocator.dupe(u8, state.next_batch);

        if (state.rooms) |rooms| {
            if (rooms.invite) |invite| {
                var entries = invite.iterator();
                while (entries.next()) |entry| {
                    const room_id = entry.key_ptr.*;
                    const room = entry.value_ptr.*;

                    self.client.joinRoom(allocator, room_id) catch |@"error"| {
                        switch (@"error") {
                            error.NoPermission => {
                                log.err("no permission to join room {s}", .{room_id});
                                break;
                            },
                            else => return @"error",
                        }
                    };

                    const room_is_encrypted = for (room.invite_state.events) |event| {
                        if (mem.eql(u8, event.type, "m.room.encryption"))
                            break true;
                    } else false;

                    if (room_is_encrypted) {
                        try self.client.sendMessage(
                            allocator,
                            room_id,
                            \\Hello there! You invited me to an encrypted room.
                            \\Unfortunately I'm not able to read encrypted messages because ciphertexts are so hard to understand!
                            \\
                            \\Even though it is possible to send unencrypted messages in encrypted rooms (like this message),
                            \\I don't want to encourage other people here doing it so I will be leaving for now!
                            \\
                            \\Please don't hesitate to invite me to any unencrypted rooms.
                            \\Public rooms where everyone can join are usually a good fit to be unencrypted.
                        ,
                            null,
                            true,
                        );
                        try self.client.leaveRoom(allocator, room_id);
                        try self.client.forgetRoom(allocator, room_id);
                    }
                }
            }

            // Ignoring the messages from the first synchronization
            // will ignore all messages sent while we were offline
            if (!first_synchronization) {
                if (rooms.join) |join| {
                    var entries = join.iterator();
                    while (entries.next()) |entry| {
                        const room_id = entry.key_ptr.*;
                        const room = entry.value_ptr.*;
                        for (room.timeline.events) |event| {
                            // This ignores encrypted messages.
                            // It contains the non-formatted version of the body.
                            if (event.content.get("body")) |body| {
                                if (body != .String)
                                    return error.InvalidValue;
                                const message = Message{
                                    .room_id = room_id,
                                    .body = body.String,
                                    .sender = .{ .value = event.sender orelse return error.NoMessageSender },
                                };
                                try message.handle(allocator, &self.client);
                            }
                        }
                    }
                }
            }
        }
    }
}
